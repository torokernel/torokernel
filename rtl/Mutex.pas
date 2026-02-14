//
// This unit implements a local cooperative mutex.
// Threads that fail to acquire the mutex are
// suspended in a wait queue until the mutex is
// released.
//
// Copyright (c) 2003-2026 Matias Vara <matiasevara@torokernel.io>
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
unit Mutex;

{$I Toro.inc}

interface

uses
  RingBuffer;

type
  PMutex = ^TMutex;
  TMutex = record
    Locked: Boolean;
    WaitQueue: PRingBuffer;
  end;

function MutexInit(Size: LongInt): PMutex;
procedure MutexLock(M: PMutex);
procedure MutexUnlock(M: PMutex);

implementation

uses
  Memory, Process;

{$MACRO ON}
{$DEFINE SaveContext:=
 asm
  push rbx
  push rdi
  push rsi
  push r12
  push r13
  push r14
  push r15
 end;}
{$DEFINE RestoreContext:=
asm
 pop r15
 pop r14
 pop r13
 pop r12
 pop rsi
 pop rdi
 pop rbx
end;}

function MutexInit(Size: LongInt): PMutex;
var
  M: PMutex;
begin
  M := ToroGetMem(SizeOf(TMutex));
  if M = nil then
  begin
    Result := nil;
    Exit;
  end;
  M.Locked := False;
  M.WaitQueue := RingCreate(Size);
  if M.WaitQueue = nil then
  begin
    ToroFreeMem(M);
    Result := nil;
    Exit;
  end;
  Result := M;
end;

procedure MutexLock(M: PMutex);
begin
  if not M.Locked then
  begin
    M.Locked := True;
    Exit;
  end;
  // Mutex is locked: suspend in wait queue
  RingPush(M.WaitQueue, GetCurrentThread);
  GetCurrentThread.State := tsSuspended;
  SaveContext;
  Scheduling;
  RestoreContext;
end;

procedure MutexUnlock(M: PMutex);
var
  Thread: PThread;
begin
  Thread := RingPop(M.WaitQueue);
  if Thread <> nil then
  begin
    // Wake up the first waiter and transfer
    // ownership
    Thread.State := tsRunnable;
    AddThreadToRunQueue(Thread);
  end else
    M.Locked := False;
end;

end.
