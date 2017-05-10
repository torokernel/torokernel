//
// TorowithFilesystem.pas
//
// This is a simple example that shows how toro can be used to read files from ext2 filesystem.
// In this example, we first read a file named index.html and then we wait for connections on port
// 80. When a connection arrives, we send the content of the file and we close the conection. The example
// also logs into a file name /web/logs to show writting operations to ext2.
//
// Changes :
//
// 04 / 05 / 2017 v2.
// 12 / 02 / 2017 Adding SysCreateFile().
// 04 / 03 / 2017 v1.
//
// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
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

program TorowithFileSystem;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{$IMAGEBASE 4194304}

// Configuring the RUN for Lazarus
{$IFDEF WIN64}
          {%RunCommand qemu-system-x86_64.exe -m 512 -smp 2 -drive format=raw,file=TorowithFileSystem.img -net nic,model=ne2k_pci -net tap,ifname=TAP2 -drive format=raw,file=ToroFiles.img -serial file:torodebug.txt}
{$ELSE}
         {%RunCommand qemu-system-x86_64 -m 512 -smp 2 -drive format=raw,file=TorowithFileSystem.img -serial file:torodebug.txt}
{$ENDIF}
{%RunFlags BUILD-}

uses
  Kernel in '..\rtl\Kernel.pas',
  Process in '..\rtl\Process.pas',
  Memory in '..\rtl\Memory.pas',
  Debug in '..\rtl\Debug.pas',
  Arch in '..\rtl\Arch.pas',
  Filesystem in '..\rtl\Filesystem.pas',
  Pci in '..\rtl\Drivers\Pci.pas',
  Ide in '..\rtl\drivers\IdeDisk.pas',
  ext2 in '..\rtl\drivers\ext2.pas',
  Console in '..\rtl\Drivers\Console.pas',
  Network in '..\rtl\Network.pas',
  Ne2000 in '..\rtl\Drivers\Ne2000.pas';

// IP values
const
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  LocalIP: array[0..3] of Byte  = (192, 100, 200, 100);

var
  HttpServer: PSocket;
  Buffer: char;
  buff: array[0..500] of char;
  tmp, log: THandle;
  HttpHandler: TNetworkHandler;
  count: longint = 0;

// Simple logger for the webserver
procedure DebugWrite(msg: pchar);
begin
  SysWriteFile(log,strlen(msg),msg);
end;

// Socket initialization
procedure HttpInit;
begin
  HttpServer := SysSocket(SOCKET_STREAM);
  HttpServer.Sourceport := 80;
  SysSocketListen(HttpServer, 50);
end;

// callback when a new connection arrives
function HttpAccept(Socket: PSocket): LongInt;
var
  tmpPing: array[0..3] of byte;
begin
  _IPAddresstoArray (Socket.DestIp, tmpPing);
  WriteConsole('\t /VToroWebServer/n: new connection from %d.%d.%d.%d\n',[tmpPing[0],tmpPing[1],tmpPing[2],tmpPing[3]]);
  DebugWrite('ToroWebServer: New connection'#13#10);
  // we wait for a new event or a timeout, i.e., 50s
  SysSocketSelect(Socket, 500000);
  Result := 0;
end;

// New data received from Socket, we can read the data and return to Network Service thread
function HttpReceive(Socket: PSocket): LongInt;
var
  tmpPing: array[0..3] of byte;
begin
  _IPAddresstoArray (Socket.DestIp, tmpPing);
  DebugWrite('ToroWebServer: Receiving Data'#13#10);
  // we keep reading until there is no more data
  while SysSocketRecv(Socket, @Buffer,1,0) <> 0 do;
  // we send the all file
  SysSocketSend(Socket, @buff[0], count, 0);
  DebugWrite('ToroWebServer: Sending Data'#13#10);
  WriteConsole ('\t /VToroWebServer/n: sending to %d.%d.%d.%d and closing connection\n',[tmpPing[0],tmpPing[1],tmpPing[2],tmpPing[3]]);
  SysSocketClose(Socket);
  Result := 0;
end;

 // Peer socket disconnected
function HttpClose(Socket: PSocket): LongInt;
var
  tmpPing: array[0..3] of byte;
begin
  _IPAddresstoArray (Socket.DestIp, tmpPing);
  WriteConsole ('\t /VToroWebServer/n: closed from remote host from %d.%d.%d.%d\n',[tmpPing[0],tmpPing[1],tmpPing[2],tmpPing[3]]);
  SysSocketClose(Socket);
  DebugWrite('ToroWebServer: Closing connection'#13#10);
  Result := 0;
end;

 // TimeOut
function HttpTimeOut(Socket: PSocket): LongInt;
begin
  WriteConsole ('\t /VToroWebServer/n: Socket: %d --> closing for timeout\n',[PtrUInt(@Socket)]);
  SysSocketClose(Socket);
  Result := 0;
end;

begin

  // Dedicate the ne2000 network card to local cpu
  DedicateNetwork('ne2000', LocalIP, Gateway, MaskIP, nil);

  // Dedicate the ide disk to local cpu
  DedicateBlockDriver('ATA0',0);

  // we mount locally
  SysMount('ext2','ATA0',6);

  // we set the call backs used by the kernel
  HttpHandler.DoInit := @HttpInit;
  HttpHandler.DoAccept := @HttpAccept;
  HttpHandler.DoTimeOut := @HttpTimeOut;
  HttpHandler.DoReceive := @HttpReceive;
  HttpHandler.DoClose := @HttpClose;

  // try to create the logs directory
  SysCreateDir('/web/logs');

  // we first try to create the file for logs
  log := SysCreateFile('/web/logs/log');
  if log = 0 then
  begin
    // if it exists we just open it
    log := SysOpenFile ('/web/logs/log');
    if log = 0 then
    begin
      WriteConsole ('logs not found\n',[]);
    end else
    begin
      // end of file
      SysSeekFile(log,0,SeekEof);
    end;
  end;

  // we open the file which is used as main page for the webserver
  tmp := SysOpenFile('/web/index.html');

  if (tmp <> 0) then
  begin
    // we read the whole file
    count := SysReadFile(tmp,sizeof(buff),@buff);
    // we close the file
    SysCloseFile(tmp);
  end else
      WriteConsole ('index.html not found\n',[]);

  // we register the web service which listens on port 80
  SysRegisterNetworkService(@HttpHandler);
  WriteConsole('\t /VToroWebServer/n: listening ...\n',[]);
  while True do
    SysThreadSwitch;
end.
