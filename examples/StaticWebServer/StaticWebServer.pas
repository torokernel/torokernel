//
// StaticWebServer.pas
//
// Copyright (c) 2003-2019 Matias Vara <matiasevara@gmail.com>
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

program StaticWebServer;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{%RunCommand qemu-system-x86_64 -m 256 -smp 1 -drive format=raw,file=StaticWebServer.img -net nic,model=virtio -net tap,ifname=TAP2 -drive file=fat:rw:StaticWebServerFiles,if=none,id=drive-virtio-disk0 -device virtio-blk-pci,drive=drive-virtio-disk0,addr=06 -serial file:torodebug.txt}
{%RunFlags BUILD-}

uses
  Kernel in '..\..\rtl\Kernel.pas',
  Process in '..\..\rtl\Process.pas',
  Memory in '..\..\rtl\Memory.pas',
  Debug in '..\..\rtl\Debug.pas',
  Arch in '..\..\rtl\Arch.pas',
  Filesystem in '..\..\rtl\Filesystem.pas',
  VirtIO in '..\..\rtl\drivers\VirtIO.pas',
  VirtIOFS in '..\..\rtl\drivers\VirtIOFS.pas',
  VirtIOVSocket in '..\..\rtl\drivers\VirtIOVSocket.pas',
  Console in '..\..\rtl\drivers\Console.pas',
  Network in '..\..\rtl\Network.pas';

const
  HeaderNotFound = 'HTTP/1.1 404 File not found'#13#10'Connection: close'#13#10'Content-Length: 0'#13#10#13#10;
  SERVICE_TIMEOUT = 20000;
  Max_Path_Len = 200;
  SERVICE_BACKLOG = 100;

type
  PRequest = ^TRequest;
  TRequest = record
    BufferStart: pchar;
    BufferEnd: pchar;
    Counter: Longint;
  end;

var
  HttpServer, HttpClient: PSocket;
  Request: PRequest;
  ThreadID: TThreadID;

function FetchHttpRequest(Socket: PSocket): Boolean;
var
  Buf: Char;
  Buffer: PChar;
  I, Len: LongInt;
  Request: PRequest;
begin
  Result := False;
  Request:= Socket.UserDefined;
  I := Request.Counter;
  Buffer := Request.BufferEnd;
  // Calculate len of the request
  if I <> 0 then
    Len := I-3
  else
    Len := 0;
  while SysSocketRecv(Socket, @buf, 1, 0) <> 0 do
  begin
    if ((i > 3) and (buf = #32)) or (Len = Max_Path_Len) then
    begin
      Buffer^ := #0;
      Result := True;
      Exit;
    end;
    if I > 3 then
    begin
      Len := I-3;
      Buffer^ := buf;
      Inc(Buffer);
      Inc(Request.BufferEnd);
    end;
    Inc(I);
  end;
  Request.Counter := I;
end;

function GetContentType(const FileName: PChar): PChar;
begin
  if StrCmp(PChar(FileName+StrLen(FileName)-4), 'html', 4) then
    Result := 'text/html'
  else if StrCmp(PChar(FileName+StrLen(FileName)-3), 'htm', 3) then
    Result := 'text/html'
  else if StrCmp(PChar(FileName+StrLen(FileName)-4), 'json', 4) then
    Result := 'text/json'
  else if StrCmp(PChar(FileName+StrLen(FileName)-3), 'css', 3) then
    Result := 'text/css'
  else if StrCmp(PChar(FileName+StrLen(FileName)-2), 'js', 2) then
    Result := 'text/javascript'
  else if StrCmp(PChar(FileName+StrLen(FileName)-2), 'md', 2) then
    Result := 'text/markdown'
  else if StrCmp(PChar(FileName+StrLen(FileName)-3), 'png', 3) then
    Result := 'image/png'
  else if StrCmp(PChar(FileName+StrLen(FileName)-3), 'jpg', 3) then
    Result := 'image/jpg'
  else if StrCmp(PChar(FileName+StrLen(FileName)-3), 'gif', 3) then
    Result := 'image/gif'
  else if StrCmp(PChar(FileName+StrLen(FileName)-3), 'ico', 3) then
    Result := 'image/x-icon'
  else
  begin
    WriteConsoleF('\t ContentType not found from FileName: %p\n', [PtrUInt(FileName)]);
    Result := 'application/octet-stream';
  end;
end;

function GetFileContent(const FileName: PChar; var FileContent: PChar): LongInt;
var
  BytesRead: LongInt;
  FileHandle: THandle;
  FileInfo: TInode;
  FileSize: Int64;
begin
  FileContent:= nil;
  Result := 0;
  if SysStatFile(FileName, @FileInfo) = 0 then
  begin
    WriteConsoleF('\t Http Server: %p not found\n', [PtrUInt(FileName)]);
    Exit;
  end;
  FileSize := FileInfo.Size;
  FileContent := ToroGetMem(FileSize+1);
  FileHandle := SysOpenFile(FileName, O_RDONLY);
  if FileHandle = 0 then
  begin
    WriteConsoleF ('Cannot open file: %p\n', [PtrUInt(FileName)]);
    Exit;
  end;
  try
    BytesRead := SysReadFile(FileHandle, FileSize, FileContent);
    if BytesRead <> FileSize then
      WriteConsoleF('\t Warning: %p BytesRead: %d != FileSize: %d\n', [PtrUInt(FileName), BytesRead, FileSize]);
    FileContent[BytesRead] := #0;
  finally
    SysCloseFile(FileHandle);
  end;
  WriteConsoleF('\t Http Server: %p loaded, size: %d bytes\n', [PtrUInt(FileName), FileSize]);
  Result := FileSize;
end;

procedure HttpSend404(Socket: PSocket; var ConnectionClosed: Boolean);
begin
  SysSocketSend(Socket, HeaderNotFound, StrLen(HeaderNotFound), 0);
  SysSocketClose(Socket);
  ConnectionClosed := True;
end;

procedure Concat(var PResponse: PChar; const Value: PChar);
begin
  StrConcat(PResponse, Value, PResponse);
  Inc(PResponse, StrLen(Value));
end;

procedure HttpSendResponse(Socket: PSocket; const Content: PChar; ContentLength: LongInt; ContentType: PChar; var ConnectionClosed: Boolean);
var
  SContentLength: array[0..10] of char;
  Response, PResponse: PChar;
  ResponseSize: LongInt;
begin
//  if ContentLength = 0 then
//    ContentLength := Strlen(Content);
  Response := ToroGetMem(1024+ContentLength);
  try
    PResponse := Response; 
    Concat(PResponse, 'HTTP/1.1 200 OK'#13#10'Content-Type: ');
    Concat(PResponse, ContentType);
    Concat(PResponse, #13#10'Content-Length: ');
    IntToStr(ContentLength, SContentLength);
    Concat(PResponse, SContentLength);
    Concat(PResponse, #13#10'Connection: close'#13#10'Server: ToroHttpServer'#13#10#13#10);
    ResponseSize := PResponse-Response;
//    WriteConsoleF('\t Headers.Size: %d\n', [ResponseSize]);
    Response[ResponseSize] := #0;
    WriteConsoleF('%p\n', [PtrUInt(Response)]);
    SysSocketSend(Socket, Response, ResponseSize, 0);
//    Move(Content^, PResponse^, ContentLength);
//    Inc(ResponseSize, ContentLength);
//    WriteConsoleF('\t ResponseSize: %d\n', [ResponseSize]);
//    SysSocketSend(Socket, Response, ResponseSize, 0);
    SysSocketSend(Socket, Content, ContentLength, 0);
    SysSocketClose(Socket);
    ConnectionClosed := True;
  finally
    ToroFreeMem(Response);
  end;
end;

function ServiceHttpRequest(Socket: PSocket; var ConnectionClosed: Boolean): LongInt;
var
  ContentType: PChar;
  FileName, FileContent: PChar;
  FileSize: LongInt;
  Request: PRequest;
begin
  Result := 0;
  if not FetchHttpRequest(Socket) then
    Exit;  
  Request := Socket.UserDefined;
  FileName := Request.BufferStart;
  FileSize := GetFileContent(Request.BufferStart, FileContent);
  if FileContent = nil then
  begin
    HttpSend404(Socket, ConnectionClosed);
    Exit;
  end;
  ContentType := GetContentType(FileName);
  HttpSendResponse(Socket, FileContent, FileSize, ContentType, ConnectionClosed);  
  WriteConsoleF('\t Http Server: closing %d:%d\n', [Socket.DestIp, Socket.DestPort]);
  if FileContent <> nil then
    ToroFreeMem(FileContent);
end;

function ServiceHttp(ASocket: Pointer): PtrInt;
var
  ConnectionClosed: Boolean;
  Socket: PSocket;
begin
  Socket := ASocket;
  try
    while True do
    begin
      if not SysSocketSelect(Socket, SERVICE_TIMEOUT) then
      begin
        WriteConsoleF('\t HttpServer: closing after timeout %d:%d\n', [Socket.DestIp, Socket.DestPort]);
        SysSocketClose(Socket);
        Break;
      end;
      ConnectionClosed := False;
      ServiceHttpRequest(Socket, ConnectionClosed);
      if ConnectionClosed then
	      Break;
    end;
  finally
    Request := Socket.UserDefined;
    ToroFreeMem(Request.BufferStart);
    ToroFreeMem(Request);
  end;
  Result := 0;
end;

var
  fsdriver: PChar;
  blkdriver: PChar;
  netdriver: PChar;
begin
  if KernelParamCount = 0 then
  begin
    Exit;
  end else
  begin
    // parameters are [ip/vsocket],[fsdriver],[blkdriver]
    netdriver := GetKernelParam(0);
    DedicateNetworkSocket(netdriver);
    fsdriver := GetKernelParam(1);
    blkdriver := GetKernelParam(2);
    DedicateBlockDriver(blkdriver, 0);
    SysMount(fsdriver, blkdriver, 0);
  end;
  HttpServer := SysSocket(SOCKET_STREAM);
  HttpServer.Sourceport := 80;
  HttpServer.Blocking := True;
  SysSocketListen(HttpServer, SERVICE_BACKLOG);
  WriteConsoleF('\t Http Server: listening at %d ..\n', [HttpServer.SourcePort]);
  while True do
  begin
    HttpClient := SysSocketAccept(HttpServer);
    WriteConsoleF('\t Http Server: new connection from %d:%d\n', [HttpClient.DestIp, HttpClient.DestPort]);
    Request := ToroGetMem(SizeOf(TRequest));
    Request.BufferStart := ToroGetMem(Max_Path_Len);
    Request.BufferEnd := Request.BufferStart;
    Request.Counter := 0;
    HttpClient.UserDefined := Request;
    ThreadID := BeginThread(nil, 4096*2, ServiceHttp, HttpClient, 0, ThreadID);
  end;
end.
