//
// VirtIO.pas
//
// This unit contains functions to deal with VirtIO modern devices.
//
// Copyright (c) 2003-2020 Matias Vara <matiasevara@gmail.com>
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

unit VirtIO;

interface

{$I ..\Toro.inc}

{$IFDEF EnableDebug}
       //{$DEFINE DebugVirtioFS}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Console, Network, Process, Memory;

type
  PVirtIOMMIODevice = ^TVirtIOMMIODevice;
  
  TVirtIOMMIODevice = record
    Base: QWord;
    Irq: byte;
  end;

const
  MAX_MMIO_DEVICES = 2;

var
  VirtIOMMIODevices: array[0..MAX_MMIO_DEVICES-1] of TVirtIOMMIODevice;
  VirtIOMMIODevicesCount: LongInt = 0;
 
implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

function startsWith(p1, p2: PChar): Boolean;
var
  j: LongInt;
begin
  Result := false;
  if strlen(p2) > strlen(p1) then
    Exit;
  for j:= 0 to (strlen(p2)-1) do
  begin
    if p1[j] <> p2[j] then
      Exit;
  end;
  Result := True;
end;

function LookForChar(p1: PChar; c: Char): PChar;
begin
  Result := nil;
  while (p1^ <> Char(0)) and (p1^ <> c) do
  begin
    Inc(p1);
  end;
  if p1^ = Char(0) then
    Exit;
  Result := p1; 
end;

function HexStrtoQWord(start, last: PChar): QWord;
var
  bt: Byte;
  i: PChar;
  Base: QWord;
begin
  i := start;
  Base := 0;
  while (i <> last) do
  begin
    bt := Byte(i^);
    Inc(i);
    if (bt >= Byte('0')) and (bt <= Byte('9')) then
      bt := bt - Byte('0')
    else if (bt >= Byte('a')) and (bt <= Byte('f')) then
      bt := bt - Byte('a') + 10
    else if (bt >= Byte('A')) and (bt <= Byte('F')) then
      bt := bt - Byte('A') + 10; 
    Base := (Base shl 4) or (bt and $F);
  end;
  Result := Base;
end;

function StrtoByte(p1: PChar): Byte;
var
  ret: Byte;
begin
  ret := 0;
  while p1^ <> Char(0) do
  begin
    ret := ret * 10 + Byte(p1^) - Byte('0');
    Inc(p1);
  end;
  Result := ret;
end;

// parse the kernel command-line to get the device tree
procedure FindVirtIOMMIODevices;
var
  j: LongInt;
  Base: QWord;
  Irq: Byte;
begin
  for j:= 1 to KernelParamCount do 
  begin
    if startsWith (GetKernelParam(j), 'virtio_mmio') then
    begin
      Base := HexStrtoQWord(LookForChar(GetKernelParam(j), '@') + 3 , LookForChar(GetKernelParam(j), ':'));
      Irq := StrtoByte(LookForChar(GetKernelParam(j), ':') + 1);
      VirtIOMMIODevices[VirtIOMMIODevicesCount].Base := Base;
      VirtIOMMIODevices[VirtIOMMIODevicesCount].Irq := Irq;
      Inc(VirtIOMMIODevicesCount);
      WriteConsoleF('VirtIO: found device at %h:%d\n', [Base, Irq]);
    end;
  end;
end;

initialization
  FindVirtIOMMIODevices;
end.
