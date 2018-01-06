//
// ToroMicroservice.pas
//
// This is a
//
// Changes :
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

program ToroMicroservice;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{$IMAGEBASE 4194304}

// Configuring the run for Lazarus
{$IFDEF WIN64}
          {%RunCommand qemu-system-x86_64.exe -m 512 -smp 2 -drive format=raw,file=ToroMicroservice.img -net nic,model=e1000 -net tap,ifname=TAP2 -drive format=raw,file=ToroFiles.img -serial file:torodebug.txt}
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
  E1000 in '..\rtl\Drivers\E1000.pas';

const
  // TCP-Stack configuration values
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  LocalIP: array[0..3] of Byte  = (192, 100, 200, 100);

  // port wher the service listens
  // TODO: to check why it does not work with 8080 or 8000
  SERVICE_PORT = 5000;

  // timeout in ms
  SERVICE_TIMEOUT = 20000;

  // number of connections that can be in the queue
  SERVICE_QUEUELEN = 50;

  CRLF = #13#10;

var
  ServiceServer: PSocket;
  Buffer: char;
  buff: array[0..500] of char;
  tmp: THandle;
  ServiceHandler: TNetworkHandler;
  count: longint = 0;


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


procedure GetRequest(Socket: PSocket; buffer: pchar);
var
   i: longint = 0;
   line: boolean = true;
   buf: char;
begin
 while SysSocketRecv(Socket, @buf,1,0) <> 0 do
 begin
  if (i>4) and (buf = #32) then
  begin
   line := false;
   buffer^ := #0;
  end;
  if (i>4) and line then
  begin
   buffer^ := buf;
   buffer +=1;
  end;
  i+=1;
 end;
end;

procedure SendStream(Socket: Psocket; Stream: Pchar);
begin
 SysSocketSend(Socket, Stream, Length(Stream), 0);
end;

procedure StrConcat(left, right, dst: pchar);
begin
  Move(left^,dst^,Length(left));
  dst := dst + Length(left);
  Move(right^,dst^,Length(right));
  dst +=Length(right);
  dst^ := #0;
end;

const
  HeaderOK = 'HTTP/1.0 200'#13#10'Content-type: Text/Html'#13#10 +
             'Content-length: 11'#13#10'Connection: close'#13#10 +
             'Server: ToroMicroserver'#13#10''#13#10;

  HeaderNotFound = 'HTTP/1.0 404'#13#10;

  KeySize = 4;
  ValueSize = 10;

type
  RegisterEntry = record
    key: array[0..KeySize] of char;
    value: array[0..ValueSize] of char;
  end;

const
  TABLE_LEN = 2 ;


var
   table: array[0..TABLE_LEN-1] of RegisterEntry;

function StrCmp(p1, p2: pchar; Len: LongInt): Boolean;
var
   i: LongInt;
begin
 result:= false;
 for i:= 0 to Len-1 do
 begin
  if (p1^ <> p2^) then
  begin
    Exit;
  end;
  p1 += 1;
  p2 += 1;
 end;
result := true;
end;

// Print in decimal form
procedure InttoStr(Value: PtrUInt; buff: pchar);
var
  I, Len: Byte;
  // 21 is the max number of characters needed to represent 64 bits number in decimal
  S: string[21];
begin
  Len := 0;
  I := 21;
  if Value = 0 then
  begin
    buff^ := '0';
  end else
  begin
    while Value <> 0 do
    begin
      S[I] := AnsiChar((Value mod 10) + $30);
      Value := Value div 10;
      I := I-1;
      Len := Len+1;
    end;
    S[0] := XChar(Len);
   for I := (sizeof(S)-Len) to sizeof(S)-1 do
   begin
    buff^ := S[I];
    buff +=1;
   end;
  end;
end;

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
   dst: array[0..(20+sizeof(HeaderOk))] of char;
begin
 if Answer = nil then
 begin
   SendStream(Socket,HeaderNotFound);
 end
 else begin
   StrConcat(HeaderOk,Answer,@dst[0]);
   //WriteConsole('Key: %p\n',[PtrUInt(Answer)]);
   SendStream(Socket,@dst[0]);
 end;
end;


procedure FinishRequest(Socket: Psocket);
begin
   SysSocketClose(Socket);
end;

function ServiceReceive(Socket: PSocket): LongInt;
var
   entry: array[0..KeySize] of char;
   value: array[0..ValueSize] of char;
   dst: array[0..(20+sizeof(HeaderOk))] of char;
begin
  GetRequest(Socket, entry);
  ProcessRequest(Socket, LookUp(@entry[0]));
  FinishRequest(Socket);
  Result := 0;
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

begin

   table[0].key := 'Mata';
   table[0].value := 'casa';

   table[1].key := 'Juan';
   table[1].value := 'nada';

  // dedicate the e1000 network card to local cpu
  DedicateNetwork('e1000', LocalIP, Gateway, MaskIP, nil);

  // set the callbacks used by the kernel
  ServiceHandler.DoInit := @ServiceInit;
  ServiceHandler.DoAccept := @ServiceAccept;
  ServiceHandler.DoTimeOut := @ServiceTimeOut;
  ServiceHandler.DoReceive := @ServiceReceive;
  ServiceHandler.DoClose := @ServiceClose;

  // register the service
  SysRegisterNetworkService(@ServiceHandler);

  WriteConsole('\t /VToroService/n: listening on port %d ...\n',[SERVICE_PORT]);

  while True do
    SysThreadSwitch;
end.
