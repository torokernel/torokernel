//
// Scheduler Example
//
// This example shows the use of the multicore scheduler.
//
// Copyright (c) 2003-2022 Matias Vara <matiasevara@gmail.com>
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

program Scheduler;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

// only include the needed units
uses
 Kernel,
 Process,
 Memory,
 Debug,
 Arch,
 Filesystem,
 {$IFDEF UseGDBstub}VirtIO,{$ENDIF}
 Network,
 {$IFDEF UseGDBstub}VirtIOConsole,
 Gdbstub,
 {$ENDIF}
 Console;

procedure ShutdownHelloWorld;
begin
  // do something
end;

function Thread(param: Pointer): PtrInt;
begin
  //while true do
  //begin
    WriteConsoleF('Hello from %d at %d\n', [PtrUInt(param), GetCoreId]);
    //ThreadSwitch;
  //end;
end;
var
  tmp: TThreadId;
begin
  ShutdownProcedure := ShutdownHelloWorld;
  WriteConsoleF('Starting threads ...\n',[]);
  tmp := BeginThread(nil, 4096, Thread, Pointer(0), 0, tmp);
  tmp := BeginThread(nil, 4096, Thread, Pointer(1), 1, tmp);
  //tmp := BeginThread(nil, 4096, Thread, Pointer(2), 2, tmp);
  While True do ThreadSwitch;
end.
