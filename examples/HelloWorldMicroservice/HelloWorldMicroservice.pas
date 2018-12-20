//
// HelloWorldMicroservice.pas
//
// Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
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

program HelloWorldMicroservice;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{%RunCommand qemu-system-x86_64 -m 256 -smp 1 -drive format=raw,file=HelloWorldMicroservice.img -net nic,model=virtio -net tap,ifname=TAP2 -serial file:torodebug.txt}
{%RunFlags BUILD-}

uses
  Kernel in '..\..\rtl\Kernel.pas',
  Process in '..\..\rtl\Process.pas',
  Memory in '..\..\rtl\Memory.pas',
  Debug in '..\..\rtl\Debug.pas',
  Arch in '..\..\rtl\Arch.pas',
  Filesystem in '..\..\rtl\Filesystem.pas',
  Pci in '..\..\rtl\drivers\Pci.pas',
  Console in '..\..\rtl\drivers\Console.pas',
  Network in '..\..\rtl\Network.pas',
  VirtIONet in '..\..\rtl\drivers\VirtIONet.pas';

const
  // TCP-Stack configuration values
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  DefaultLocalIP: array[0..3] of Byte  = (192, 100, 200, 100);

  // port wher the service listens
  SERVICE_PORT = 8080;

  // timeout in ms
  SERVICE_TIMEOUT = 20000;

  // number of connections that can be in the queue
  SERVICE_QUEUELEN = 50;

  CRLF = #13#10;

  HeaderOK = 'HTTP/1.0 200'#13#10'Content-type: Text/Html'#13#10 + 'Content-length:';
  ContentOK = #13#10'Connection: close'#13#10 + 'Server: ToroMicroserver'#13#10''#13#10;
  HeaderNotFound = 'HTTP/1.0 404'#13#10;

  MaxKeySize = 200;


type

    PRequest = ^TRequest;
    TRequest = record
      BufferStart: pchar;
      BufferEnd: pchar;
      counter: Longint;
    end;

    // Declaration of the function used for querying the microservice
    TMicroserviceFunction = Function (Param : Pchar) : Pchar;

var
   ServiceServer: PSocket;
   ServiceHandler: TNetworkHandler;
   MyMicroFunction : TMicroserviceFunction;
   LocalIp: array[0..3] of Byte;

// Service Initialization
procedure ServiceInit;
begin
 ServiceServer := SysSocket(SOCKET_STREAM);
 ServiceServer.Sourceport := SERVICE_PORT;
 SysSocketListen(ServiceServer, SERVICE_QUEUELEN);
end;

// A new connection arrives
function ServiceAccept(Socket: PSocket): LongInt;
var
   rq: PRequest;
begin
 rq := ToroGetMem(sizeof(TRequest));
 rq.BufferStart := ToroGetMem(MaxKeySize);
 rq.BufferEnd := rq.BufferStart;
 rq.counter:= 0;
 Socket.UserDefined:= rq;
 SysSocketSelect(Socket, SERVICE_TIMEOUT);
 Result := 0;
end;

function GetRequest(Socket: PSocket): Boolean;
var
   i, Len: longint;
   buf: char;
   rq: PRequest;
   buffer: Pchar;
begin
 Result := False;
 rq := Socket.UserDefined;
 i := rq.counter;
 buffer := rq.BufferEnd;
 // Calculate len of the request
 if i <> 0 then
  Len :=  i - 4
 else
  Len := 0;
 while (SysSocketRecv(Socket, @buf,1,0) <> 0) do
 begin
  if ((i>4) and (buf = #32)) or (Len = MaxKeySize) then
  begin
    buffer^ := #0;
    Result := True;
    Exit;
  end;
  if (i>4) then
  begin
    Len := i - 4;
    buffer^ := buf;
    buffer +=1;
    rq.BufferEnd += 1;
  end;
  i+=1;
 end;

 rq.counter := i;
end;

procedure SendStream(Socket: Psocket; Stream: Pchar);
begin
 SysSocketSend(Socket, Stream, Length(Stream), 0);
end;

procedure ProcessRequest (Socket: PSocket; Answer: pchar);
var
   dst, tmp: ^char;
   anssizechar: array[0..10] of char;
   AnsSize: LongInt;
begin
 if Answer = nil then
 begin
   SendStream(Socket, HeaderNotFound);
 end
 else begin
   AnsSize := strlen(Answer);
   InttoStr(AnsSize,@anssizechar[0]);
   dst := ToroGetMem(StrLen(@anssizechar[0]) + StrLen(HeaderOk) + StrLen(ContentOK) + StrLen(Answer)+sizeof(char));
   tmp := dst;
   StrConcat(HeaderOk, @anssizechar[0], dst);
   dst := dst + StrLen(@anssizechar[0]) + StrLen(HeaderOk);
   StrConcat(dst, ContentOK, dst);
   dst := dst + StrLen(ContentOK);
   StrConcat(dst, Answer, dst);
   SendStream(Socket,tmp);
   ToroFreeMem(tmp);
 end;
end;

procedure FinishRequest(Socket: Psocket);
begin
   SysSocketClose(Socket);
end;

function ServiceClose(Socket: PSocket): LongInt;
begin
  SysSocketClose(Socket);
  Result := 0;
end;

function ServiceTimeOut(Socket: PSocket): LongInt;
var
   rq: PRequest;
begin
  rq := Socket.UserDefined;
  ToroFreeMem(rq.BufferStart);
  ToroFreeMem(rq);
  SysSocketClose(Socket);
  Result := 0;
end;

var
   connectionCount: Longint = 0;

function ServiceReceive(Socket: PSocket): LongInt;
var
   rq : PRequest;
   entry: pchar;
begin
 if GetRequest(Socket) then
 begin
   rq := Socket.UserDefined;
   entry := rq.BufferStart;
   ProcessRequest(Socket, MyMicroFunction(rq.BufferStart));
   FinishRequest(Socket);
   connectionCount := connectionCount + 1;
   //WriteConsoleF('\t Connection %d, received: %d bytes\n',[connectionCount, strlen(entry)]);
   ToroFreeMem(rq.BufferStart);
   ToroFreeMem(rq);
   Socket.UserDefined := nil;
 end else SysSocketSelect(Socket, SERVICE_TIMEOUT);
 Result := 0;
end;

const
  HelloWorldMsg = 'Hello World I am Toro!'#13#10;

function PrintHelloWorld(entry: pchar): pchar;
begin
 Result := HelloWorldMsg;
end;

begin
  If GetKernelParam(1)^ = #0 then
  begin
    DedicateNetwork('virtionet', DefaultLocalIP, Gateway, MaskIP, nil)
  end else
  begin
    IPStrtoArray(GetKernelParam(1), LocalIp);
    DedicateNetwork('virtionet', LocalIP, Gateway, MaskIP, nil);
  end;

  // register service callback
  ServiceHandler.DoInit    := @ServiceInit;
  ServiceHandler.DoAccept  := @ServiceAccept;
  ServiceHandler.DoTimeOut := @ServiceTimeOut;
  ServiceHandler.DoReceive := @ServiceReceive;
  ServiceHandler.DoClose   := @ServiceClose;

  // register the main service function
  MyMicroFunction := @PrintHelloWorld;

  // create the service
  SysRegisterNetworkService(@ServiceHandler);

  WriteConsoleF('\t /VToroService/n: listening on port %d ...\n',[SERVICE_PORT]);

  SysSuspendThread(0);
end.
