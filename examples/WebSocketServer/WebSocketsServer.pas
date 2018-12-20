//
// WebSocketsServer.pas
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

program WebSocketsServer;

{$mode delphi}
{$DEFINE FAT}
{. $DEFINE EXT2}
{. $DEFINE DebugWebServer}

{%RunCommand qemu-system-x86_64 -m 256 -smp 1 -drive format=raw,file=WebSocketsServer.img -net nic,model=virtio -net tap,ifname=TAP2 -drive file=fat:rw:WebSocketsFiles -serial file:torodebug.txt}
{%RunFlags BUILD-}

uses
  Kernel in '..\..\rtl\Kernel.pas',
  Process in '..\..\rtl\Process.pas',
  Memory in '..\..\rtl\Memory.pas',
  Debug in '..\..\rtl\Debug.pas',
  Arch in '..\..\rtl\Arch.pas',
  Ide in '..\..\rtl\drivers\IdeDisk.pas',
  {$IFDEF FAT} Fat in '..\..\rtl\drivers\Fat.pas', {$ENDIF}
  {$IFDEF EXT2} Ext2 in '..\..\rtl\drivers\Ext2.pas', {$ENDIF}
  Filesystem in '..\..\rtl\Filesystem.pas',
  Pci in '..\..\rtl\drivers\Pci.pas',
  Console in '..\..\rtl\drivers\Console.pas',
  Network in '..\..\rtl\Network.pas',
  VirtIONet in '..\..\rtl\drivers\VirtIONet.pas',
  WebSockets in 'WebSockets.pas';

const
  // Network address
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  DefaultLocalIP: array[0..3] of Byte  = (192, 100, 200, 100);

  HTTP_PORT = 80;
  HTTPSERVER_TIMEOUT = 20000;
  HTTPSERVER_QUEUELEN = 50;
  CRLF = #13#10;
  HttpHeaderOK = 'HTTP/1.1 200 OK'#13#10;
  HttpHeaderNotFound = 'HTTP/1.1 404 Not Found'#13#10;

type
  PHttpRequest = ^THttpRequest;
  THttpRequest = record
    Buffer: TXBuffer;
    Socket: PSocket;
  end;

procedure HttpRequestCreate(Socket: PSocket);
var
  HttpRequest: PHttpRequest;
begin
  {$IFDEF DebugWebServer} WriteDebug('HttpRequestCreate ...\n', []); {$ENDIF}
  HttpRequest := ToroGetMem(SizeOf(THttpRequest));
  XBufferCreate(HttpRequest.Buffer, nil, 1024);
  HttpRequest.Socket := Socket;
  Socket.UserDefined := HttpRequest;
  {$IFDEF DebugWebServer} WriteDebug('HttpRequestCreate Done.\n', []); {$ENDIF}
end;

procedure HttpRequestFree(HttpRequest: PHttpRequest);
begin
  if HttpRequest = nil then
    Exit;
  {$IFDEF DebugWebServer} WriteDebug('HttpRequestFree ...\n', []); {$ENDIF}
  HttpRequest.Socket.UserDefined := nil;
  XBufferFree(HttpRequest.Buffer);
  ToroFreeMem(HttpRequest);
  {$IFDEF DebugWebServer} WriteDebug('HttpRequestFree Done.\n', []); {$ENDIF}
end;


function HttpRequestGetHeaders(HttpRequest: PHttpRequest): Boolean;
var
  Buffer: PXChar;
  ReceivedBytes: Int32;
begin
  {$IFDEF DebugWebServer} WriteDebug('HttpRequestGetHeaders...', []); {$ENDIF}
  Result := False;
  while True do
  begin
    Buffer := @HttpRequest.Buffer.Buf[HttpRequest.Buffer.Size];
    //{$IFDEF DebugWebServer} WriteDebug('HttpRequestGetHeaders - Socket.BufferLength: %d\n', [HttpRequest.Socket.BufferLength]); {$ENDIF}
    //{$IFDEF DebugWebServer} WriteDebug('HttpRequestGetHeaders - HttpRequest.Buffer.Capacity-HttpRequest.Buffer.Size: %d\n', [HttpRequest.Buffer.Capacity-HttpRequest.Buffer.Size]); {$ENDIF}
    ReceivedBytes := SysSocketRecv(HttpRequest.Socket, Buffer, HttpRequest.Buffer.Capacity-HttpRequest.Buffer.Size, 0);
    //{$IFDEF DebugWebServer} WriteDebug('HttpRequestGetHeaders - ReceivedBytes: %d\n', [ReceivedBytes]); {$ENDIF}
    if ReceivedBytes = 0 then
      Break;
    Inc(HttpRequest.Buffer.Size, ReceivedBytes);
  end;
  Result := True;
  {$IFDEF DebugWebServer} WriteDebug('HttpRequestGetHeaders Done.', []); {$ENDIF}
end;

procedure SocketSend(Socket: PSocket; const Buffer: TXBuffer);
begin
  SysSocketSend(Socket, @Buffer.Buf[0], Buffer.Size, 0);
end;

procedure SendHttpResponse(Socket: PSocket; const Content: TXBuffer; const ContentType: XString);
var
  Headers: TXBuffer;
  HeadersBuf: TXBuffer1K;
begin
  {$IFDEF DebugWebServer} WriteDebug('SendHttpResponse...\n', []); {$ENDIF}
  XBufferFromVar(Headers, @HeadersBuf, SizeOf(HeadersBuf), nil);
  if Content.Size = 0 then
    XBufferAppend(Headers, HttpHeaderNotFound)
  else
  begin
    XBufferAppend(Headers, HttpHeaderOK);
    XBufferAppend(Headers, 'Content-Type: ');
    XBufferAppend(Headers, ContentType);
    XBufferAppend(Headers, #13#10);
  end;
  XBufferAppend(Headers, 'Content-Length: ');
  XBufferAppendInt(Headers, Content.Size);
  XBufferAppend(Headers, #13#10);
  XBufferAppend(Headers, 'Connection: close'#13#10);
  XBufferAppend(Headers, 'Server: ToroMicroserver'#13#10);
  XBufferAppend(Headers, #13#10);
  {$IFDEF DebugWebServer} WriteDebug('SocketSend...\n', []); {$ENDIF}
  SocketSend(Socket, Headers);
  {$IFDEF DebugWebServer} WriteDebug('SendHttpResponse Done.\n', []); {$ENDIF}
  if Content.Size > 0 then
    SocketSend(Socket, Content);
end;

var
  HttpServer: PSocket;
  HttpServerHandler: TNetworkHandler;
  Favicon_ico: TXBuffer;
  Index_htm: TXBuffer;

procedure HttpServerInit;
begin
  HttpServer := SysSocket(SOCKET_STREAM);
  HttpServer.SourcePort := HTTP_PORT;
  SysSocketListen(HttpServer, HTTPSERVER_QUEUELEN);
end;

function HttpServerAccept(Socket: PSocket): LongInt;
begin
  HttpRequestCreate(Socket);
  {$IFDEF DebugWebServer} WriteDebug('HttpServerAccept - SysSocketSelect(Socket, HTTPSERVER_TIMEOUT)...\n', []); {$ENDIF}
  SysSocketSelect(Socket, HTTPSERVER_TIMEOUT);
  Result := 0;
end;

function HttpServerClose(Socket: PSocket): LongInt;
begin
  HttpRequestFree(Socket.UserDefined);
  Socket.UserDefined := nil;
  SysSocketClose(Socket);
  Result := 0;
end;

function HttpServerTimeOut(Socket: PSocket): LongInt;
begin
  HttpRequestFree(Socket.UserDefined);
  Socket.UserDefined := nil;
  SysSocketClose(Socket);
  Result := 0;
end;

function HttpServerReceive(Socket: PSocket): LongInt;
var
  HttpRequest : PHttpRequest;
begin
  Result := 0;
  HttpRequest := Socket.UserDefined;
  if not HttpRequestGetHeaders(HttpRequest) then
  begin
    SysSocketSelect(Socket, HTTPSERVER_TIMEOUT);
    Exit;
  end;
  HttpRequest := Socket.UserDefined;
  if XPos('favicon.ico', HttpRequest.Buffer.AsString, 1) > 0 then
  begin
    WriteConsoleF('HttpServerReceive -> favicon.ico\n', []);
    SendHttpResponse(Socket, Favicon_ico, 'image/x-icon')
  end else
  begin
    WriteConsoleF('HttpServerReceive -> index.html\n', []);
    SendHttpResponse(Socket, Index_htm, 'text/html');
  end;
  SysSocketClose(Socket);
  HttpRequestFree(HttpRequest);
end;

const
  HelloWorldMsg = 'Hello World from Toro!'#13#10;

procedure PreloadFile(const FileName: PXChar; var Buffer: TXBuffer);
var
  FileHandle: THandle;
  INode: TINode;
begin
  XBufferClear(Buffer);
  if SysStatFile(FileName, @INode) = 0 then
  begin
    WriteConsoleF('SysStatFile %p not found\n', [PtrUInt(FileName)]);
    Exit;
  end;
  XBufferCreate(Buffer, nil, INode.Size);
  FileHandle := SysOpenFile(FileName);
  if FileHandle = 0 then
  begin
    WriteConsoleF('SysOpenFile %p not found\n', [PtrUInt(FileName)]);
    Exit;
  end;
  //XBufferFromXString(Index_htm, HelloWorldMsg, nil);
  Buffer.Size := SysReadFile(FileHandle, INode.Size, @Buffer.Buf[0]);
  SysCloseFile(FileHandle);
  WriteConsoleF('\t /VToroWebSockets/n: loaded, Size: %d bytes\n', [Buffer.Size]);
end;

procedure TestWebSocket;
var
  WebSocket: TWebSocket;
begin
  //WriteConsoleF('TestWebSocket Create\n', []);
  WebSocket := XObjCreate(TWebSocket, nil);
  //WriteConsoleF('TestWebSocket Free\n', []);
  WebSocket.Free;
  //WriteConsoleF('TestWebSocket Done\n', []);
end;

var
  LocalIp: array[0..3] of Byte;
begin
  If GetKernelParam(1)^ = #0 then
  begin
    DedicateNetwork('virtionet', DefaultLocalIP, Gateway, MaskIP, nil)
  end else
  begin
    IPStrtoArray(GetKernelParam(1), LocalIp);
    DedicateNetwork('virtionet', LocalIP, Gateway, MaskIP, nil);
  end;
  DedicateNetwork('virtionet', LocalIP, Gateway, MaskIP, nil);
  DedicateBlockDriver('ATA0', 0);
  {$IFDEF EXT2} SysMount('ext2', 'ATA0', 5); {$ENDIF}
  {$IFDEF FAT} SysMount('fat', 'ATA0', 6); {$ENDIF}
  PreloadFile('/web/index.htm', Index_htm);
  PreloadFile('/web/favicon.ico', Favicon_ico);
  InitNetworkService(HttpServerHandler, HttpServerInit, HttpServerAccept, HttpServerReceive, HttpServerClose, HttpServerTimeOut);
  SysRegisterNetworkService(@HttpServerHandler);
  WriteConsoleF('\t /VWebServer/n: listening on port %d ...\n', [HTTP_PORT]);
  TestWebSocket;
  WebSocketsCreate;

  SysSuspendThread(0);
end.
