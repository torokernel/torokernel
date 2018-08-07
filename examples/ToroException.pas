//
// Toro Exception Example
//
// Changes :
// 
// 04.8.2017 Adding backtrace.
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

{$IFDEF WIN64}
  {$IMAGEBASE 4194304}
{$ENDIF}

// they are declared just the necessary units
// the units used depend the hardware where you are running the application
uses
  SysUtils,
  Kernel in '..\rtl\Kernel.pas',
  Process in '..\rtl\Process.pas',
  Memory in '..\rtl\Memory.pas',
  Debug in '..\rtl\Debug.pas',
  Arch in '..\rtl\Arch.pas',
  Filesystem in '..\rtl\Filesystem.pas',
  Console in '..\rtl\Drivers\Console.pas';

//var
//  tmp: TThreadID = 0;

// Procedure that tests Division by zero exception handler
procedure DoDivZero;
var
  Q, R: Longint;
begin
    {$ASMMODE intel}
    // finally statement is always executed
    try
      Q := 5;
      R := 0;
      R := Q div R;
    except
       WriteConsoleF('Exception!\n',[]);
    end;   
end;


// Procedure that tests Page Fault exception handler
procedure DoPageFault;
var
  p: ^longint;
begin
  // this page is not present
  try
   p := pointer($ffffffffffffffff);
   p^ := $1234;
  except
   WriteConsoleF('exception\n', []);
  end;
end;

// Procedure that tests Protection Fault exception handler
procedure DoProtectionFault;
begin
  asm
     mov ax, $20
     mov ds, ax
  end;
end;

// Procedure that tests Illegal instruction exception handler
procedure DoIllegalInstruction;
begin
  asm
  db $ff, $ff
  end;
end;

function Exception_Core2(Param: Pointer):PtrInt;
begin
  //DoDivZero;
  //DoPageFault;
  DoProtectionFault;
  //DoIllegalInstruction;
  Result := 0;
end;

Type EDivException = Class(Exception);

begin
  // tmp:= BeginThread(nil, 4096, Exception_Core2, nil, 1, tmp);
  // SysThreadSwitch;
  //DoDivZero;
  try
     Raise EDivException.Create ('Division by Zero would occur');
  except
    WriteConsoleF('Exception!\n',[]);
  end;
  //DoPageFault;
  //DoProtectionFault;
  //DoIllegalInstruction;
end.
