//
// Exception Handling
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

program ExceptionHandling;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{%RunCommand qemu-system-x86_64 -m 256 -smp 2 -drive format=raw,file=ExceptionHandling.img}
{%RunFlags BUILD-}

uses
  SysUtils,
  Kernel in '..\..\rtl\Kernel.pas',
  Process in '..\..\rtl\Process.pas',
  Memory in '..\..\rtl\Memory.pas',
  Debug in '..\..\rtl\Debug.pas',
  Arch in '..\..\rtl\Arch.pas',
  Filesystem in '..\..\rtl\Filesystem.pas',
  Console in '..\..\rtl\drivers\Console.pas';

// var
//  tmp: TThreadID = 0;

{$ASMMODE intel}

// Procedure that tests Division by zero exception handler
procedure DoDivZero;
var
  Q, R: Longint;
begin
  try
    Q := 5;
    R := 0;
    R := Q div R;
  except
    on E: Exception do
    begin
      WriteConsoleF('Exception Message: %s\n',[PtrUInt(@E.Message)]);
    end;
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
    on E: Exception do
    begin
      WriteConsoleF('Exception Message: %s\n',[PtrUInt(@E.Message)]);
    end;
  end;
end;

// Procedure that tests Protection Fault exception handler
procedure DoProtectionFault;
begin
  try
    asm
      mov ax, $20
      mov ds, ax
    end;
  except
    on E: Exception do
    begin
      WriteConsoleF('Exception Message: %s\n',[PtrUInt(@E.Message)]);
    end;
  end;
end;

// Procedure that tests Illegal instruction exception handler
procedure DoIllegalInstruction;
begin
  try
    asm
      db $ff, $ff
    end;
  except
    on E: Exception do
    begin
      WriteConsoleF('Exception Message: %s\n',[PtrUInt(@E.Message)]);
    end;
  end;
end;

function Exception_Core2(Param: Pointer):PtrInt;
begin
  //DoDivZero;
  DoPageFault;
  //DoProtectionFault;
  //DoIllegalInstruction;
  Result := 0;
end;

begin
  //tmp:= BeginThread(nil, 4096, Exception_Core2, nil, 1, tmp);
  //SysThreadSwitch;
  //DoDivZero;
  //try
  //   Raise EDivException.Create ('Division by Zero would occur');
  //except
  //  WriteConsoleF('Exception!\n',[]);
  //end;
  DoPageFault;
  //DoProtectionFault;
  //DoIllegalInstruction;
end.
