//
// TestProcess.pas
//
// This program contains unittests for the Process unit.
//
// Copyright (c) 2003-2021 Matias Vara <matiasevara@gmail.com>
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

program TestProcess;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{$ASMMODE Intel}

uses
  SysUtils,
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
  test, ret: LongInt;

function Thread(Param: Pointer):PtrInt;
begin
  if PtrUInt(Param) = $12345 then
    ret := 0
  else
    ret := 1;
  Result := 0;
end;

function ThreadLoop(Param: Pointer):PtrInt;
begin
  While true do
    SysThreadSwitch;
end;

function TestThreadSwitch(out test: Longint): Boolean;
var
  rbx_reg, rbx_regb: QWord;
  rdi_reg, rdi_regb: QWord;
  rsi_reg, rsi_regb: QWord;
  r12_reg, r12_regb: QWord;
  r13_reg, r13_regb: QWord;
  r14_reg, r14_regb: QWord;
  r15_reg, r15_regb: QWord;
  tmp: TThreadID;
begin
  test := 0;

  //tmp := BeginThread(nil, 4096, ThreadLoop, nil, 0, tmp);

  Result := false;
  asm
    mov rbx_reg, rbx
    mov rsi_reg, rsi
    mov rdi_reg, rdi
    mov r12_reg, r12
    mov r13_reg, r13
    mov r14_reg, r14
    mov r15_reg, r15
  end;

  SysThreadSwitch;
  SysThreadSwitch;

  asm
    mov rbx_regb, rbx
    mov rsi_regb, rsi
    mov rdi_regb, rdi
    mov r12_regb, r12
    mov r13_regb, r13
    mov r14_regb, r14
    mov r15_regb, r15
  end;

  if rbx_reg <> rbx_regb then
    Exit;

  if rdi_reg <> rdi_regb then
    Exit;

  if rsi_reg <> rsi_regb then
    Exit;

  if r12_reg <> r12_regb then
    Exit;

  if r13_reg <> r13_regb then
    Exit;

  if r14_reg <> r14_regb then
    Exit;

  if r15_reg <> r15_regb then
    Exit;

  Result := true;
end;

procedure TestBeginThread;
var
  test: LongInt;
  tmp: TThreadID;
begin
  test := 0;
  ret := 2;
  tmp := BeginThread(nil, 4096, Thread, Pointer($12345), 0, tmp);

  while ret = 2 do
    SysThreadSwitch;

  if ret = 1 then
    WriteDebug('TestBeginThread-%d: FAILED\n', [test])
  else
    WriteDebug('TestBeginThread-%d: PASSED\n', [test]);

  ret := 2;
  Inc (test);
  tmp := BeginThread(nil, 4096, Thread, Pointer($12345), 1, tmp);

  while ret = 2 do
    SysThreadSwitch;

  if ret = 1 then
    WriteDebug('TestBeginThread-%d: FAILED\n', [test])
  else
    WriteDebug('TestBeginThread-%d: PASSED\n', [test]);
end;

procedure TestExceptions;
var
  Q, R, test: Longint;
  p: ^LongInt;
begin
  test := 0;
  try
    Q := 5;
    R := 0;
    R := Q div R;
    WriteDebug('TestExceptions-%d: FAILED\n', [test]);
  except
    WriteDebug('TestExceptions-%d: PASSED\n', [test])
  end;
  Inc(test);
  try
    p := pointer($ffffffffffffffff);
    p^ := $1234;
    WriteDebug('TestExceptions-%d: FAILED\n', [test]);
  except
    WriteDebug('TestExceptions-%d: PASSED\n', [test]);
  end;
end;

procedure TestSleep;
var
  ResumeTime: Int64;
begin
  ResumeTime := read_rdtsc + 2 * LocalCPUSpeed * 1000;
  Sleep(2);
  // tolerate no more than 1 ms of error
  if (read_rdtsc - ResumeTime) > (1 * LocalCPUSpeed * 1000) then
    WriteDebug('TestSleep: FAILED\n', [])
  else
    WriteDebug('TestSleep: PASSED\n', []);
end;

begin
  TestBeginThread;
  if TestThreadSwitch(test) then
    WriteDebug('TestThreadSwitch-%d: PASSED\n', [test])
  else
    WriteDebug('TestThreadSwitch-%d: FAILED\n', [test]);
  TestExceptions;
  TestSleep;
end.
