//
// TestMemory.pas
//
// This unit contains unit-tests of the Memory unit. 
// 
// Copyright (c) 2003-2019 Matias Vara <matiasevara@gmail.com>
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

program TestMemory;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{$DEFINE EnableDebug}
{$DEFINE DebugCrash}

uses
  Kernel in '..\..\rtl\Kernel.pas',
  Process in '..\..\rtl\Process.pas',
  Memory in '..\..\rtl\Memory.pas',
  Debug in '..\..\rtl\Debug.pas',
  Arch in '..\..\rtl\Arch.pas',
  FileSystem in '..\..\rtl\Filesystem.pas',
  Pci in '..\..\rtl\Pci.pas',
  Network in '..\..\rtl\Network.pas',
  Console in '..\..\rtl\drivers\Console.pas';

var
  test: LongInt;

function TestGetMem(out test: Longint): Boolean;
begin
  Result := False;
  test := 0;
  If ToroGetMem(0) = nil then
    Exit;
  Inc(test);  
  If ToroGetMem(1) = nil then
    Exit;
  Inc(test);
  If ToroGetMem(2*1024*1024*1024) <> nil then
    Exit;
  Result := True; 
end;

function TestFreeMem(out test: LongInt): Boolean;
begin
  Result := False;
  test := 0;
  If ToroFreeMem(nil) = 0 then
    Exit;
  Inc(test); 
  // this must trigger a panic()
  //If ToroFreeMem($ffffff) = 0 then
  //  Exit;
  //Inc(test);
  If ToroFreeMem(ToroGetMem(64)) = 1 then
    Exit;
  Result := True;
end;

function TestStressMemory(out test: Longint): Boolean;
var
  i: Longint;
begin
  Result := False;
  test := 0;
  i := 0;
  while true do
  begin
    if ToroGetMem(64) = nil then
      Break;
    i += 1;
  end;
  // number of allocations of 64 bytes for 256Mb per core
  if i <> 1765080 Then
    Exit;
  Result := True;
end;

begin
  // TODO: Neither exceptions nor panics are captured
  if TestGetMem(test) then
    WriteDebug('TestGetMem: PASSED\n', [])
  else
    WriteDebug('TestGetMem: FAILED, %d\n', [test]);

  if TestFreeMem(test) then
    WriteDebug('TestFreeMem: PASSED\n', [])
  else
    WriteDebug('TestFreeMem: FAILED\n', []);
  
  if TestStressMemory(test) then
    WriteDebug('TestStressMemory: PASSED\n', [])
  else
    WriteDebug('TestStressMemory: FAILED\n', []);

  ShutdownInQemu;
end.
