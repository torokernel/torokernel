//
// Toro Http example.
//
// This imple program shows how can be used the stack TCP/IP.
// The service listens at port 80 and it says "Hello" when a new
// connection arrives and then it closes it.
//
// Changes :
// 2017 / 01 / 04 : Minor fixes
// 2016 / 12 / 22 : First working version by Matias Vara
// 2011 / 07 / 30 : Some stuff around the resource dedication
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

unit uToroHttp;

{$mode delphi}

interface


Procedure Main;

implementation

uses
  Console,Network;

const
  Welcome: PChar = '<b>Hello from Toro!</b>'+#13#10;
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  LocalIP: array[0..3] of Byte  = (192, 100, 200, 100);

var
  HttpServer: PSocket;
  Buffer: char;

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
  SysSocketSend(Socket, Welcome, strlen(Welcome), 0);
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

Procedure Main;
var
  HttpHandler: TNetworkHandler;
begin
  // Dedicate the ne2000 network card to local cpu
  DedicateNetwork('ne2000', LocalIP, Gateway, MaskIP, nil);
  WriteConsole('Listening at port 80\n',[0]);
  // we set the call backs used by the kernel
  HttpHandler.DoInit := @HttpInit;
  HttpHandler.DoAccept := @HttpAccept;
  HttpHandler.DoTimeOut := @HttpTimeOut;
  HttpHandler.DoReceive := @HttpReceive;
  HttpHandler.DoClose := @HttpClose;
  // we register the service
  SysRegisterNetworkService(@HttpHandler);
end;
end.

