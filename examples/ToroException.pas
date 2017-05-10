//
// Toro Exceptions Example
//
// Changes :
// 
// 24.8.2016 First Version by Matias E. Vara.
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

program ToroException;


{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

// Configuring the RUN for Lazarus
{$IFDEF WIN64}
          {%RunCommand qemu-system-x86_64.exe -m 256 -smp 2 -drive format=raw,file=ToroException.img}
{$ELSE}
         {%RunCommand qemu-system-x86_64 -m 256 -smp 2 -drive format=raw,file=ToroException.img}
{$ENDIF}
{%RunFlags BUILD-}

// Adding support for FPC 2.0.4 ;)
{$IMAGEBASE 4194304}

// they are declared just the necessary units
// the units used depend the hardware where you are running the application
uses
  Kernel in 'rtl\Kernel.pas',
  Process in 'rtl\Process.pas',
  Memory in 'rtl\Memory.pas',
  Debug in 'rtl\Debug.pas',
  Arch in 'rtl\Arch.pas',
  Filesystem in 'rtl\Filesystem.pas',
  Console in 'rtl\Drivers\Console.pas';

var
  tmp: TThreadID;

function Exception_Core2(Param: Pointer):PtrInt;
begin
  {$ASMMODE intel}
     asm
   	mov rbx, 1987
     	mov rax, 166
        mov rcx, 0
        mov rdx, 555
   	div rcx
     end;
end;

// This procedure is a exception handler. 
// It has to enable the interruptions and finish the thread who made the exception
procedure MyOwnHandler;
begin
  WriteConsole('Hello from My Handler!\n',[]);
  // enable interruptions
  asm
     sti
  end;
  ThreadExit(True);
end;


begin
  WriteConsole('\c',[]);

  //CaptureInt(EXC_DIVBYZERO, @MyOwnHandler);

  tmp:= BeginThread(nil, 4096, Exception_Core2, nil, 1, tmp);
  SysThreadSwitch;

  {$ASMMODE intel}
    asm
  	mov rbx, 1987
    	mov rax, 166
        mov rcx, 0
        mov rdx, 555
  	div rcx
   end;
end.
