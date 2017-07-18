// Toro Exceptions Example

// Changes :

// 24.8.2016 First Version by Matias E. Vara.

// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
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
unit uToroException;

{$mode delphi}

interface

uses
    Process,
    Console;

procedure Main;

implementation


var
    tmp: TThreadID;

function Exception_Core2(Param: Pointer): PtrInt;
begin
{$ASMMODE intel}
    asm
               MOV     RBX, 1987
               MOV     RAX, 166
               MOV     RCX, 0
               MOV     RDX, 555
               DIV     RCX
    end;
end;

// This procedure is a exception handler.
// It has to enable the interruptions and finish the thread who made the exception
procedure MyOwnHandler;
begin
    WriteConsole('Hello from My Handler!\n', []);
    // enable interruptions
    asm
               STI
    end;
    ThreadExit(True);
end;

procedure Main;

begin
    WriteConsole('\c', []);

    //CaptureInt(EXC_DIVBYZERO, @MyOwnHandler);

    tmp := BeginThread(nil, 4096, Exception_Core2, nil, 1, tmp);
    SysThreadSwitch;

{$ASMMODE intel}
    asm
               MOV     RBX, 1987
               MOV     RAX, 166
               MOV     RCX, 0
               MOV     RDX, 555
               DIV     RCX
    end;
end;

end.
