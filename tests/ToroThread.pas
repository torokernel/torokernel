//
// Toro Multithreading Example
// Clasical example using a minimal kernel to show "Hello World" 
//
// Changes :
// 
// 11/12/2011 First Version by Matias E. Vara.
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

program ToroThread;


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
  Filesystem in 'rtl\Filesystem.pas',
  Console in 'rtl\Drivers\Console.pas';


const
 sBusy = 1;
 sFree = 0;

type
 Pargumment = ^Targumment;
 Targumment = record
 op1 : longint;
 op2 : longint;
 res : longint;
 state: boolean;
end; 
 
// Thread Main procedure
function ThreadHelloWorld(Param: Pointer):PtrInt;
var
 parg: Pargumment;
begin
   parg := Param;
   WriteConsole('Core:#%d, op1= %d, op2= %d\n',[GetApicId, parg.op1, parg.op2]);
end;


var
 th: array[0..MAX_CPU] of TThreadID;
 thArg : array [0..MAX_CPU] of Targumment;
 tmp: TThreadID;
 j: longint;


begin
  // we create a thread each core
  for j:= 0 to (CPU_COUNT-1) do
  begin
    thArg[j].state := false;
    thArg[j].op1 := 4 ;
    thArg[j].op2 := 5 ;
    thArg[j].res := 0;
    // passing the argumments
    th[j]:= BeginThread(nil, 4096, ThreadHelloWorld, @thArg[j], j, tmp);
    if th[j]= 0 then
       WriteConsole('/RFail/n: Creating a Thread in core #%d\n', [j]);
  end;

  while true do
   SysThreadSwitch;
end.
