//
// Inter-core communication example by using VirtIO
//
// This example shows the use of VirtIO to communicate cores.
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

program InterCoreCom;

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
 VirtIO,
 VirtIOBus,
 Console;

{$asmmode intel}
var
 ping: PChar = 'ping'#0;
 pong: PChar = 'pong'#0;
 tmp: TThreadId;
 buff: pointer;

function Thread(param: Pointer): PtrInt;
var
  buff: pointer;
begin
  while true do
  begin
    RecvFrom(0, buff);
    SendTo(0, pong, strlen(pong)+1);
 end;
end;

begin

 tmp := BeginThread(nil, 4096, Thread, Nil, 1, tmp);

 ThreadSwitch;
 while True do
 begin
   SendTo(1, ping, strlen(ping)+1);
   RecvFrom(1, buff);
 end;

 while true do;
end.
