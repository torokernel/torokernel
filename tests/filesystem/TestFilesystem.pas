//
// TestFilesystem.pas
//
// This program contains unittests for the Filesystem unit.
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

program TestFilesystem;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

uses
  Kernel in '..\..\rtl\Kernel.pas',
  Process in '..\..\rtl\Process.pas',
  Memory in '..\..\rtl\Memory.pas',
  Debug in '..\..\rtl\Debug.pas',
  Arch in '..\..\rtl\Arch.pas',
  FileSystem in '..\..\rtl\Filesystem.pas',
  Pci in '..\..\rtl\Pci.pas',
  Network in '..\..\rtl\Network.pas',
  Console in '..\..\rtl\drivers\Console.pas',
  Fat in '..\..\rtl\drivers\Fat.pas',
  VirtIOBlk in '..\..\rtl\drivers\VirtIOBlk.pas';

const
  longname: Pchar = 'testtesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttest';
  noendname: array[0..4] of char = 'aaaaa';
  content: Pchar = 'abcdefeedfegghkkgiugjfhuiifjijefij';

var
  test, i: LongInt;
  idx: TInode;
  buf: char;
  buf2: ^char;
  tmp: THandle;

begin
  DedicateBlockDriver('virtioblk', 0);
  SysMount('fat', 'virtioblk', 0);

  test := 0;
  if SysOpenFile('/1kfile') = 0 then
    WriteDebug('TestOpen-%d: FAILED\n', [test])
  else
    WriteDebug('TestOpen-%d: PASSED\n', [test]);

  Inc(test);

  if SysOpenFile('/dir/1kfile') = 0 then
    WriteDebug('TestOpen-%d: FAILED\n', [test])
  else
    WriteDebug('TestOpen-%d: PASSED\n', [test]);

  Inc(test);

  if SysOpenFile('/dir') = 0 then
    WriteDebug('TestOpen-%d: FAILED\n', [test])
  else
    WriteDebug('TestOpen-%d: PASSED\n', [test]);

  Inc(test);

  try
    SysOpenFile(longname);
    WriteDebug('TestOpen-%d: PASSED\n', [test]);
  except
    WriteDebug('TestOpen-%d: FAILED\n', [test]);
  end;

  Inc(test);

  try
    SysOpenFile('/filenametooooolong');
    WriteDebug('TestOpen-%d: PASSED\n', [test]);
  except
    WriteDebug('TestOpen-%d: FAILED\n', [test]);
  end;

  Inc(test);

  try
    SysOpenFile('/dir/filenametooooolong');
    WriteDebug('TestOpen-%d: PASSED\n', [test]);
  except
    WriteDebug('TestOpen-%d: FAILED\n', [test]);
  end;

  Inc(test);

  try
    SysOpenFile(@noendname);
    WriteDebug('TestOpen-%d: PASSED\n', [test]);
  except
    WriteDebug('TestOpen-%d: FAILED\n', [test]);
  end;

  Inc(test);

  SysStatFile('/emptyfile', @idx);

  if idx.Size <> 0 then
    WriteDebug('TestStat-%d: FAILED\n', [test])
  else
    WriteDebug('TestStat-%d: PASSED\n', [test]);

  Inc(test);
  SysStatFile('/1kfile', @idx);

  if idx.Size <> 1024 then
    WriteDebug('TestStat-%d: FAILED\n', [test])
  else
    WriteDebug('TestStat-%d: PASSED\n', [test]);

  Inc(test);
  SysStatFile('/10kfile', @idx);

  if idx.Size <> 10*1024 then
    WriteDebug('TestStat-%d: FAILED\n', [test])
  else
    WriteDebug('TestStat-%d: PASSED\n', [test]);

  Inc(test);
  SysStatFile('/100kfile', @idx);

  if idx.Size <> 100*1024 then
    WriteDebug('TestStat-%d: FAILED\n', [test])
  else
    WriteDebug('TestStat-%d: PASSED\n', [test]);

  Inc(test);
  SysStatFile('/1Mfile', @idx);

  if idx.Size <> 1024*1024 then
    WriteDebug('TestStat-%d: FAILED\n', [test])
  else
    WriteDebug('TestStat-%d: PASSED\n', [test]);

  Inc(test);
  tmp := SysOpenFile('/1Mfilezero');
  i := 0;

  while SysReadFile (tmp, 1, @buf) <> 0 do
  begin
    Inc(i);
    if buf <> #0 then
      Break;
  end;

  if i <> (1024*1024-1) then
    WriteDebug('TestRead-%d: FAILED\n', [test])
  else
    WriteDebug('TestRead-%d: PASSED\n', [test]);

  SysCloseFile(tmp);

  Inc(test);
  tmp := SysOpenFile('/1Mfilezero');

  buf2 := ToroGetMem(1024*1024);
  SysReadFile (tmp, 1024*1024, buf2);

  for i:= 0 to 1024*1024-1 do
  begin
    if buf2[i] <> #0 then
      Break;
  end;
  if i <> 1024*1024-1 then
    WriteDebug('TestRead-%d: FAILED\n', [test])
  else
    WriteDebug('TestRead-%d: PASSED\n', [test]);

  SysCloseFile(tmp);
  Inc(test);

  tmp := 0;

  try
    tmp := SysCreateFile('/test');
    WriteDebug('TestRead-%d: PASSED\n', [test]);
  except
    WriteDebug('TestRead-%d: FAILED\n', [test]);
  end;

  if tmp <> 0 then
  begin
    Inc(test);
    SysWriteFile(tmp, StrLen(content), content);
    SysCloseFile(tmp);

    tmp := SysOpenFile('/test');
    i := 0;

    while SysReadFile(tmp, 1, @buf) <> 0 do
    begin
      if buf <> content[i] then
        Break;
      Inc(i);
    end;

    if i <> StrLen(content) then
      WriteDebug('TestWrite-%d: FAILED\n', [test])
    else
      WriteDebug('TestWrite-%d: PASSED\n', [test]);
  end;

  ShutdownInQemu;
end.
