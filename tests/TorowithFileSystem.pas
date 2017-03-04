//
// Toro Hello World Example.
// Clasical example using a minimal kernel to print "Hello World"
//
// Changes :
// 
// 16/09/2011 First Version by Matias E. Vara.
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
  p: array[0..500] of char;
  tmp: THandle;
  HttpHandler: TNetworkHandler;
  count: longint = 0;

// Socket initialization
procedure HttpInit;
begin
  HttpServer := SysSocket(SOCKET_STREAM);
  HttpServer.Sourceport := 80;
  SysSocketListen(HttpServer, 50);
end;

// callback when a new connection arrives
function HttpAccept(Socket: PSocket): LongInt;
begin
  WriteConsole('New connection on port 80\n',[0]);
  // we wait for a new event or a timeout, i.e., 50s
  SysSocketSelect(Socket, 500000);
  Result := 0;
end;

// New data received from Socket, we can read the data and return to Network Service thread
function HttpReceive(Socket: PSocket): LongInt;
begin
  // we keep reading until there is no more data
  while SysSocketRecv(Socket, @Buffer,1,0) <> 0 do;
  SysSocketSend(Socket, @p[0], 178, 0);
  WriteConsole ('Closing conection\n',[]);
  // todo: this can close the socket two times!!!!!
  SysSocketClose(Socket);
  Result := 0;
end;

 // Peer socket disconnected
function HttpClose(Socket: PSocket): LongInt;
begin
  WriteConsole ('Remote Host Closed the conection\n',[]);
  SysSocketClose(Socket);
  Result := 0;
end;

 // TimeOut
function HttpTimeOut(Socket: PSocket): LongInt;
begin
  WriteConsole ('Closing connection for timeout\n',[]);
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

  // we open the file which is used as main page for the webserver
  tmp := SysOpenFile('/web/index.html');
  // we read the whole file first
  while SysReadFile(tmp,1,@p[count]) <> 0 do count := count +1;
  // by closing we free resources
  SysCloseFile(tmp);

  // we register the web service so we start to listening at port 80
  SysRegisterNetworkService(@HttpHandler);
  WriteConsole('\c/VToroWebServer/n: listening at port 80\n',[0]);
  while True do
    SysThreadSwitch;
end.
