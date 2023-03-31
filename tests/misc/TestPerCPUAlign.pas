//
// TestPerCPUAlign.pas
//
// This unit tests the alignment of per-CPU variables.
//
// Copyright (c) 2003-2023 Matias Vara <matiasevara@torokernel.io>
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

program TestPerCPUAlign;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

uses
  Kernel,
  Process,
  Memory,
  Debug,
  Arch,
  Filesystem,
  Network,
  Console,
  VirtIO,
  VirtIOConsole;

var
  test: LongInt;

function TestProcess: Boolean;
var
  m: LongInt;
begin
  Result := False;
  for m:= 0 to MAX_CPU-1 do
  begin
    if (PtrUInt(@CPU[m]) mod (CACHELINE_LEN*sizeof(QWORD)) <> 0) then
      Exit;
  end;
  Result := True;
end;

function TestStorages: Boolean;
var
  m: LongInt;
begin
  Result := False;
  for m:= 0 to MAX_CPU-1 do
  begin
    if (PtrUInt(@Storages[m]) mod (CACHELINE_LEN*sizeof(QWORD)) <> 0) then
      Exit;
  end;
  Result := True;
end;

function TestPerCPUVar: Boolean;
var
  m: LongInt;
begin
  Result := False;
  for m:= 0 to MAX_CPU-1 do
  begin
    if (PtrUInt(@PerCPUVar[m]) mod (CACHELINE_LEN*sizeof(QWORD)) <> 0) then
      Exit;
  end;
  Result := True;
end;

begin
  If TestProcess then
    WriteDebug('TestProcess: PASSED\n', [])
  else
    WriteDebug('TestProcess: FAILED\n', []);

  If TestStorages then
    WriteDebug('TestStorages: PASSED\n', [])
  else
    WriteDebug('TestStorages: FAILED\n', []);

  If TestPerCPUVar then
    WriteDebug('TestPerCPUVar: PASSED\n', [])
  else
    WriteDebug('TestPerCPUVar: FAILED\n', []);

end.
