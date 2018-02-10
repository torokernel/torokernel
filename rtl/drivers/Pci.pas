// Pci.pas
//
//
// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
// All Rights Reserved
//
// 07/ 05/ 2017 First version.
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

// {$DEFINE DebugPci}

interface

uses
  Arch, Process, Console, Memory, Debug;

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
  Next: PBusDevInfo;
end;

procedure PciSetMaster(dev: PBusDevInfo);

// List of the pci devices
var
  PCIDevices: PBusDevInfo = nil;

implementation

const
 ADDPCISTART = $e0000;
 MAX_PCIBUS = 4;
 MAX_PCIDEV = 32;
 MAX_PCIFUNC = 8;
 PCI_CONF_PORT_INDEX = $CF8;
 PCI_CONF_PORT_DATA  = $CFC;
 PCI_CONFIG_INTR        = 15;
 PCI_CONFIG_VENDOR      = 0;
 PCI_CONFIG_CLASS_REV   = 2;
 PCI_CONFIG_BASE_ADDR_0 = 4;
 PCI_BAR                = $10;

type
  PBios32 = ^TBios32;
  TBios32 = record
    Magic: LongInt;
    phys_entry: LongInt;
    Revision: Byte;
    Length : Byte;
    CRC: XChar;
    Reserved: array [1..5] of Byte;
 end;

// Detect all devices in PCI Buses
// brute force algorithm to find pci devices
procedure PciDetect;
var
  dev, func, Bus, Vendor, Device, regnum: UInt32;
  DevInfo: PBusDevInfo;
  I, Tmp, btmp: UInt32;
begin
  btmp := 0;
  for Bus := 0 to MAX_PCIBUS-1 do
  begin
    for dev := 0 to MAX_PCIDEV-1 do
    begin
      {$IFDEF DebugPci} WriteDebug('PciDetect - Bus: %d Dev: %d', [Bus, Dev]); {$ENDIF}
      for func := 0 to MAX_PCIFUNC-1 do
      begin
        {$IFDEF DebugPci} WriteDebug('PciDetect - Before PciReadDword Bus: %q dev: %d func: %d', [Bus, dev, func]); {$ENDIF}
        Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_VENDOR);
        {$IFDEF DebugPci} WriteDebug('PciDetect - PciReadDword PCI_CONFIG_VENDOR func: %d Tmp: %h', [Tmp, func]); {$ENDIF}
        Vendor := Tmp and $FFFF;
        Device := Tmp div 65536;
        // some bug
        if func = 0 then
          btmp := Device
        else if Device = btmp then
          Break;
        // check if the device exists
        if (Vendor = $ffff) or (Vendor = 0) then
          Continue;
        DevInfo := ToroGetMem(SizeOf(TBusDevInfo));
        // memory problem
        if DevInfo = nil then
          Exit;
        DevInfo.Device := Device;
        DevInfo.Vendor := Vendor;
        Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_CLASS_REV);
        {$IFDEF DebugPci} WriteDebug('PciDetect - PciReadDword PCI_CONFIG_CLASS_REV func: %d Tmp: %h', [Tmp, func]); {$ENDIF}
        DevInfo.MainClass := Tmp div 16777216;
        DevInfo.SubClass := (Tmp div 65536) and $ff;
        for I := 0 to 5 do
        begin
          regnum := PCI_CONFIG_BASE_ADDR_0+I;
          {$IFDEF DebugPci} WriteDebug('PciDetect - Before PciReadDword Bus: %q dev: %d func: %d', [Bus, dev, func]); {$ENDIF}
          {$IFDEF DebugPci} WriteDebug('PciDetect - Before PciReadDword I: %d', [I]); {$ENDIF}
          Tmp := PciReadDword(Bus, dev, func, regnum);
          {$IFDEF DebugPci} WriteDebug('PciDetect - After PciReadDword Bus: %q dev: %d func: %d', [Bus, dev, func]); {$ENDIF}
          {$IFDEF DebugPci} WriteDebug('PciDetect - PciReadDword PCI_CONFIG_BASE_ADDR_0+%d, Tmp: %h', [Tmp, I]); {$ENDIF}
          if (Tmp and 1) = 1 then
          begin
            // the devices is accesed by a io port
            DevInfo.IO[I] := Tmp and $FFFFFFFC // IO port
          end else begin
            // the devices is memory mapped
            DevInfo.IO[I] := Tmp;
          end;
        end;
        Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_INTR);
        {$IFDEF DebugPci} WriteDebug('PciDetect - PciReadDword PCI_CONFIG_INTR, func: %d, Tmp: %h', [Tmp, func]); {$ENDIF}
        DevInfo.irq := Tmp and $ff;
        DevInfo.bus := Bus;
        DevInfo.func := func;
        DevInfo.dev := dev;
        // the devices is enqueued
        DevInfo.Next := PciDevices;
        PciDevices := DevInfo;
      end;
    end;
  end;
end;

// PciSetMaster:
// set a device as bus mastering. This is used for e1000 driver that runs
// as master
//
procedure PciSetMaster(dev: PBusDevInfo);
var
  Tmp: Word;
begin
 Tmp := PciReadWord(dev.bus, dev.dev, dev.func, $4 );
 Tmp := Tmp or $4;
 PciWriteWord(dev.bus, dev.dev, dev.func, $4, Tmp);
end;

initialization
WriteConsoleF('Detecting Pci devices ...\n',[]);
PciDetect;

end.
