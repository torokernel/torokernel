//
// Toro Ping example.
//
// Changes :
// 08 / 12 / 2016 : First Version by Matias Vara
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

program ToroPing;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

// Configuring the RUN for Lazarus
{$IFDEF WIN64}
         {%RunCommand qemu-system-x86_64.exe -m 256 -smp 2 -net nic,model=e1000 -net tap,ifname=TAP2 -serial file:torodebug.txt -drive format=raw,file=ToroPing.img}
{$ELSE}
         {%RunCommand qemu-system-x86_64 -m 256 -smp 2 -net nic,model=e1000 -net tap,ifname=TAP2 -serial file:torodebug.txt -drive format=raw,file=ToroPing.img}
{$ENDIF}
{%RunFlags BUILD-}

{$IMAGEBASE 4194304}

// They are declared just the necessary units
// The units used depend on the hardware in which you run the application
uses
  Kernel in '..\rtl\Kernel.pas',
  Process in '..\rtl\Process.pas',
  Memory in '..\rtl\Memory.pas',
  Debug in '..\rtl\Debug.pas',
  Arch in '..\rtl\Arch.pas',
  Filesystem in '..\rtl\Filesystem.pas',
  Pci in  '..\rtl\Drivers\Pci.pas',
  Network in '..\rtl\Network.pas',
  Console in '..\rtl\Drivers\Console.pas',
  E1000 in '..\rtl\Drivers\E1000.pas',
  uToroPing;

var ldIPAdrCompr:DWORD;

begin
  ldIPAdrCompr:=Init(PingIP);
  Main(ldIPAdrCompr);
end.
