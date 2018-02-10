//
// ToroKeyb
// Example that shows the keyboard apis
//
// Changes :
// 
// 16/09/2011 First Version by Matias E. Vara.
//
// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
// All Rights Reserved
//
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

program ToroKeyb;


{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{$IMAGEBASE 4194304}

// Configuring the RUN for Lazarus
{$IFDEF WIN64}
          {%RunCommand qemu-system-x86_64.exe -m 512 -smp 2 -drive format=raw,file=ToroKeyb.img}
{$ELSE}
         {%RunCommand qemu-system-x86_64 -m 512 -smp 2 -drive format=raw,file=ToroKeyb.img}
{$ENDIF}
{%RunFlags BUILD-}

// They are declared just the necessary units
// The units used depend the hardware where you are running the application 
uses
  Kernel in 'rtl\Kernel.pas',
  Process in 'rtl\Process.pas',
  Memory in 'rtl\Memory.pas',
  Debug in 'rtl\Debug.pas',
  Arch in 'rtl\Arch.pas',
  Filesystem in 'rtl\Filesystem.pas',
  Console in 'rtl\Drivers\Console.pas';

begin
  WriteConsoleF('\c/vPress a Key ...\n',[0]);
  EnabledConsole;
  while True do
    SysThreadSwitch;
end.
