//
// UploadFiles.pas
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

program UploadFiles;

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
  {$IFDEF UseVirtIOFS}
    VirtIOFS in '..\..\rtl\drivers\VirtIOFS.pas',
    VirtIOVSocket in '..\..\rtl\drivers\VirtIOVSocket.pas',
  {$ELSE}
    VirtIOBlk in '..\..\rtl\drivers\VirtIOBlk.pas',
    // Ext2 in '..\..\rtl\drivers\Ext2.pas',
    Fat in '..\..\rtl\drivers\Fat.pas',
    VirtIONet in '..\..\rtl\drivers\VirtIONet.pas',
  {$ENDIF}
  Console in '..\..\rtl\drivers\Console.pas',
  Network in '..\..\rtl\Network.pas';

const
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 2, 1);
  DefaultLocalIP: array[0..3] of Byte  = (192, 100, 2, 100);

  //HeaderOK = 'HTTP/1.0 200'#13#10'Content-type: ';
  HeaderOK = 'HTTP/1.0 200'#13#10;
  ContentLen = #13#10'Content-length: ';
  ContentOK = 'Connection: close'#13#10 + 'Server: ToroHttpServer'#13#10''#13#10;
  HeaderNotFound = 'HTTP/1.0 404'#13#10;
  HEADER_CONTENT_LENGTH = 'Content-Length: ';
  HEADER_CONTENT_BOUNDARY = 'Content-Type: application/x-www-form-urlencoded; boundary=';
  HEADER_CONTENT_APP_URLENCODED = 'Content-Type: application/x-www-form-urlencoded'#13#10;
  HEADER_END_LINE = #13#10;
  BODY_CONTENT_DISP = 'Content-Disposition: form-data; name="';
  BODY_QUOTE = '"';
  EMPTY = '';
  AMPERSAND = '&';
  EQUAL = '=';
  BODY_DOUBLE_BREAK_LINE = #13#10#13#10;
  SERVICE_TIMEOUT = 20000;
  Max_Path_Len = 200;

type
  TContentType = (ContentTypeFormUrlEncoded, ContentTypeFormUrlEncodedWithBoundary);
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
  
  
function torolib_string_find(Const s: PChar; Const sub: PChar; Const from_: Integer; Const to_: Integer): Integer;
var
    i: Integer;
    j: Integer;
begin
    i:= from_;
    j:= 0;
    
    while((i<to_) and (j < length(sub))) do
    begin
        if(s[i] = sub[j]) then
        begin
            j:=j+1;
        end
        else
        begin
            j:=0;
            i:=i-j;
        end;
        Inc(i);
    end;
    
    if(j = length(sub)) then
        Result := i-j
    else
        Result := -1;

end;

function torolib_string_find2(Const s: PChar; Const sub: PChar; Const from_: Integer; Const to_: Integer; Const sub_from_: Integer; Const sub_to_: Integer): Integer;
var
    i: Integer;
    j: Integer;
begin
    i:= from_;
    j:= sub_from_;
    
    while((i<to_) and (j < sub_to_)) do
    begin
        if(s[i] = sub[j]) then
            j:=j+1
        else
        begin
            i:=i-(j-sub_from_);
            j:=sub_from_;
        end;
        Inc(i);
    end;
    
    if(j = sub_to_) then
        Result := i-(j-sub_from_)
    else
        Result := -1;

end;

function torolib_string_toInt(s: PChar; from_: Integer; to_: Integer): Integer;
var
    i:Integer;
    
begin
    Result := 0;
    i:=from_;
    while(i<to_) do
    begin
        Result := 10 * Result + ord(s[i])-48;
        Inc(i);
    end;
end;

function GetRequest(Socket: PSocket): Boolean;
var
   i: longint;
   buf: char;
   rq: PRequest;
   buffer: Pchar;
   CESAR_finish_header: Integer;
   body: PRequest;
   CESAR_contentlen_pos: Integer;
   CESAR_contentlen_end_pos: Integer;
   CESAR_contentlen:Integer;
   CESAR_boundary_pos: Integer;
   CESAR_boundary_end_pos: Integer;
   CESAR_total_fields : Integer;
   CESAR_oc_boundary: Integer;
   CESAR_field_name_start: integer;
   CESAR_field_name_end: integer;
   CESAR_field_value_start: integer;
   CESAR_field_value_end: integer;
   
   CESAR_content_type: TContentType;
begin
  Result := False;
  CESAR_finish_header := 0;
  rq := Socket.UserDefined;
  i := rq.counter;
  buffer := rq.BufferEnd;
  // 1) Calculate len of the request
  while (SysSocketRecv(Socket, @buf,1,0) <> 0)do
  begin
    if((CESAR_finish_header = 0) and (buf = #13)) then
        CESAR_finish_header := 1
    else if((CESAR_finish_header = 1) and (buf = #10)) then
        CESAR_finish_header := 2
    else if((CESAR_finish_header = 2) and (buf = #13)) then
        Break
    else if((CESAR_finish_header = 3) and (buf = #10)) then
        Break
    else
        CESAR_finish_header := 0;
  
    buffer^ := buf;
    Inc(buffer);
    Inc(rq.BufferEnd);
    Inc(i);
  end;
  rq.counter := i;
  
  WriteConsoleF('Size of Header: %d\n', [i]);
  
  
  // 2) Determine length of request
  CESAR_contentlen_pos := torolib_string_find(rq.BufferStart, HEADER_CONTENT_LENGTH, 0, rq.counter) + Length(HEADER_CONTENT_LENGTH);
  CESAR_contentlen_end_pos := torolib_string_find(rq.BufferStart, HEADER_END_LINE, CESAR_contentlen_pos, rq.counter);
  CESAR_contentlen := torolib_string_toInt(rq.BufferStart, CESAR_contentlen_pos, CESAR_contentlen_end_pos);
  
  // DEBUG:
  //WriteConsoleF('Content Length of upcoming body: %d\n', [torolib_string_toInt(rq.BufferStart, CESAR_contentlen_pos, CESAR_contentlen_end_pos)]);
  
  WriteConsoleF('Length of Request: %d %d %d\n', [CESAR_contentlen_pos, CESAR_contentlen_end_pos, CESAR_contentlen]);
  
  // 3) Determine the content-boundary
  CESAR_boundary_pos := torolib_string_find(rq.BufferStart, HEADER_CONTENT_BOUNDARY, 0, rq.counter);
  
  if (CESAR_boundary_pos = -1) then
  begin
  //ContentTypeFormUrlEncodedWithBoundary 
        // 3.a) There is no content-boundary
        CESAR_boundary_pos := torolib_string_find(rq.BufferStart, HEADER_CONTENT_APP_URLENCODED, 0, rq.counter);
        if(CESAR_boundary_pos = -1) then // 3.a.1) There is an unsupported type of request
        begin
            WriteConsoleF('Unsupported content-type\n', []);
            Result:=False;
            Exit;
        end;
        
        CESAR_content_type :=ContentTypeFormUrlEncoded;
  end
  else
  begin
      CESAR_boundary_pos := CESAR_boundary_pos + Length(HEADER_CONTENT_BOUNDARY);
      CESAR_boundary_end_pos := torolib_string_find(rq.BufferStart, HEADER_END_LINE, CESAR_boundary_pos, rq.counter);
      
      CESAR_content_type := ContentTypeFormUrlEncodedWithBoundary;
  end;
  
  WriteConsoleF('Length of Boundary: %d %d\n', [CESAR_boundary_pos, CESAR_boundary_end_pos]);
  
  // 4) Now, extract the header
  body := ToroGetMem(sizeof(TRequest));
  body.BufferStart := ToroGetMem(CESAR_contentlen);
  body.BufferEnd := body.BufferStart;
  body.counter := 0;
  buffer := body.BufferEnd;
  i:=0;
  while ((i < CESAR_contentlen) and (SysSocketRecv(Socket, @buf,1,0) <> 0))do
  begin
        buffer^ := buf;
        Inc(buffer);
        Inc(body.BufferEnd);
        i:=i+1;
  end;
  body.counter := i;
  
  WriteConsoleF('Finish extracting body (%d): %p\n', [i, PtrUInt(Body.BufferStart)]);
  WriteConsoleF('Finish extracting body (%d)\n', [i]);
  
  CESAR_field_value_end :=0 ;
  CESAR_field_name_start := CESAR_field_value_end;
  if (CESAR_content_type = ContentTypeFormUrlEncoded) then
  begin
        // We have to search for equals and ampersands
        i:=0;
        while(i<CESAR_contentlen) do
        begin
            CESAR_field_name_start := CESAR_field_value_end;
            CESAR_field_name_end := torolib_string_find(body.BufferStart, EQUAL, CESAR_field_name_start, body.counter);
            
            CESAR_field_value_start := CESAR_field_name_end + 1;
            CESAR_field_value_end := torolib_string_find(body.BufferStart, AMPERSAND, CESAR_field_value_start, body.counter);
            if(CESAR_field_value_end = -1) then
            begin
                i:=CESAR_contentlen;
                CESAR_field_value_end := CESAR_contentlen;
            end;
                
            WriteConsoleF('FIeld name[%d, %d) = [%d, %d)\n', [CESAR_field_name_start, CESAR_field_name_end, CESAR_field_value_start, CESAR_field_value_end]);
            
            Inc(i);
        end;
  end;
  
  if (CESAR_content_type = ContentTypeFormUrlEncodedWithBoundary) then
  begin
      // 5) Search occurrences of boundary
      WriteConsoleF('Occurrence boundary %d\n', [torolib_string_find2(body.BufferStart, rq.BufferStart, 0, 44, CESAR_boundary_pos, CESAR_boundary_end_pos)]);
      
      CESAR_total_fields := 0;
      i:=0;
      CESAR_oc_boundary := 0;
      while((i<CESAR_contentlen) and (CESAR_oc_boundary <> -1)) do
      begin
        CESAR_oc_boundary := torolib_string_find2(body.BufferStart, rq.BufferStart, CESAR_oc_boundary + 1, CESAR_contentlen, CESAR_boundary_pos, CESAR_boundary_end_pos);
        
        if(CESAR_oc_boundary <> -1) then
        begin
            Inc(CESAR_total_fields);
        end;
      end;
      
      i:=0;
      CESAR_oc_boundary := 0;
      while(i<CESAR_total_fields - 1) do
      begin
            CESAR_oc_boundary := torolib_string_find2(body.BufferStart, rq.BufferStart, CESAR_oc_boundary + 1, CESAR_contentlen, CESAR_boundary_pos, CESAR_boundary_end_pos);
            
            if(CESAR_oc_boundary <> -1) then
            begin
                CESAR_field_name_start := torolib_string_find(body.BufferStart, BODY_CONTENT_DISP, CESAR_oc_boundary, body.counter) + Length(BODY_CONTENT_DISP);
                CESAR_field_name_end := torolib_string_find(body.BufferStart, BODY_QUOTE, CESAR_field_name_start, body.counter);
                
                CESAR_field_value_start := torolib_string_find(body.BufferStart, BODY_DOUBLE_BREAK_LINE, CESAR_field_name_end, body.counter) + 4; // double break line counts as 2 chars (but in toro magic
                CESAR_field_value_end := torolib_string_find2(body.BufferStart, rq.BufferStart, CESAR_oc_boundary + 1, CESAR_contentlen, CESAR_boundary_pos, CESAR_boundary_end_pos) - 4;
                
                WriteConsoleF('FIeld name[%d, %d) = [%d, %d)\n', [CESAR_field_name_start, CESAR_field_name_end, CESAR_field_value_start, CESAR_field_value_end]);
            end;
            
            Inc(i);
      end;
  end;

  
  Result := True;
  
end;

procedure SendStream(Socket: Psocket; Stream: Pchar);
begin
  SysSocketSend(Socket, Stream, Length(Stream), 0);
end;

procedure ProcessRequest (Socket: PSocket);
var
  dst, tmp: ^char;
begin
    dst := ToroGetMem(StrLen(HeaderOk) + StrLen(ContentOK));
    tmp := dst;
    StrConcat(HeaderOk, EMPTY, dst);
    dst := dst + StrLen(HeaderOk);
    StrConcat(dst, ContentOK, dst);
    SendStream(Socket,tmp);
end;

//procedure SendStream(Socket: Psocket; Stream: Pchar; Len: Longint);
//begin
//  If Len = 0 then
//    SysSocketSend(Socket, Stream, Length(Stream), 0)
//  else
//    SysSocketSend(Socket, Stream, Len, 0);
//end;



function ServiceReceive(Socket: PSocket): LongInt;
//var
//  rq: PRequest;
begin
  while true do
  begin
    GetRequest(Socket);
    //begin
//      rq := Socket.UserDefined;
      //entry := rq.BufferStart;
      WriteConsoleF('\t Http Server: closing from %d:%d\n', [Socket.DestIp, Socket.DestPort]);
      ProcessRequest(Socket);
      SysSocketClose(Socket);
      //ToroFreeMem(rq.BufferStart);
      //ToroFreeMem(rq);
      Exit;
    //end;
    //else
    //begin
    //  if not SysSocketSelect(Socket, SERVICE_TIMEOUT) then
    //  begin
    //    WriteConsoleF('\t Http Server: closing for timeout from %d:%d\n', [Socket.DestIp, Socket.DestPort]);
    //    SysSocketClose(Socket);
    //    rq := Socket.UserDefined;
    //    ToroFreeMem(rq.BufferStart);
    //    ToroFreeMem(rq);
    //    Exit;
    //  end;
    //end;
  end;
  Result := 0;
end;

function ProcessesSocket(Socket: Pointer): PtrInt;
begin
  ServiceReceive (Socket);
  Result := 0;
end;

begin
//  {$IFDEF UseVirtIOFS}
//    DedicateNetworkSocket('virtiovsocket');
//    DedicateBlockDriver('myfstoro', 0);
//    SysMount('virtiofs', 'myfstoro', 0);
//  {$ELSE}
//    If GetKernelParam(1)^ = #0 then
//    begin
      DedicateNetwork('virtionet', DefaultLocalIP, Gateway, MaskIP, nil);
//    end else
//    begin
      IPStrtoArray(GetKernelParam(1), LocalIp);
      DedicateNetwork('virtionet', LocalIP, Gateway, MaskIP, nil);
//    end;
//    DedicateBlockDriver('virtioblk', 0);
//    SysMount('fat', 'virtioblk', 0);
//  {$ENDIF}
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
