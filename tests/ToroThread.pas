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


var
 tmp: TThreadID;
 var1, var2, var3: longint;
 n1: boolean = true;
 n2: boolean = false;
 n3: boolean = false;


function ThreadF2(Param: Pointer):PtrInt;
begin
  while true do
  begin
    while n2=false do SysThreadSwitch;
    var3:=var2+7;
    n3:= true;
    n2:=false;
  end
end;

function ThreadF3(Param: Pointer):PtrInt;
begin
  while true do
  begin
      while n3=false do SysThreadSwitch;
      var1:=var3 mod 11;
      WriteConsole('-%d-',[var1]);
      n1:=true;
      n3:=false;
  end;
end;




begin
  // we create a thread each core
  var1:=0;
  var2:=4;
  var3:=11;

  tmp:= BeginThread(nil, 4096, ThreadF3, nil, 1, tmp);
  tmp:= BeginThread(nil, 4096, ThreadF2, nil, 1, tmp);


  while true do
  begin
      while n1=false do SysThreadSwitch;
      var2:=var1+5;
      n2:=true;
      n1:=false;
  end;

end.
