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
  VirtIOBlk in '..\..\rtl\drivers\VirtIOBlk.pas',
  // Ext2 in '..\..\rtl\drivers\Ext2.pas',
  Fat in '..\..\rtl\drivers\Fat.pas',
  Console in '..\..\rtl\drivers\Console.pas',
  Network in '..\..\rtl\Network.pas',
  //E1000 in '..\..\rtl\drivers\E1000.pas';
  VirtIONet in '..\..\rtl\drivers\VirtIONet.pas';

const
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  DefaultLocalIP: array[0..3] of Byte  = (192, 100, 200, 100);

  HeaderOK = 'HTTP/1.0 200'#13#10'Content-type: Text/Html'#13#10 + 'Content-length:';
  ContentOK = #13#10'Connection: close'#13#10 + 'Server: ToroMicroserver'#13#10''#13#10;
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
  tmp: THandle;
  LocalIp: array[0..3] of Byte;
  tid: TThreadID;
  rq: PRequest;

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
    AnsSize := Strlen(Answer);
    InttoStr(AnsSize,@anssizechar[0]);
    dst := ToroGetMem(StrLen(@anssizechar[0]) + StrLen(HeaderOk) + StrLen(ContentOK) + StrLen(Answer));
    tmp := dst;
    StrConcat(HeaderOk, @anssizechar[0], dst);
    dst := dst + StrLen(@anssizechar[0]) + StrLen(HeaderOk);
    StrConcat(dst, ContentOK, dst);
    dst := dst + StrLen(ContentOK) ;
    StrConcat(dst, Answer, dst);
    SendStream(Socket,tmp);
    ToroFreeMem(tmp);
  end;
end;

function GetFileContent(entry: pchar): pchar;
var
  idx: TInode;
  indexSize: LongInt;
  Buf: Pchar;
begin
  Result := nil;
  if SysStatFile(entry, @idx) = 0 then
  begin
    WriteConsoleF ('%p not found\n',[PtrUInt(entry)]);
    Exit;
  end else
    Buf := ToroGetMem(idx.Size + 1);
  tmp := SysOpenFile(entry);
  if (tmp <> 0) then
  begin
    indexSize := SysReadFile(tmp, idx.Size, Buf);
    pchar(Buf+idx.Size)^ := #0;
    SysCloseFile(tmp);
    WriteConsoleF('\t /VWebServer/n: %p loaded, size: %d bytes\n', [PtrUInt(entry),idx.Size]);
    Result := Buf;
  end else
  begin
    WriteConsoleF ('index.html not found\n',[]);
  end;
end;

function ServiceReceive(Socket: PSocket): LongInt;
var
  rq: PRequest;
  entry, content: PChar;
begin
  while true do
  begin
    if GetRequest(Socket) then
    begin
      rq := Socket.UserDefined;
      entry := rq.BufferStart;
      content := GetFileContent(rq.BufferStart);
      ProcessRequest(Socket, content);
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
  If GetKernelParam(1)^ = #0 then
  begin
    DedicateNetwork('virtionet', DefaultLocalIP, Gateway, MaskIP, nil)
  end else
  begin
    IPStrtoArray(GetKernelParam(1), LocalIp);
    DedicateNetwork('virtionet', LocalIP, Gateway, MaskIP, nil);
  end;

  while true do;
  // Dedicate the ide disk to local cpu
  DedicateBlockDriver('ATA0',0);

  //SysMount('ext2','ATA0',5);
  SysMount('fat','ATA0',6);

  HttpServer := SysSocket(SOCKET_STREAM);
  HttpServer.Sourceport := 80;
  HttpServer.Blocking := True;
  SysSocketListen(HttpServer, 50);
  WriteConsoleF('\t /VWebServer/n: listening ...\n',[]);

  while true do
  begin
    HttpClient := SysSocketAccept(HttpServer);
    rq := ToroGetMem(sizeof(TRequest));
    rq.BufferStart := ToroGetMem(Max_Path_Len);
    rq.BufferEnd := rq.BufferStart;
    rq.counter := 0;
    HttpClient.UserDefined := rq;
    tid := BeginThread(nil, 4096, ProcessesSocket, HttpClient, 0, tid);
  end;

end.
