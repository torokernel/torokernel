//
// ToroMicroservice.pas
//
// This is a
//
// Changes :
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
  SERVICE_PORT = 8000;

  // timeout in ms
  SERVICE_TIMEOUT = 20000;

  // number of connections that can be in the queue
  SERVICE_QUEUELEN = 50;

  CRLF = #13#10;

var
  ServiceServer: PSocket;
  Buffer: char;
  tmp: THandle;
  ServiceHandler: TNetworkHandler;
  count: longint = 0;
  idx, idx2: TInode;

// Service Initialization
procedure ServiceInit;
begin
  ServiceServer := SysSocket(SOCKET_STREAM);
  ServiceServer.Sourceport := SERVICE_PORT;
  SysSocketListen(ServiceServer, SERVICE_QUEUELEN);
end;

// A new connection arrives
function ServiceAccept(Socket: PSocket): LongInt;
begin
  SysSocketSelect(Socket, SERVICE_TIMEOUT);
  Result := 0;
end;


procedure GetRequest(Socket: PSocket; buffer: pchar; Len: LongInt);
var
   i: longint = 0;
   line: boolean = true;
   buf: char;
begin
 while (SysSocketRecv(Socket, @buf,1,0) <> 0) or line do
 begin
  if ((i>4) and (buf = #32)) or (Len = 0) then
  begin
   line := false;
   buffer^ := #0;
  end;
  if (i>4) and line then
  begin
   buffer^ := buf;
   buffer +=1;
   Len := Len - 1;
  end;
  i+=1;
 end;
end;

procedure SendStream(Socket: Psocket; Stream: Pchar);
begin
 SysSocketSend(Socket, Stream, Length(Stream), 0);
end;


const
  HeaderOK = 'HTTP/1.0 200'#13#10'Content-type: Text/Html'#13#10 + 'Content-length:';
  ContentOK = #13#10'Connection: close'#13#10 + 'Server: ToroMicroserver'#13#10''#13#10;

  HeaderNotFound = 'HTTP/1.0 404'#13#10;

  KeySize = 15 * 1024;
  ValueSize = 15 * 1024;

type
  RegisterEntry = record
    key: array[0..KeySize-1] of char;
    value: array[0..ValueSize-1] of char;
  end;

const
  TABLE_LEN = 2 ;

var
   table: array[0..TABLE_LEN-1] of RegisterEntry;

function LookUp(entry: pchar): pchar;
var
   i: LongInt;
begin
     for i:= 0 to (TABLE_LEN-1) do
     begin
       if StrCmp(entry, @table[i].key[0], 4) then
       begin
         Result := @table[i].value[0];
         Exit;
       end;
     end;
     result := nil;
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

   dst := dst +   StrLen(ContentOK) ;

   StrConcat(dst, Answer, dst);

   SendStream(Socket,tmp);
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
begin
  SysSocketClose(Socket);
  Result := 0;
end;

// main service function
function ServiceReceive(Socket: PSocket): LongInt;
var
   entry: ^char;
   value: array[0..ValueSize] of char;
   dst: array[0..(20+sizeof(HeaderOk))] of char;
begin

 entry := ToroGetMem(KeySize);

 // get the request
 GetRequest(Socket, entry, KeySize);

 WriteConsoleF('recibido %d\n',[StrLen(entry)]);

 // process it
 ProcessRequest(Socket, LookUp(entry));

 // finish
 FinishRequest(Socket);

 ToroFreeMem(entry);

 Result := 0;
end;

begin
   // get this from file and parse it
  // TODO: get values from disk
  // NOTE: key and value must be least than 15kb!
  //table[0].key :=  'Mata';
  //table[0].value := 'casa12345';
  table[1].key := 'Juan';
  table[1].value := 'nada';

    // Dedicate the ide disk to local cpu
  DedicateBlockDriver('ATA0',0);

  SysMount('ext2','ATA0',5);

  // dedicate the e1000 network card to local cpu
  DedicateNetwork('virtionet', LocalIP, Gateway, MaskIP, nil);

  if SysStatFile('/web/key', @idx) = 0 then
  begin
    WriteConsoleF ('index.html not found\n',[]);
  end;
  //else
   // Buf := ToroGetMem(idx.Size);

  tmp := SysOpenFile('/web/key');

  if (tmp <> 0) then
  begin
    SysReadFile(tmp, idx.Size, @table[0].key);
    SysCloseFile(tmp);
  end else
      WriteConsoleF ('key not found\n',[]);

  WriteConsoleF('Key size %d\n',[idx.Size]);

  if SysStatFile('/web/value', @idx2) = 0 then
  begin
    WriteConsoleF ('index.html not found\n',[]);
  end;
  //end else
  //  Buf := ToroGetMem(idx.Size);

  tmp := SysOpenFile('/web/value');

  if (tmp <> 0) then
  begin
    SysReadFile(tmp, idx2.Size, @table[0].value);
    SysCloseFile(tmp);
  end else
      WriteConsoleF ('value not found\n',[]);

  WriteConsoleF('Value size %d\n',[idx2.Size]);

  // set the callbacks used by the kernel
  ServiceHandler.DoInit    := @ServiceInit;
  ServiceHandler.DoAccept  := @ServiceAccept;
  ServiceHandler.DoTimeOut := @ServiceTimeOut;
  ServiceHandler.DoReceive := @ServiceReceive;
  ServiceHandler.DoClose   := @ServiceClose;

  // register the service
  SysRegisterNetworkService(@ServiceHandler);

  WriteConsoleF('\t /VToroService/n: listening on port %d ...\n',[SERVICE_PORT]);

  SysSuspendThread(0);
end.
