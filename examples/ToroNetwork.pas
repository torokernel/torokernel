//
// Toro Network example.
// This imple program shows how can be used the stack TCP/IP.
// The service listens at port 80 and it says "Hello" when a new connection arrives and then it closes it. 
//
// Changes :
// 2011 / 07 / 30 : Some stuff around the resource dedication
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
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

program ToroNetwork;


{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}


// Adding support for FPC 2.0.4 ;)
{$IMAGEBASE 4194304}

// They are declared just the necessary units
// The units used depend the hardware where you are running the application 
uses
  Kernel in 'rtl\Kernel.pas',
  Process in 'rtl\Process.pas',
  Memory in 'rtl\Memory.pas',
  Debug in 'rtl\Debug.pas',
  Arch in 'rtl\Arch.pas',
  Filesystem in 'rtl\Filesystem.pas',
  Network in 'rtl\Network.pas',
  Console in 'rtl\Drivers\Console.pas',
  E1000 in 'rtl\Drivers\E1000.pas';

const 
  Welcome: PChar = 'Hello from Toro!'+#13#10;
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  LocalIP: array[0..3] of Byte  = (192, 100, 200, 100);


var
  HttpServer: PSocket;

// Socket initialization
procedure HttpInit;
begin
  HttpServer := SysSocket(SOCKET_STREAM);
  HttpServer.Sourceport := 80;
  SysSocketListen(HttpServer, 50);
end;

function HttpAccept(Socket: PSocket): LongInt;
begin
  WriteConsole('New Connection on port 80\n',[0]);
  // Waiting for new data from remote host or TimeOut or RemoteClose
  SysSocketSend(Socket, Welcome, SizeOf(Welcome), 0);
  SysSocketSelect(Socket, 500000);
  Result := 0;
end;

 // New data received from Socket, we can read the data and return to Network Service thread
function HttpReceive(Socket: PSocket): LongInt;
begin
  // the socket will dead
  SysSocketClose(Socket);
  Result := 0;
end;

 // Peer socket disconnected
function HttpClose(Socket: PSocket): LongInt;
begin
  SysSocketClose(Socket);
  Result := 0;
end;

 // TimeOut
function HttpTimeOut(Socket: PSocket): LongInt;
begin
  SysSocketClose(Socket);
  Result := 0;
end;

var
  HttpHandler: TNetworkHandler;

begin
  // Dedicate the e1000 network card to local cpu
  DedicateNetwork('e1000', LocalIP, Gateway, MaskIP, nil);
  WriteConsole('Listening at port 80\n',[0]);
  // Configuration of Handlers
  HttpHandler.DoInit := @HttpInit;
  HttpHandler.DoAccept := @HttpAccept;
  HttpHandler.DoTimeOut := @HttpTimeOut;
  HttpHandler.DoReceive := @HttpReceive;
  HttpHandler.DoClose := @HttpClose;
  // Port 80, service registration
  SysRegisterNetworkService(@HttpHandler);
  while True do
    SysThreadSwitch;
end.
