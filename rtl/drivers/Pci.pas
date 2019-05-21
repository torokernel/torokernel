// Pci.pas
//
// This unit detects devices on pci bus.
//
// Copyright (c) 2003-2019 Matias Vara <matiasevara@gmail.com>
// All Rights Reserved
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
Unit Pci;

{$I ../Toro.inc}

interface

uses
 {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Process, Console, Memory;

type
PBusDevInfo = ^TBusDevInfo;
TBusDevInfo = record
  bus: LongInt;
  dev: LongInt;
  func: LongInt;
  irq: LongInt;
  IO: array[0..5] of UInt32;
  Vendor: UInt32;
  Device: UInt32;
  MainClass: UInt32;
  SubClass: UInt32;
  Capabilities: DWORD;
  Next: PBusDevInfo;
end;

procedure PciSetMaster(dev: PBusDevInfo);
function PciGetNextCapability(Dev: PBusDevInfo; Cap: DWORD): DWORD;
function IsPCI64Bar(Bar: DWORD): Boolean;

var
  PCIDevices: PBusDevInfo = nil;

implementation

const
  MAX_PCIBUS = 4;
  MAX_PCIDEV = 32;
  MAX_PCIFUNC = 8;
  PCI_CONF_PORT_INDEX = $CF8;
  PCI_CONF_PORT_DATA  = $CFC;
  PCI_CONFIG_INTR        = 15;
  PCI_CONFIG_CAPABILITIES = $d;
  PCI_CONFIG_VENDOR      = 0;
  PCI_CONFIG_STATUS      = 1;
  PCI_CONFIG_CLASS_REV   = 2;
  PCI_CONFIG_BASE_ADDR_0 = 4;
  PCI_STATUS_CAP_LIST = $10;

procedure PciDetect;
var
  dev, func, Bus, Vendor, Device, regnum: UInt32;
  DevInfo: PBusDevInfo;
  I, Tmp, btmp: UInt32;
  status: DWORD;
begin
  btmp := 0;
  for Bus := 0 to MAX_PCIBUS-1 do
  begin
    for dev := 0 to MAX_PCIDEV-1 do
    begin
      for func := 0 to MAX_PCIFUNC-1 do
      begin
        Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_VENDOR);
        Vendor := Tmp and $FFFF;
        Device := Tmp div 65536;
        if func = 0 then
          btmp := Device
        else if Device = btmp then
          Break;
        if (Vendor = $ffff) or (Vendor = 0) then
          Continue;
        DevInfo := ToroGetMem(SizeOf(TBusDevInfo));
        if DevInfo = nil then
          Exit;
        DevInfo.Device := Device;
        DevInfo.Vendor := Vendor;
        Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_CLASS_REV);
        DevInfo.MainClass := Tmp div 16777216;
        DevInfo.SubClass := (Tmp div 65536) and $ff;
        I := 0;
        while I < 5 do
        begin
          regnum := PCI_CONFIG_BASE_ADDR_0+I;
          Tmp := PciReadDword(Bus, dev, func, regnum);
          if Tmp and 1 = 1 then
          begin
            DevInfo.IO[I] := Tmp and $FFFFFFFC
          end
          else
          begin
            DevInfo.IO[I] := Tmp;
            if Tmp and 4 = 4 then
            begin
              Tmp := PciReadDword(Bus, dev, func, regnum + 1);
              DevInfo.IO[I+1] := Tmp;
              Inc(I);
            end;
          end;
          Inc(I);
        end;
        Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_INTR);
        DevInfo.irq := Tmp and $ff;
        DevInfo.bus := Bus;
        DevInfo.func := func;
        DevInfo.dev := dev;

        status := PciReadDword(Bus, dev, func, PCI_CONFIG_STATUS);
        status := status shr 16;

        if status and PCI_STATUS_CAP_LIST = PCI_STATUS_CAP_LIST then
          Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_CAPABILITIES)
        else
          Tmp := 0;

        Tmp := Tmp and $ff;
        DevInfo.Capabilities := Tmp;

        DevInfo.Next := PciDevices;
        PciDevices := DevInfo;
      end;
    end;
  end;
end;

procedure PciSetMaster(dev: PBusDevInfo);
var
  Tmp: Word;
begin
  Tmp := PciReadWord(dev.bus, dev.dev, dev.func, $4 );
  Tmp := Tmp or $4;
  PciWriteWord(dev.bus, dev.dev, dev.func, $4, Tmp);
end;

function PciGetNextCapability(Dev: PBusDevInfo; Cap: DWORD): DWORD;
begin
  if Cap = 0 then
  begin
    Result := Dev.Capabilities;
    Exit;
  end;
  Result := PciReadByte(Dev.bus, Dev.dev, Dev.func, Cap + 1);
end;

function IsPCI64Bar(Bar: DWORD): Boolean;
begin
 If Bar and 4 = 4 then
  Result := True
 else
  Result := False;
end;

initialization
  WriteConsoleF('Detecting Pci devices ...\n',[]);
  PciDetect;

end.
