//
// Toro Hello World Example.
// Clasical example using a minimal kernel to show "Hello World" 
//
// Changes :
// 
// 16/09/2011 First Version.
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
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

program ToroHello;


{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}


// Adding support for FPC 2.0.4 ;)
{$IMAGEBASE 4194304}

// They are declared just the necessary units
// The units used depend the hardware where you are running the application 
uses
  Kernel in 'rtl\Kernel.pas',
  Process in 'rtl\Process.pas',
  Memory in 'rtl\Memory.pas',
  Debug in 'rtl\Debug.pas',
  Arch in 'rtl\Arch.pas',
  Console in 'rtl\Drivers\Console.pas';

begin
  WriteConsole('/RHellow World!!!\n',[0]);
  while True do
    SysThreadSwitch;
end.
