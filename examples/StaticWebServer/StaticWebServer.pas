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
  Pci in '..\..\rtl\drivers\Pci.pas',
  // Ide in '..\..\rtl\drivers\IdeDisk.pas',
  VirtIOFS in '..\..\rtl\drivers\VirtIOFS.pas',
  VirtIOBlk in '..\..\rtl\drivers\VirtIOBlk.pas',
  Fat in '..\..\rtl\drivers\Fat.pas',
  VirtIOVSocket in '..\..\rtl\drivers\VirtIOVSocket.pas',
  VirtIONet in '..\..\rtl\drivers\VirtIONet.pas',
  Console in '..\..\rtl\drivers\Console.pas',
  Network in '..\..\rtl\Network.pas';

const
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  DefaultLocalIP: array[0..3] of Byte  = (192, 100, 200, 100);

  HeaderOK = 'HTTP/1.0 200'#13#10'Content-type: ';
  ContentLen = #13#10'Content-length: ';
  ContentOK = #13#10'Connection: close'#13#10 + 'Server: ToroHttpServer'#13#10''#13#10;
  HeaderNotFound = 'HTTP/1.0 404'#13#10;
  SERVICE_TIMEOUT = 20000;
  Max_Path_Len = 200;

type
  PRequest = ^TRequest;
  TRequest = record
    BufferStart: pchar;
    BufferEnd: pchar;
    counter: Longint;
  end;

var
  HttpServer, HttpClient: PSocket;
  LocalIp: array[0..3] of Byte;
  tid: TThreadID;
  rq: PRequest;
  fsdriver: PChar;
  blkdriver: PChar;

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
    Len :=  i - 3
  else
    Len := 0;
  while (SysSocketRecv(Socket, @buf,1,0) <> 0)do
  begin
    if ((i>3) and (buf = #32)) or (Len = Max_Path_Len) then
    begin
      buffer^ := #0;
      Result := True;
      Exit;
    end;
    if (i>3) then
    begin
      Len := i - 3;
      buffer^ := buf;
      Inc(buffer);
      Inc(rq.BufferEnd);
    end;
    Inc(i);
  end;
  rq.counter := i;
end;

procedure SendStream(Socket: Psocket; Stream: Pchar; Len: Longint);
begin
  If Len = 0 then
    SysSocketSend(Socket, Stream, Length(Stream), 0)
  else
    SysSocketSend(Socket, Stream, Len, 0);
end;

procedure ProcessRequest (Socket: PSocket; Answer: pchar; Len: LongInt; Header: Pchar);
var
  dst, tmp: ^char;
  anssizechar: array[0..10] of char;
  AnsSize: LongInt;
  TotalLen: Longint;
begin
  if Answer = nil then
  begin
    SendStream(Socket, HeaderNotFound, 0);
  end
  else begin
    If Len = 0 then
      AnsSize := Strlen(Answer)
    else
      AnsSize := Len;
    InttoStr(AnsSize,@anssizechar[0]);
    TotalLen := StrLen(@anssizechar[0]) + StrLen(HeaderOk) + StrLen(Header) + Strlen(ContentLen) + StrLen(ContentOK) + AnsSize;
    dst := ToroGetMem(TotalLen);
    tmp := dst;
    StrConcat(HeaderOk, Header, dst);
    dst := dst + StrLen(HeaderOk) + StrLen(Header);
    StrConcat(dst, ContentLen, dst);
    dst := dst + StrLen(ContentLen);
    StrConcat(dst, @anssizechar[0], dst);
    dst := dst + StrLen(@anssizechar[0]);
    StrConcat(dst, ContentOK, dst);
    dst := dst + StrLen(ContentOK) ;
    if Len = 0 then
    begin
      StrConcat(dst, Answer, dst);
      SendStream(Socket,tmp, 0);
    end
    else begin
      Move(Answer^, dst^, AnsSize);
      SendStream(Socket,tmp, TotalLen);
    end;
    ToroFreeMem(tmp);
  end;
end;

function GetFileContent(entry: pchar; var Content: pchar): LongInt;
var
  idx: TInode;
  indexSize: LongInt;
  Buf: Pchar;
  tmp: THandle;
begin
  Content := nil;
  Result := 0;
  if SysStatFile(entry, @idx) = 0 then
  begin
    WriteConsoleF ('\t Http Server: %p not found\n',[PtrUInt(entry)]);
    Exit;
  end else
    Buf := ToroGetMem(idx.Size + 1);
  tmp := SysOpenFile(entry, O_RDONLY);
  if (tmp <> 0) then
  begin
    indexSize := SysReadFile(tmp, idx.Size, Buf);
    pchar(Buf+idx.Size)^ := #0;
    SysCloseFile(tmp);
    WriteConsoleF('\t Http Server: %p loaded, size: %d bytes\n', [PtrUInt(entry),idx.Size]);
    Result := idx.Size;
    Content := Buf;
  end else
  begin
    WriteConsoleF ('file not found\n',[]);
  end;
end;

function ServiceReceive(Socket: PSocket): LongInt;
var
  rq: PRequest;
  entry, content: PChar;
  len: LongInt;
begin
  while true do
  begin
    if GetRequest(Socket) then
    begin
      rq := Socket.UserDefined;
      entry := rq.BufferStart;
      len := GetFileContent(rq.BufferStart, content);
      if StrCmp(Pchar(entry + StrLen(entry) - 4), 'html', 4) then
        ProcessRequest(Socket, content, 0, 'Text/html')
      else if StrCmp(PChar(entry + StrLen(entry) - 4), 'json', 4) then
        ProcessRequest(Socket, content, 0, 'Text/json')
      else if StrCmp(Pchar(entry + StrLen(entry) - 3), 'htm', 3) then
        ProcessRequest(Socket, content, 0, 'Text/htm')
      else if StrCmp(PChar(entry + StrLen(entry) - 3), 'css', 3) then
        ProcessRequest(Socket, content, 0, 'Text/css')
      else if StrCmp(PChar(entry + StrLen(entry) - 2), 'js', 2) then
        ProcessRequest(Socket, content, 0, 'Text/javascript')
      else if StrCmp(PChar(entry + StrLen(entry) - 2), 'md', 2) then
        ProcessRequest(Socket, content, 0, 'Text/markdown')
      else if StrCmp(PChar(entry + StrLen(entry) - 3), 'png', 3) then
        ProcessRequest(Socket, content, len, 'Image/png')
      else
        WriteConsoleF('\t Http Server: file format not found\n', []);
      WriteConsoleF('\t Http Server: closing from %d:%d\n', [Socket.DestIp, Socket.DestPort]);
      SysSocketClose(Socket);
      if content <> nil then
        ToroFreeMem(content);
      ToroFreeMem(rq.BufferStart);
      ToroFreeMem(rq);
      Exit;
    end
    else
    begin
      if not SysSocketSelect(Socket, SERVICE_TIMEOUT) then
      begin
        WriteConsoleF('\t Http Server: closing for timeout from %d:%d\n', [Socket.DestIp, Socket.DestPort]);
        SysSocketClose(Socket);
        rq := Socket.UserDefined;
        ToroFreeMem(rq.BufferStart);
        ToroFreeMem(rq);
        Exit;
      end;
    end;
  end;
  Result := 0;
end;

function ProcessesSocket(Socket: Pointer): PtrInt;
begin
  ServiceReceive (Socket);
  Result := 0;
end;

begin
  // default parameters
  if KernelParamCount = 0 then
  begin
    DedicateNetwork('virtionet', DefaultLocalIP, Gateway, MaskIP, nil);
    DedicateBlockDriver('virtioblk', 0);
    SysMount('fat', 'virtioblk', 0)
  end else
  begin
    // configure networking
    // TODO: compare the full virtiosocket string
    if GetKernelParam(1)[0] = 'v' then
      DedicateNetworkSocket('virtiovsocket')
    else If GetKernelParam(1)^ = #0 then
    begin
      DedicateNetwork('virtionet', DefaultLocalIP, Gateway, MaskIP, nil)
    end else
    begin
      IPStrtoArray(GetKernelParam(1), LocalIp);
      DedicateNetwork('virtionet', LocalIP, Gateway, MaskIP, nil);
    end;
    // configure filesystem
    if GetKernelParam(2)^ = #0 then
    begin
      DedicateBlockDriver('virtioblk', 0);
      SysMount('fat', 'virtioblk', 0);
    end else
    begin
      fsdriver := GetKernelParam(2);
      blkdriver := GetKernelParam(3);
      DedicateBlockDriver(blkdriver, 0);
      SysMount(fsdriver, blkdriver, 0);
    end;
  end;
  HttpServer := SysSocket(SOCKET_STREAM);
  HttpServer.Sourceport := 80;
  HttpServer.Blocking := True;
  SysSocketListen(HttpServer, 50);
  WriteConsoleF('\t Http Server: listening at %d ..\n',[HttpServer.Sourceport]);

  while true do
  begin
    HttpClient := SysSocketAccept(HttpServer);
    WriteConsoleF('\t Http Server: new connection from %d:%d\n', [HttpClient.DestIp, HttpClient.DestPort]);
    rq := ToroGetMem(sizeof(TRequest));
    rq.BufferStart := ToroGetMem(Max_Path_Len);
    rq.BufferEnd := rq.BufferStart;
    rq.counter := 0;
    HttpClient.UserDefined := rq;
    tid := BeginThread(nil, 4096*2, ProcessesSocket, HttpClient, 0, tid);
  end;
end.
