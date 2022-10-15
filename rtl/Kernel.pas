//
// This unit contains the initialization of the kernel.
//
// Copyright (c) 2003-2022 Matias Vara <matiasevara@torokernel.io>
// All Rights Reserved
//
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
unit Kernel;

{$I Toro.inc}

interface

{$IFDEF DCC}
type
  PtrInt = Int64;
{$ENDIF}

// function InitSystem is declared only for compatibility
function InitSystem(notused: pointer): PtrInt; external {$IFDEF DCC} '' {$ENDIF} name 'PASCALMAIN';
procedure KernelStart;

implementation

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Console, Process, Memory, FileSystem, Network;

const
  MainThreadStackSize = 64*1024;
  {$IFDEF LINUX}
    Kernel_Head : PChar = {$I %KERNEL_HEAD%};
    Build_Time : PChar =  {$I %BUILD_TIME%};
  {$ELSE}
    Kernel_Head : PChar = '';
  {$ENDIF}

procedure KernelStart;
{$IFDEF EnableDebug}
var
  tmp: PChar;
{$ENDIF}
begin
  {$IFDEF ProfileBootTime}
    ShutdownInQemu;
  {$ENDIF}
  ConsoleInit;
  WriteConsoleF('Loading Toro ... \n', []);
  WriteConsoleF('commit: %p, build time: %p\n', [PtrUInt(Kernel_Head), PtrUInt(Build_Time)]);
  ArchInit;
  {$IFDEF EnableDebug} DebugInit; {$ENDIF}
  ProcessInit;
  MemoryInit;
  {$IFDEF EnableDebug}
    tmp := ToroGetMem(DebugRingSize);
    Panic(tmp=nil,'No memory for ring buffer for debug\n', []);
    SetDebugRing (tmp,DebugRingSize);
    WriteDebug('Debug ring buffer size: %d\n',[DebugRingSize]);
  {$ENDIF}
  FileSystemInit;
  NetworkInit;
  // we will never return from this procedure call
  {$IFDEF FPC} CreateInitThread(@InitSystem, MainThreadStackSize); {$ENDIF}
  {$IFDEF DCC}
//    CreateInitThread(@InitSystem, MainThreadStackSize);
  {$ENDIF}
end;

initialization
  {$IFDEF DCC} KernelStart; {$ENDIF}

end.



