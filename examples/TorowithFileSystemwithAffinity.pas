//
// TorowithFilesystemwithAffinity.pas
//
// This is a simple example that shows how toro can be used to read files from ext2 filesystem.
// In this example, we first read a file named index.html and then we wait for connections on port
// 80. When a connection arrives, we send the content of the file and we close the conection. The example
// also logs into a file name /web/logs to show writting operations to ext2.
//
// Changes :
//
// 19 / 10 / 2017 v1.
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

program TorowithFilesystemwithAffinity;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{$IMAGEBASE 4194304}

// Configuring the run for Lazarus
{$IFDEF WIN64}
          {%RunCommand qemu-system-x86_64.exe -m 512 -smp 2 -drive format=raw,file=TorowithFilesystemwithAffinity.img -net nic,model=e1000 -net tap,ifname=TAP2 -drive format=raw,file=ToroFiles.img -serial file:torodebug.txt}
{$ELSE}
         {%RunCommand qemu-system-x86_64 -m 512 -smp 2 -drive format=raw,file=TorowithFilesystemwithAffinity.img -serial file:torodebug.txt}
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

var
  HttpServer: PSocket;
  Buffer: char;
  buff: array[0..500] of char;
  tmp, log: THandle;
  HttpHandler: TNetworkHandler;
  count: longint = 0;


// This performs the initialization of the FS on core 1
// ATA0 is firstly dedicated to core 1 and then
// the filesystem ext2 is mounted
function FileSystemInit(Param: Pointer):PtrInt;
begin
  // Dedicate the ide disk to core 1
  DedicateBlockDriver('ATA0',1);

  // we mount locally
  SysMount('ext2','ATA0',5);

  // try to create the logs directory
  SysCreateDir('/web/logs');

  // we first try to create the file for logs
  log := SysCreateFile('/web/logs/log');
  if log = 0 then
  begin
    // if it exists we just open it
    log := SysOpenFile ('/web/logs/log');
    if log = 0 then
    begin
      WriteConsoleF ('logs not found\n',[]);
    end else
    begin
      // end of file
      SysSeekFile(log,0,SeekEof);
    end;
  end;

  // we open the file which is used as main page for the webserver
  tmp := SysOpenFile('/web/index.html');

  if (tmp <> 0) then
  begin
    // we read the whole file
    count := SysReadFile(tmp,sizeof(buff),@buff);
    // we close the file
    SysCloseFile(tmp);
  end else
      WriteConsoleF ('index.html not found\n',[]);

  while True do
    SysThreadSwitch;
end;


begin
  // The filesystem is initialized by a thread that runs on core 1
  tmp:= BeginThread(nil, 4096, FileSystemInit, nil, 1, tmp);

  while True do
    SysThreadSwitch;
end.
