//
// TorowithFilesystem.pas
//
// This is a simple example that shows how toro can be used to read files from ext2 filesystem.
// In this example, we first read a file named index.html and then we wait for connections on port
// 80. When a connection arrives, we send the content of the file and we close the conection. The example
// also logs into a file name /web/logs to show writting operations to ext2.
//
// Changes :
//
// 04 / 05 / 2017 v2.
// 12 / 02 / 2017 Adding SysCreateFile().
// 04 / 03 / 2017 v1.
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

program TorowithFileSystem;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{$IMAGEBASE 4194304}

// Configuring the run for Lazarus
{$IFDEF WIN64}
          {%RunCommand qemu-system-x86_64.exe -m 512 -smp 2 -drive format=raw,file=TorowithFileSystem.img -net nic,model=virtio -net tap,ifname=TAP2 -drive format=raw,file=ToroFiles.img -serial file:torodebug.txt}
{$ELSE}
         {%RunCommand qemu-system-x86_64 -m 512 -smp 2 -drive format=raw,file=TorowithFileSystem.img -serial file:torodebug.txt}
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
  //E1000 in '..\rtl\Drivers\E1000.pas';
  VirtIONet in '..\rtl\Drivers\VirtIONet.pas';
// IP values
const
  MaskIP: array[0..3] of Byte   = (255, 255, 255, 0);
  Gateway: array[0..3] of Byte  = (192, 100, 200, 1);
  LocalIP: array[0..3] of Byte  = (192, 100, 200, 100);

  HeaderOK = 'HTTP/1.0 200'#13#10'Content-type: Text/Html'#13#10 + 'Content-length:';
  ContentOK = #13#10'Connection: close'#13#10 + 'Server: ToroMicroserver'#13#10''#13#10;

var
  HttpServer: PSocket;
  Buffer: char;
  Buf, HttpContent: ^Char;
  tmp: THandle;
  HttpHandler: TNetworkHandler;
  idx: TInode;
  BuffLeninChar: array[0..10] of char;
  indexSize: Longint;
  HttpContentLen : Longint;

// Socket initialization
procedure HttpInit;
begin
  HttpServer := SysSocket(SOCKET_STREAM);
  HttpServer.Sourceport := 80;
  SysSocketListen(HttpServer, 50);
end;

// callback when a new connection arrives
function HttpAccept(Socket: PSocket): LongInt;
var
  tmpPing: array[0..3] of byte;
begin
  _IPAddresstoArray (Socket.DestIp, tmpPing);
  WriteConsoleF('\t /VToroWebServer/n: connected %d.%d.%d.%d:%d\n',[tmpPing[0],tmpPing[1],tmpPing[2],tmpPing[3], Socket.DestPort]);
  // we wait for a new event or a timeout, i.e., 50s
  SysSocketSelect(Socket, 20000);
  Result := 0;
end;

// New data received from Socket, we can read the data and return to Network Service thread
function HttpReceive(Socket: PSocket): LongInt;
var
  tmpPing: array[0..3] of byte;
begin
  _IPAddresstoArray (Socket.DestIp, tmpPing);
  WriteConsoleF ('\t /VToroWebServer/n: reading %d.%d.%d.%d:%d\n',[tmpPing[0],tmpPing[1],tmpPing[2],tmpPing[3], Socket.DestPort]);
  // we keep reading until there is no more data
  while SysSocketRecv(Socket, @Buffer, 1, 0) <> 0 do
  begin
  end;
  // we send the whole file
  SysSocketSend(Socket, HttpContent, HttpContentLen, 0);
  WriteConsoleF ('\t /VToroWebServer/n: closing %d.%d.%d.%d:%d\n',[tmpPing[0],tmpPing[1],tmpPing[2],tmpPing[3], Socket.DestPort]);
  SysSocketClose(Socket);
  Result := 0;
end;

 // Peer socket disconnected
function HttpClose(Socket: PSocket): LongInt;
var
  tmpPing: array[0..3] of byte;
begin
  _IPAddresstoArray (Socket.DestIp, tmpPing);
  WriteConsoleF ('\t /VToroWebServer/n: closing %d.%d.%d.%d:%d\n',[tmpPing[0],tmpPing[1],tmpPing[2],tmpPing[3], Socket.DestPort]);
  SysSocketClose(Socket);
  Result := 0;
end;

 // TimeOut
function HttpTimeOut(Socket: PSocket): LongInt;
begin
  WriteConsoleF ('\t /VToroWebServer/n: closing %h for timeout\n',[PtrUInt(Socket)]);
  SysSocketClose(Socket);
  Result := 0;
end;

begin
  //DedicateNetwork('e1000', LocalIP, Gateway, MaskIP, nil);
  DedicateNetwork('virtionet', LocalIP, Gateway, MaskIP, nil);

  // Dedicate the ide disk to local cpu
  DedicateBlockDriver('ATA0',0);

  SysMount('ext2','ATA0',5);

  HttpHandler.DoInit    := @HttpInit;
  HttpHandler.DoAccept  := @HttpAccept;
  HttpHandler.DoTimeOut := @HttpTimeOut;
  HttpHandler.DoReceive := @HttpReceive;
  HttpHandler.DoClose   := @HttpClose;

  if SysStatFile('/web/index.html', @idx) = 0 then
  begin
    WriteConsoleF ('index.html not found\n',[]);
  end else
    Buf := ToroGetMem(idx.Size);

  tmp := SysOpenFile('/web/index.html');

  if (tmp <> 0) then
  begin
    indexSize := SysReadFile(tmp,idx.Size, Buf);
    SysCloseFile(tmp);
    WriteConsoleF('\t /VToroWebServer/n: index.html loaded, size: %d bytes\n', [idx.Size]);
  end else
      WriteConsoleF ('index.html not found\n',[]);

  // build the http header
  InttoStr(indexSize, @BuffLeninChar[0]);
  HttpContentLen := StrLen(@BuffLeninChar[0]) + StrLen(HeaderOk) + StrLen(ContentOK) + StrLen(Buf);
  HttpContent := ToroGetMem(HttpContentLen);
  StrConcat(HeaderOk, @BuffLeninChar[0], HttpContent);
  HttpContent := HttpContent + StrLen(@BuffLeninChar[0]) + StrLen(HeaderOk);
  StrConcat(HttpContent, ContentOK, HttpContent);
  HttpContent := HttpContent + StrLen(ContentOK) ;
  StrConcat(HttpContent, Buf, HttpContent);
  ToroFreeMem(Buf);

  // register the web service which listens on port 80
  SysRegisterNetworkService(@HttpHandler);
  WriteConsoleF('\t /VToroWebServer/n: listening ...\n',[]);

  // main thread goes to sleep
  SysSuspendThread(0);
end.
