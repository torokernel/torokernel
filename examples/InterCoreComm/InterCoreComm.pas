//
// Inter-core communication by using VirtIO
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
 Network,
 VirtIO,
 {$IFDEF UseGDBstub}
 VirtIOConsole,
 Gdbstub,
 {$ENDIF}
 VirtIOBus,
 Console;

var
 ping: PChar = 'ping'#0;
 pong: PChar = 'pong'#0;
 tmp: TThreadId;
 buff: array[0..VIRTIO_CPU_MAX_PKT_BUF_SIZE-1] of Char;

function Thread(param: Pointer): PtrInt;
var
  buff: array[0..VIRTIO_CPU_MAX_PKT_BUF_SIZE-1] of Char;
  id: DWORD;
begin
  id := PtrUInt(param);
  while true do
  begin
    RecvFrom(id, @buff[0]);
    WriteConsoleF('Core[%d] -> Core[%d]: %p\n', [id, GetCoreId, PtrUInt(@buff[0])]);
    SendTo(id, pong, strlen(pong)+1);
  end;
end;

begin
 tmp := BeginThread(nil, 4096, Thread, Pointer(0), 1, tmp);
 tmp := BeginThread(nil, 4096, Thread, Pointer(0), 2, tmp);
 ThreadSwitch;
 while True do
 begin
   SendTo(1, ping, strlen(ping)+1);
   RecvFrom(1, @buff[0]);
   WriteConsoleF('Core[%d] -> Core[%d]: %p\n', [1, GetCoreId, PtrUInt(@buff[0])]);
   SendTo(2, ping, strlen(ping)+1);
   RecvFrom(2, @buff[0]);
   WriteConsoleF('Core[%d] -> Core[%d]: %p\n', [2, GetCoreId, PtrUInt(@buff[0])]);
 end;
end.
