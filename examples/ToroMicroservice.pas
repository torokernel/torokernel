//
// ToroMicroservice.pas
//
// This example shows the use of Toro to run a microservice to access a table.
// The microservice filters the request to get the string after the GET command.
// The string is used a key to query a table and returns the value. The microservice
// relies on a generic function named "MyMicroFunction(Pchar): Pchar" to process the
// request and returns a string. From the output string, the http response is generated
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

program ToroMicroservice;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{$IMAGEBASE 4194304}

// Configuring the run for Lazarus
{$IFDEF WIN64}
          {%RunCommand qemu-system-x86_64.exe -m 512 -smp 2 -drive format=raw,file=ToroMicroservice.img -net nic,model=virtio -net tap,ifname=TAP2 -drive format=raw,file=ToroFiles.img -serial file:torodebug.txt}
{$ELSE}
         {%RunCommand qemu-system-x86_64 -m 512 -smp 2 -drive format=raw,file=ToroMicroservice.img -serial file:torodebug.txt}
{$ENDIF}
{%RunFlags BUILD-}

uses
  Kernel in '..\rtl\Kernel.pas',
  Process in '..\rtl\Process.pas',
  Memory in '..\rtl\Memory.pas',
  Debug in '..\rtl\Debug.pas',
  Arch in '..\rtl\Arch.pas',
  Filesystem in '..\rtl\Filesystem.pas',
  Pci in '..\rtl\Drivers\Pci.pas',
  Ide in '..\rtl\drivers\IdeDisk.pas',
  ext2 in '..\rtl\drivers\ext2.pas',
  Console in '..\rtl\Drivers\Console.pas',
  Network in '..\rtl\Network.pas',
  VirtIONet in '..\rtl\Drivers\VirtIONet.pas';

const
  // TCP-Stack configuration values
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  LocalIP: array[0..3] of Byte  = (192, 100, 200, 100);

  // port wher the service listens
  SERVICE_PORT = 80;

  // timeout in ms
  SERVICE_TIMEOUT = 20000;

  // number of connections that can be in the queue
  SERVICE_QUEUELEN = 50;

  CRLF = #13#10;

  HeaderOK = 'HTTP/1.0 200'#13#10'Content-type: Text/Html'#13#10 + 'Content-length:';
  ContentOK = #13#10'Connection: close'#13#10 + 'Server: ToroMicroserver'#13#10''#13#10;
  HeaderNotFound = 'HTTP/1.0 404'#13#10;

  MaxKeySize = 5455;
  TABLE_LEN = 1 ;


type
    RegisterEntry = record
      key: pchar;
      value: pchar;
    end;

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
   tmp: THandle;
   ServiceHandler: TNetworkHandler;
   idx, idx2: TInode;
   table: array[0..TABLE_LEN-1] of RegisterEntry;
   MyMicroFunction : TMicroserviceFunction;

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
 while (SysSocketRecv(Socket, @buf,1,0) <> 0)do
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

function LookUp(entry: pchar): pchar;
var
   i, EntryLen, TableEntryLen: LongInt;
begin
 EntryLen := strlen(entry);
 for i:= 0 to (TABLE_LEN-1) do
 begin
   TableEntryLen := strlen(table[i].key);
  if EntryLen <> TableEntryLen then
    Continue;
  if StrCmp(entry, table[i].key, EntryLen) then
  begin
    Result := table[i].value;
    Exit;
  end;
 end;
 Result := nil;
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
   entry: PChar;
begin
 if GetRequest(Socket) then
 begin
   rq := Socket.UserDefined;
   entry := rq.BufferStart;
   ProcessRequest(Socket, MyMicroFunction(rq.BufferStart));
   FinishRequest(Socket);
   connectionCount := connectionCount + 1;
   WriteConsoleF('\t Connection %d, received: %d bytes\n',[connectionCount, strlen(entry)]);
   ToroFreeMem(rq.BufferStart);
   ToroFreeMem(rq);
 end else SysSocketSelect(Socket, SERVICE_TIMEOUT);
 Result := 0;
end;

begin
  // dedicate the ide disk to local cpu
  DedicateBlockDriver('ATA0',0);

  SysMount('ext2','ATA0',5);

  // dedicate the virtio network card to local cpu
  DedicateNetwork('virtionet', LocalIP, Gateway, MaskIP, nil);

  if SysStatFile('/web/key', @idx) = 0 then
  begin
    WriteConsoleF ('key not found\n',[]);
  end else
    Table[0].key := ToroGetMem(idx.Size);

  tmp := SysOpenFile('/web/key');

  if (tmp <> 0) then
  begin
    SysReadFile(tmp, idx.Size, Table[0].key);
    SysCloseFile(tmp);
  end else
      WriteConsoleF ('cannot open key\n',[]);

  if SysStatFile('/web/value', @idx2) = 0 then
  begin
    WriteConsoleF ('value not found\n',[]);
  end else
    Table[0].value := ToroGetMem(idx2.Size);

  tmp := SysOpenFile('/web/value');

  if (tmp <> 0) then
  begin
    SysReadFile(tmp, idx2.Size, Table[0].value);
    SysCloseFile(tmp);
  end else
      WriteConsoleF ('cannot open value\n',[]);

  // set the callbacks used by the kernel
  ServiceHandler.DoInit    := @ServiceInit;
  ServiceHandler.DoAccept  := @ServiceAccept;
  ServiceHandler.DoTimeOut := @ServiceTimeOut;
  ServiceHandler.DoReceive := @ServiceReceive;
  ServiceHandler.DoClose   := @ServiceClose;

  // the microservice function
  MyMicroFunction := @LookUp;

  // register the service
  SysRegisterNetworkService(@ServiceHandler);

  WriteConsoleF('\t /VToroService/n: listening on port %d ...\n',[SERVICE_PORT]);

  SysSuspendThread(0);
end.
