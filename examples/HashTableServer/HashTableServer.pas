//
// HashTableServer.pas
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

program HashTableServer;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

uses
  Kernel,
  Process,
  Memory,
  Debug,
  Arch,
  Filesystem,
  VirtIO,
  {$IFDEF UseGDBstub}VirtIOConsole,{$ENDIF}
  VirtIOVSocket,
  Console,
  {$IFDEF UseGDBstub}Gdbstub,{$ENDIF}
  Network, cHash;

const
  HeaderOK = 'HTTP/1.0 200'#13#10'Content-type: ';
  ContentLen = #13#10'Content-length: ';
  ContentOK = #13#10'Connection: close'#13#10 + 'Server: ToroMicroserver'#13#10''#13#10;
  HeaderNotFound = 'HTTP/1.1 404'#13#10;
  SERVICE_TIMEOUT = 1000;
  Max_Path_Len = 400;
  MAX_IDX_IN_HASH = 10000;
  Index = '<!doctype html>'#10 +
          '<html>'#10 +
          '<head>'#10 +
          '<title>Welcome to hashtable.torokernel.io!</title>'#10 +
          '</head>'#10 +

          '<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.5.1/styles/agate.min.css">'#10 +
          '<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.5.1/highlight.min.js"></script>'#10 +
          '<script src="https://unpkg.com/@highlightjs/cdn-assets@11.5.1/languages/python.min.js"></script>'#10 +
          '<script>hljs.highlightAll();</script>'#10 +
          '<body>'#10 +
          '<h1>Hashtable in Toro unikernel</h1>'#10 +
          '<p>This is a simple hashtable that you can access by using the GET method. We strongly recommend you to use the Python class <a href="https://github.com/torokernel/torokernel/blob/master/examples/HashTableServer/HashTableClient.py">here</a></p>'#10 +
          '<pre><code class="language-python">'#10 +
          'from HashTableClient import HashServer'#10 +
          'import random'#10 +
          #10 +
          'URL = "http://hashtable.torokernel.io/"'#10 +
          'server = HashServer(URL)'#10 +
          #10 +
          'key = "toro"'#10 +
          'value = "kernel"'#10 +
          #10 +
          'server.SetKey(key, value)'#10 +
          'assert server.GetKey(key) == value'#10 +
          '</code></pre>'#10 +
          '<p>We have already <strong>'#0;

 Index2 = '</strong> keys stored.</p>'#10'</body>'#10 +
           '</html>'#10#0;

type
  PRequest = ^TRequest;
  TRequest = record
    BufferStart: pchar;
    BufferEnd: pchar;
    counter: Longint;
  end;

var
  HttpServer, HttpClient: PSocket;
  tid: TThreadID;
  rq: PRequest;
  netdriver: PChar;
  nrkeys: LongInt;

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

var
  Hash: array[0..MAX_IDX_IN_HASH-1] of PChar;

function GetKey(key: Pchar): PChar;
var
  idx: LongInt;
begin
  idx := CalcChecksum32(key);
  if idx > MAX_IDX_IN_HASH then
  begin
    Result := nil;
    Exit;
  end;
  Result := Hash[idx];
end;

procedure SetKeyValue(key: PChar; value: Pchar);
var
 len, idx: LongInt;
 buff: PChar;
begin
  len := strlen(value);
  buff := ToroGetMem(len+1);
  Move(Value^, Buff^, len+1);
  idx := CalcChecksum32(key);
  if Hash[idx] <> nil then
   ToroFreeMem(Hash[idx]);
  Hash[idx] := buff;
  Inc(nrkeys);
end;

// Content must free by caller
function GetHashContent(entry: pchar; var Content: pchar): LongInt;
var
  len: LongInt;
  Buf, Key, Value: Pchar;
  snrkeys: array[0..10] of char;
  tmp: THandle;
begin
  Content := nil;
  Result := 0;
  Key := entry;
  while (Key^ <> #0) and (Key^ <> '=') do
      Inc(Key);
  if Key^ = #0 then
  begin
    Value := Nil
  end
  else
  begin
    Key^:= #0;
    Value := Key;
    Inc(Value)
  end;
  Key := entry;
  Inc(Key);
  if Key^ = #0 then
  begin
    InttoStr(nrkeys, @snrkeys[0]);
    len := strlen(Index) + strlen(Index2) + strlen(@snrkeys[0]);
    Content := ToroGetMem(len+1);
    StrConcat(Index, @snrkeys[0], Content);
    StrConcat(Content, Index2, Content);
    Result := len;
    Exit;
  end;
  if (Value = Nil) or (Value^ = #0) then
  begin
    Buf := GetKey(Key);
    if Buf <> nil then
    begin
      len := strlen(Buf);
      Content := ToroGetMem(len+1);
      Move(Buf^, Content^, len+1);
      Result := len;
    end;
  end
  else
  begin
    len := strlen(Value);
    SetKeyValue(Key, Value);
    Content := ToroGetMem(len+1);
    Move(Value^, Content^, len+1);
    Result := len;
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
      len := GetHashContent(rq.BufferStart, content);
      ProcessRequest(Socket, content, 0, 'Text/html');
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
var
  i: LongInt;
begin
  DedicateNetworkSocket('virtiovsock');
  if StrCmp(GetKernelParam(0), 'noconsole', strlen('noconsole')) then
    HeadLess := True;
  for i:= 0 to MAX_IDX_IN_HASH - 1 do
    Hash[i] := nil;
  HttpServer := SysSocket(SOCKET_STREAM);
  HttpServer.Sourceport := 80;
  HttpServer.Blocking := True;
  SysSocketListen(HttpServer, 50);
  WriteConsoleF('\t HashTableServer: listening ...\n', []);
  nrkeys := 0;
  while true do
  begin
    HttpClient := SysSocketAccept(HttpServer);
    rq := ToroGetMem(sizeof(TRequest));
    rq.BufferStart := ToroGetMem(Max_Path_Len);
    rq.BufferEnd := rq.BufferStart;
    rq.counter := 0;
    HttpClient.UserDefined := rq;
    tid := BeginThread(nil, 4096*2, ProcessesSocket, HttpClient, 0, tid);
  end;
end.
