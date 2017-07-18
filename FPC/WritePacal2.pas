// Toro Write Pascal Example.
// Example using a minimal kernel to print "Pascal" in 3D

// Changes :

// 19/06/2017 First Version by Joe Care.

// Copyright (c) 2017 Joe Care
// All Rights Reserved

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

program WritePacal2;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{$IMAGEBASE 4194304}

// Configuring the RUN for Lazarus
{$IFDEF WIN64}
{%RunCommand "$env(ProgramFiles)\qemu\qemu-system-x86_64.exe" -m 512 -drive format=raw,file=$Path($(TargetFile))\$NameOnly($(TargetFile)).img}
{%RunFlags BUILD-}
{%RunWorkingDir $(PkgOutDir)}
{$ELSE}
{%RunCommand qemu-system-x86_64 -m 512 -smp 2 -drive format=raw,file=ToroHello.img}
{$ENDIF}

// They are declared just the necessary units
// The needed units depend on the hardware where you are running the application
uses
    Kernel in '..\rtl\Kernel.pas',
    Process in '..\rtl\Process.pas',
    Memory in '..\rtl\Memory.pas',
    Debug in '..\rtl\Debug.pas',
    Arch in '..\rtl\Arch.pas',
    Filesystem in '..\rtl\Filesystem.pas',
    Pci in '..\rtl\Drivers\Pci.pas',
    Console in '..\rtl\Drivers\Console.pas',
    uWritePascal2;

begin
  Main;
  while True do
       SysThreadSwitch;
end.

