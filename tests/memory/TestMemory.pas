//
// TestMemory.pas
//
// This unit contains unittests for the Memory unit.
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
  r: ^Char;

begin
  test := 0;
  If ToroFreeMem(nil) = 1 then
    WriteDebug('TestFreeMem-%d: PASSED\n', [test])
  else
    WriteDebug('TestFreeMem-%d: FAILED\n', [test]);

  Inc(test);

  If ToroFreeMem(ToroGetMem(64)) <> 1 then
    WriteDebug('TestFreeMem-%d: PASSED\n', [test])
  else
    WriteDebug('TestFreeMem-%d: FAILED\n', [test]);

  Inc(test);

  if ToroGetMem(0) <> nil then
    WriteDebug('TestGetMem-%d: PASSED\n', [test])
  else
    WriteDebug('TestGetMem-%d: FAILED\n', [test]);

  Inc(test);

  if ToroGetMem(2*1024*1024*1024) = nil then
    WriteDebug('TestGetMem-%d: PASSED\n', [test])
  else
    WriteDebug('TestGetMem-%d: FAILED\n', [test]);

  Inc(test);

  while true do
  begin
    r := ToroGetMem(64);
    if r = nil then
      Break;
    try
      r^ := 'a';
    except
      WriteDebug('TestGetMem-%d: FAILED\n', [test]);
      break;
    end;
  end;

  if r = nil then
     WriteDebug('TestGetMem-%d: PASSED\n', [test]);
end.
