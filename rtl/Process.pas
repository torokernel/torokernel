//
// Process.pas
//
// Interruption handler, SMP initialization, protection, scheduler and thread manipulation
//
// Notes :
// - Stack and tls blocks of memory are not optimize by kmalloc() functions
// - The scheduler is implemented using the Cooperative Threading model approach
// - This model doesn't need lock protection
// - MAX_CPU limits the size of cpu array
// - This units implements routines for the FPC thread manager
// - the procedure CreateInitThread, create the first thread on the system with epi pointer  to PASCALMAIN procedure
// - RemoveThreadReady is only used by systhreadkill() function
//
// Changes:
// 27 /03  / 2011 : Renaming Exchange slot to MxSlots.
// 14 / 10 / 2009 : Bug Fixed In Scheduler.
// 16 / 05 / 2009 : SMP Initialization was moved to Arch Unit.
// 21 / 12 / 2008 : Bug fixed in SMP Initialization.
// 07 / 08 / 2008 : Bug fixed in Sleep
// 04 / 06 / 2007 : KW Refactoring, renaming and code formatting
// 19 / 02 / 2007 : Some modications in SuspendThread procedure.
// 10 / 02 / 2007 : Some bugs in BootCPU procedure  , now the delay work fine.
// 08 / 09 / 2006 : Implementation of Toro Thread Manager driver for FPC calls (beginthread, endthread, etc) .
// 21 / 08 / 2006 : Memory model implement .
// 12 / 08 / 2006 : New model implement by Matias Vara .
// 04 / 08 / 2006 : First version by Matias E. Vara .
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
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

unit Process;

interface

{$I Toro.inc}

uses Arch;

type
  PThread = ^TThread;
  PCPU = ^TCPU;
  TMxSlot = Pointer;
  // MxSlots[SenderID][ReceiverID] can be assigned only if slot is empty (nil)
  TMxSlots = array[0..MAX_CPU-1, 0..MAX_CPU-1] of TMxSlot;

  // Mechanism to transfer data between CPU[SenderID] --> CPU[ReceiverID] without locking mechanism
  // There is 1 global matrix of message passing slots [CPU SenderID x CPU ReceiverID]
  // 1. a Thread to be dispatched on a remote CPU is queued in CurrentCPU.ThreadsToBeDispatched[RemoteCpuID]
  // 2. Scheduling[CurrentCPU] set threads queue in CpuMxSlots[CurrentCpuID][RemoteCpuID] if empty (nil)
  // 3. Scheduling[RemoteCPU] ForEach CpuMxSlots[][RemoteCpuID] read slot and reset slot (if not empty)
  
  // Drivers fill this structure
  IOInfo = record
    DeviceState: ^boolean;
  end;

  TThreadFunc = function(Param: Pointer): PtrInt;
  TThread = record // in Toro any task is a Thread
    ThreadID: TThreadID; // thread identificator
    Next: PThread; // Next and Previous are independant of the thread created from the Parent
    Previous: PThread; // and are used for the scheduling to scan all threads for a CPU
    Parent : PThread; // pointer to parent thread
    NextSibling: PThread; // Simple tail for ThreadWait procedure
    FirstChild: PThread; // tail of childs
    IOScheduler: IOInfo;
    // th_waitpid , th_ready ...
    Flags: Byte;
    State: Byte;
    PrivateHeap: pointer;
    TerminationCode: PtrInt; // Value returned by ThreadFunc
    ErrNo: Integer; // return  error in kernel function
    //init  and argument for thread main procedure
    StartArg: Pointer;
    ThreadFunc: TThreadFunc;
    TLS: Pointer;
    StackAddress: Pointer;
    StackSize: SizeUInt;
    ret_thread_sp: Pointer;
    sleep_rdtsc: Int64; // sleep counter
    // Interface between the threads with Network Sockets
    NetworkService: Pointer;
    CPU: PCPU; // CPU on which is running this thread
  end;

  TCPU = record // every CPU have this entry
    Apicid: longint;
    CurrentThread: PThread; // thread running in this moment  , in this CPU
    Threads: PThread; // this tail is use by scheduler
    ThreadsToBeDispatched: array[0..MAX_CPU-1] of PThread;
  end;

const
  // Thread State
  tsIOPending = 5 ; // GetDevice and FreeDevice use this state
  tsReady = 2 ;
  tsSuspended = 1 ;
  tsZombie = 4 ;
  
  
// Interface function matching common declaration
function BeginThread(SecurityAttributes: Pointer; StackSize: SizeUInt; ThreadFunction: TThreadFunc; Parameter: Pointer; CreationFlags: DWORD; var ThreadID: TThreadID): TThreadID;
procedure CreateInitThread(ThreadFunction: TThreadFunc; const StackSize: SizeUInt);
function GetCurrentThread: PThread;
procedure ProcessInit;
procedure Sleep(Miliseg: longint);
procedure SysEndThread(ExitCode: DWORD);
function SysResumeThread(ThreadID: TThreadID): DWORD;
function SysSuspendThread(ThreadID: TThreadID): DWORD;
procedure SysThreadSwitch;
procedure ThreadSuspend;
procedure ThreadResume(Thread: PThread);
function ThreadWait(var TerminationCode: PtrInt): TThreadID;

var
  CPU: array[0..MAX_CPU-1] of TCPU;
  CpuMxSlots: TMxSlots;

implementation

uses
  {$IFDEF DEBUG} Debug, {$ENDIF}
  Console, Memory;

const
  CPU_NIL: LongInt = -1; // cpu_emigrate register
  SPINLOCK_FREE = 3 ; // flags for spinlock
  SPINLOCK_BUSY = 4 ;
  tfKill = 1 ; // Thread Flags signals
  EXCEP_TERMINATION = -1 ; // code of termination for exception
  THREADVAR_BLOCKSIZE: DWORD = 0 ; // size of local variables storage for every thread

{  Errno Implementation }
  //MAX_ERROR = 124;
  ECHILD		= 10;	{ No child processes }
  EAGAIN	 	= 11;	{ Try again }
  
// private procedures 
procedure SystemExit; forward;
procedure Scheduling(Candidate: PThread); forward;
procedure ThreadExit(TerminationCode: PtrInt; Schedule: Boolean); forward;
procedure ThreadMain; forward;
procedure Signaling; forward;

var
{$IFDEF FPC}
  ToroThreadManager: TThreadManager;
{$ENDIF}
  InitialThreadID: TThreadID;  // ThreadID of initial thread

//------------------------------------------------------------------------------
// Routines to capture all exceptions
//------------------------------------------------------------------------------

// Parent thread reads the termination code
procedure ExceptionHandler;
begin
  EnabledInt;
  ThreadExit(EXCEP_TERMINATION, True);
end;

procedure Excep_DIVBYZERO; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : Division by Zero', 0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

procedure Excep_OVERFLOW; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : Overflow',  0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

procedure Excep_BOUND; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : Bound instruction',  0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

procedure Excep_ILEGALINS; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : Ilegal Instruction',  0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

procedure Excep_DEVNOTAVA; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : Device not Available',  0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

procedure Excep_DF; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : Double fault',  0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

procedure Excep_STACKFAULT; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : Stack Fault',  0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

procedure Excep_GENERALP; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : General Protection',  0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

procedure Excep_PAGEFAUL; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : Page Fault',  0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

procedure Excep_FPUE; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception : Fpu error',  0, 0, 0); {$ENDIF}
  ExceptionHandler
end;

// more important Exceptions are captured
procedure InitializeINT;
begin
  CaptureInt(EXC_DIVBYZERO,@Excep_DIVBYZERO);
  CaptureInt(EXC_OVERFLOW,@Excep_OVERFLOW);
  CaptureInt(EXC_BOUND,@Excep_BOUND);
  CaptureInt(EXC_ILEGALINS,@Excep_ILEGALINS);
  CaptureInt(EXC_DEVNOTAVA,@Excep_DEVNOTAVA);
  CaptureInt(EXC_DF,@excep_DF);
  CaptureInt(EXC_STACKFAULT,@excep_STACKFAULT);
  CaptureInt(EXC_GENERALP,@excep_GENERALP);
  CaptureInt(EXC_PAGEFAUL,@excep_PAGEFAUL);
  CaptureInt(EXC_FPUE,@excep_FPUE);
end;

// Initialization of every Core in the system
procedure InitCores;
var
  I, J: longint;
begin
  PrintK_('Multicore Initialization ...\n',0);
  // cleaning all table
  for I := 0 to Max_CPU-1 do
  begin
    CPU[I].Apicid := 0 ;
    CPU[I].CurrentThread := nil;
    CPU[I].Threads :=nil;
    for J := 0 to Max_CPU-1 do
    begin
      CPU[I].ThreadsToBeDispatched[J] := nil;
      CpuMxSlots[I][J] := nil;
    end;
  end;
  if CPU_COUNT = 1 then
  begin // with one cpu we don't need any initialization proc.
    PrintK_('Core#0 ... /VOk\n/n',0);
    Exit;
  end;
  for I := 0 to CPU_COUNT-1 do
  begin
    if not Cores[I].CPUBoot and Cores[I].present then
    begin
      CPU[Cores[I].ApicID].Apicid := Cores[I].ApicID;
      Cores[I].InitProc := @Scheduling; // core jump to this procedure // !!! KW 20110802 suspect a bug here,
      // !!! the procedure Scheduling is using a parameter, but Cores[].InitProc has no parameter
      // !!! I guess this is pure luck that the RCX is nil when starting the first time InitProc
      // !!! or because the Candidate parameter is not used at first call
      // !!! it would be safer to change the procedure InitProc to match the signature of Scheduling
      // !!! this would force to call InitProc with @Candidate=nil
      InitCore(Cores[I].ApicID); // initialize the CPU
      if Cores[I].InitConfirmation then
        PrintK_('Core#%d ... /VOk\n/n', Cores[I].ApicID)
      else
        PrintK_('Core#%d ... /RFault\n/n', Cores[I].ApicID);
    end else if Cores[I].CPUBoot then
      PrintK_('Core#0 ... /VOk\n/n',0);
  end;
end;

{$IFDEF FPC}
// Manipulation of critical section by Thread Manager of FPC
procedure SysInitCriticalSection(var CS: TRTLCriticalSection);
begin
  CS.Flag := SPINLOCK_FREE;
  CS.Short := True;
end;

procedure SysEnterCriticalSection(var CS: TRTLCriticalSection);
begin
  // ??? here i have an error
  if CS.short then
  begin
    SpinLock(SPINLOCK_FREE, SPINLOCK_BUSY, CS.Flag)
    // in the long mode the thread sleep when return the lock operation is executed only one more time
  end else
  begin
    SpinLock(SPINLOCK_FREE, SPINLOCK_BUSY, CS.Flag);
    ThreadSuspend;
  end;
end;

procedure SysLeaveCriticalSection(var CS: TRTLCriticalSection);
begin
  if CS.short then
    CS.Flag := SPINLOCK_FREE
  else
  begin
    // in long mode the thread schedule next thread
    CS.Flag := SPINLOCK_FREE;
    ThreadResume(CS.lock_tail);
  end;
end;
{$ENDIF}

//------------------------------------------------------------------------------
// Threads list management
//------------------------------------------------------------------------------

// Adds a thread to ready task queue
procedure AddThreadReady(Thread: PThread);
var
  CPU: PCPU;
begin
  CPU := Thread.CPU;
  if CPU.Threads = nil then
  begin
    CPU.Threads := Thread;
    Thread.Next := Thread;
    Thread.Previous := Thread;
    Exit;
  end;
  Thread.Previous := CPU.Threads.Previous;
  Thread.Next := CPU.Threads;
  CPU.Threads.Previous.Next := Thread;
  CPU.Threads.Previous := Thread;
end;

// Removes a thread from ready task queue
procedure RemoveThreadReady(Thread: PThread);
begin
  if (Thread.CPU.Threads = Thread) and (Thread.CPU.Threads.Next = Thread.CPU.Threads) then
  begin
    Thread.CPU.Threads := nil ;
    Thread.Previous := nil;
    Thread.Next := nil;
    Exit;
  end;
  if (Thread.CPU.Threads = Thread) then
    Thread.CPU.Threads := Thread.Next;
  Thread.Previous.Next := Thread.Next;
  Thread.Next.Previous := Thread.Previous;
  Thread.Next := nil ;
  Thread.Previous := nil;
end;

// Adds a thread to emigrate array
procedure AddThreadEmigrate(Thread: PThread);
var
  ApicID: LongInt;
  FirstThread: PThread;
  CurrentCPU: PCPU;
begin
  CurrentCPU := @CPU[GetApicID];
  ApicID := Thread.CPU.ApicID;
  FirstThread := CurrentCPU.ThreadsToBeDispatched[ApicID];
  if FirstThread = nil then
  begin
    CurrentCPU.ThreadsToBeDispatched[ApicID] := Thread;
    Thread.Next := Thread;
    Thread.Previous := Thread;
  end else begin
    Thread.Previous := FirstThread.Previous;
    Thread.Next := FirstThread;
    if FirstThread.Previous <> nil then
      FirstThread.Previous.Next := Thread;
    FirstThread.Previous := Thread ;
  end;
end;

// Returns current Thread pointer running on this CPU
function GetCurrentThread: PThread; 
begin
  Result := CPU[GetApicID].CurrentThread;
end;

// Set thread state to tsSuspended. This procedure is executed in only one CPU
procedure ThreadSuspend;
begin
  GetCurrentThread.State := tsSuspended;
  {$IFDEF DebugProcess}
   DebugTrace('Thread Suspended',0,0,0);
  {$ENDIF}
  Scheduling(nil);
end;

// the thread is ready to be scheduled by the scheduler
procedure ThreadResume(Thread: PThread);
begin
  Thread.State := tsReady;
  {$IFDEF DebugProcess}
   DebugTrace('Thread Resume , Thread: %q',Int64(Thread),0,0);
  {$ENDIF}
end;

const
  Initialized: Boolean = False; // Used only for the first thread to flag if initialized

// create a new thread, in the CPU and init IP instruction
function ThreadCreate(const StackSize: SizeUInt; CPUID: DWORD; ThreadFunction: TThreadFunc; Arg: Pointer): PThread;
var
  NewThread: PThread;
  ip_ret: ^THandle;
begin
  NewThread := ToroGetMem(SizeOf(TThread));
  {$IFDEF DEBUG} DebugTrace('ThreadCreate - NewThread: %h', PtrUInt(NewThread), 0, 0); {$ENDIF}
  if NewThread = nil then
  begin
    {$IFDEF DEBUG} DebugTrace('ThreadCreate - NewThread = nil', 0, 0, 0); {$ENDIF}
    Result := nil;
    Exit;
  end;
  NewThread^.StackAddress := ToroGetMem(StackSize);
  if NewThread.StackAddress = nil  then
  begin
    {$IFDEF DEBUG} DebugTrace('ThreadCreate - NewThread.StackAddress = nil', 0, 0, 0); {$ENDIF}
    ToroFreeMem(NewThread);
    Result := nil;
    Exit;
  end;
  // Is this the  first thread ?
  if not Initialized then
  begin
    {$IFDEF DEBUG} DebugTrace('ThreadCreate - First Thread -> Initialized=True', 0, 0, 0); {$ENDIF}
    Initialized := True;
  end else if THREADVAR_BLOCKSIZE <> 0 then
  begin
    NewThread.TLS := ToroGetMem(THREADVAR_BLOCKSIZE) ;
    if NewThread.TLS = nil then
    begin // Not enough memory, Thread cannot be created
      {$IFDEF DEBUG} DebugTrace('ThreadCreate - NewThread.TLS = nil', 0, 0, 0); {$ENDIF}
      ToroFreeMem(NewThread.StackAddress);
      ToroFreeMem(NewThread);
      Result := nil;
      Exit;
    end;
  end;
  // Stack initialization
  NewThread.StackSize := StackSize;
  NewThread.ret_thread_sp := Pointer(PtrUInt(NewThread.StackAddress) + StackSize-1);
  NewThread.sleep_rdtsc := 0;
  NewThread.Flags := 0;
  NewThread.State := tsReady;
  NewThread.TerminationCode := 0;
  NewThread.ErrNo := 0;
  NewThread.StartArg := Arg; // this argument we will read by thread main
  NewThread.ThreadFunc := ThreadFunction;
  NewThread.PrivateHeap := XHeapAcquire(CPUID); // Private Heap allocator init
  NewThread.ThreadID := TThreadID(NewThread); // check protection, it is not very important
  NewThread.CPU := @CPU[CPUID];
  // New thread is added in the child queue of the parent thread (CurrentThread)
  NewThread.FirstChild := nil;
  NewThread.Parent := CPU[GetApicID].CurrentThread; // Note: for the initial thread this is not important
  NewThread.NextSibling := NewThread.Parent.FirstChild;
  NewThread.Parent.FirstChild := NewThread ; // only parent (CurrentThread) can remove or add threads to this list ---> no lock protection required
  // when executing ret_to_thread  this stack is pushed in esp register
  // when scheduling() returns (is a procedure!) return to this eip pointer
  // when thread is executed for first time thread_sp_register pointer to stack base (or end)
  ip_ret := NewThread.ret_thread_sp;
  Dec(ip_ret);
  // scheduler return
  ip_ret^ := PtrInt(@ThreadMain);
  // ebp return
  Dec(ip_ret);
  ip_ret^ := PtrUInt(NewThread.ret_thread_sp) - SizeOf(Pointer);
  NewThread.ret_thread_sp := Pointer(PtrUInt(NewThread.ret_thread_sp) - SizeOf(Pointer)*2);
  if CPUID = GetApicID then
    AddThreadReady(NewThread)
  else
    AddThreadEmigrate(NewThread);
  Result := NewThread;
end;

// free all memory structures of the thread, called after waitpid function.
// These blocks of memory live in parent thread CPU
procedure ThreadFree(Thread: PThread);
begin
  if THREADVAR_BLOCKSIZE <> 0 then
    ToroFreeMem(Thread.TLS);
  ToroFreeMem (Thread.StackAddress);
  ToroFreeMem(Thread);
end;

// Sleep current thread for SleepTime .
procedure Sleep(Miliseg: Longint);
var
  CurrentTime,ResumeTime,CountTime,tmp: Int64;
begin
  CountTime := 0;
  ResumeTime := Miliseg*LocalCPUSpeed*1000;
  {$IFDEF DebugProcess} DebugTrace('Sleep - ResumeTime: %q', ResumeTime, 0, 0); {$ENDIF}
  while CountTime < ResumeTime do
  begin
     CurrentTime:= read_rdtsc;
     Scheduling(nil);
     tmp:=read_rdtsc;
     if tmp > CurrentTime then
      CountTime:= CountTime + tmp - CurrentTime
     else
      CountTime:= CountTime + ($ffffffff-CurrentTime+tmp);
  end;
  {$IFDEF DebugProcess} DebugTrace('Sleep - ResumeTime exiting', 0, 0, 0); {$ENDIF}
end;

// Parent thread waits for return of child thread, returns the Termination code and the ThreadID of Child.
// Note: simliar to waitpid function in linux system. Returns TerminationCode value and ThreadID.
function ThreadWait(var TerminationCode: PtrInt): TThreadID;
var
  ChildThread: PThread;
  NextSibling: PThread;
  PreviousThread: PThread;
begin
  while True do
  begin
    // Find in the simple tail of son
    ChildThread := CPU[GetApicID].CurrentThread;
    if ChildThread = nil then
    begin
      Result := 0;
      Exit;
    end;
    ChildThread := ChildThread.FirstChild;
    if ChildThread = nil then
    begin
      // No child
      Result := 0;
      Exit;
    end;
    PreviousThread := nil ;
    while ChildThread <> nil do
    begin
      // Waiting for me ??
      if ChildThread.State = tsZombie then
      begin
        TerminationCode := ChildThread.TerminationCode;
        Result := ChildThread.ThreadID ;
        NextSibling := ChildThread.NextSibling ;
        if PreviousThread <> nil then
          PreviousThread.NextSibling := NextSibling
        else
          GetCurrentThread.FirstChild := NextSibling;
        // stack and tls is allocated from parent CPU and must released by the Parent
        ThreadFree(ChildThread);
        {$IFDEF DebugProcess} DebugTrace('ThreadWait: ThreadID %d', SizeUInt(Result), 0, 0); {$ENDIF}
        Exit;
      end
      else begin
        PreviousThread := ChildThread ;
        ChildThread := ChildThread.NextSibling;
      end;
    end;
    // wait
    Scheduling(nil);
  end;
end;

// actual thread is dead and the status is the termination register in TThread
procedure ThreadExit(TerminationCode: PtrInt; Schedule: Boolean);
var
  CurrentThread, NextThread: PThread;
begin
  CurrentThread := GetCurrentThread ;
  // Free memory allocated by PrivateHeap
  XHeapRelease(CurrentThread.PrivateHeap);
  CurrentThread.TerminationCode := TerminationCode;
  if TerminationCode = EXCEP_TERMINATION then
   printk_('Exception happens on Thread %d\n',PtrUint(CurrentThread));
  // this is not important if next_sched = curr_th then tq_Ready = nil
  NextThread := CurrentThread.Next;
  RemoveThreadReady(CurrentThread);
  CurrentThread.State := tsZombie;
  {$IFDEF DebugProcess} DebugTrace('ThreadExit - ThreadID: %q', CurrentThread.ThreadID, 0, 0); {$ENDIF}
  if Schedule then  // Go to Scheduling and next exit ??
    Scheduling(NextThread);
end;

// The thread(ThreadID) is dead, only parent thread can execute this function
function SysKillThread(ThreadID: TThreadID): DWORD;
var
  CurrentThread: PThread;
  Thread: PThread;
begin
  Thread := PThread(ThreadID);
  CurrentThread := CPU[GetApicID].CurrentThread;
  if CurrentThread = nil then
  begin
    Result := 0;
    Exit;
  end;
  // only parent thread can perform a KillThread . Warning: the pointer may be incorrect (corrupted)
  if Thread.Parent.ThreadID <> CurrentThread.ThreadID then
  begin
    CurrentThread.ErrNo := -ECHILD;
    Result := DWORD(-1);
    Exit;
  end;
{$IFDEF DebugProcess} DebugTrace('SysKillThread - sending signal to Thread: %q in CPU: %d \n', ThreadID, Thread.CPU.ApicID,0); {$ENDIF}
  Thread.Flags := tfKill;
  Result := 0;
end;

function SysSuspendThread(ThreadID: TThreadID): DWORD;
var
  CurrentThread: PThread;
  Thread: PThread;
begin
  Thread := PThread(ThreadID);
  CurrentThread := CPU[GetApicID].CurrentThread;
  if CurrentThread = nil then
  begin
    Result := 0;
    Exit;
  end;
  // Current Thread is Suspended
  if (Thread = nil) or (CurrentThread.ThreadID = ThreadID) then
  begin
    CurrentThread.state := tsSuspended;
    SysThreadSwitch;
    {$IFDEF DebugProcess} DebugTrace('SuspendThread: Current Threads was Suspended',0,0,0); {$ENDIF}
  end;
  // only parent thread can perform a SuspendThread
  if Thread.Parent.ThreadID <> CurrentThread.ThreadID then
  begin
    CurrentThread.ErrNo := -ECHILD;
    Result := DWORD(-1);
    Exit;
  end;
  Thread.State := tsSuspended;
  Result := 0;
end;

// The thread is wake , you must execute thread_resume in this order thread_suspend ---> thread_resume , because the
// thread can interrupt waiting one irq
function SysResumeThread(ThreadID: TThreadID): DWORD;
var
  CurrentThread: PThread;
  Thread: PThread;
begin
  Thread := PThread(ThreadID);
  CurrentThread := CPU[GetApicID].CurrentThread;
  if CurrentThread = nil then 
  begin
    Result := 0;
    Exit;
  end;
  // only parent thread can perform a ResumeThread
  if Thread.Parent.ThreadID <> CurrentThread.ThreadID then
  begin
    CurrentThread.ErrNo := -ECHILD;
    Result := DWORD(-1);
    Exit; // added by KW 20110730, I presume this was the intended behavior
  end;
  ThreadResume(Thread);
  Result := 0;
end;

//
// Scheduling model implementation
//

// Import waiting threads from other CPUs to local list of Threads
procedure Inmigrating(CurrentCPU: PCPU);
var
  RemoteCpuID: LongInt;
  EmigrateThreads: PThread; // tail to threads in emigrate array
  LastThread: PThread;
begin
  for RemoteCpuID := 0 to CPU_COUNT-1 do
  begin
    if CpuMxSlots[CurrentCPU.ApicID][RemoteCpuID] <> nil then
    begin
      EmigrateThreads := CpuMxSlots[CurrentCPU.ApicID][RemoteCpuID];
      if CurrentCPU.Threads = nil then
      	CurrentCPU.Threads := EmigrateThreads
      else
      begin
        EmigrateThreads.Previous.Next := CurrentCPU.Threads;
	      LastThread := EmigrateThreads.Previous;
        EmigrateThreads.Previous := CurrentCPU.Threads.Previous;
        if CurrentCPU.Threads.Previous <> nil then
          CurrentCPU.Threads.Previous.Next := EmigrateThreads;
        CurrentCPU.Threads.Previous := LastThread;
      end;
      CpuMxSlots[CurrentCPU.ApicID][RemoteCpuID] := nil;
      {$IFDEF DebugProcessInmigrating}DebugTrace('Inmigrating - from CPU %d to LocalCPU %d', 0, RemoteCpuID, CurrentCPU.ApicID);{$ENDIF}
    end;
  end;
end;

// Move pending threads to remote CPUs waiting list
procedure Emigrating(CurrentCPU: PCPU);
var
  RemoteCpuID: LongInt;
begin
  for RemoteCpuID := 0 to CPU_COUNT-1 do
  begin
    if (CurrentCPU.ThreadsToBeDispatched[RemoteCpuID] <> nil) and (CpuMxSlots[RemoteCpuID][CurrentCPU.ApicID] = nil) then
    begin
      CpuMxSlots[RemoteCpuID][CurrentCPU.ApicID] := CurrentCPU.ThreadsToBeDispatched[RemoteCpuID];
      CurrentCPU.ThreadsToBeDispatched[RemoteCpuID]:= nil;
      {$IFDEF DebugProcessEmigrating} DebugTrace('Emigrating - Switch Threads of DispatchArray[%d] to EmigrateArray[%d]', 0, CurrentCPU.ApicID, RemoteCpuID); {$ENDIF}
    end;
  end;
end;

// This is the Scheduler
// Schedule next thread, the current thread must be added in the appropriate list (CPU[].ThreadsToBeDispatched) and have saved its registers
procedure Scheduling(Candidate: PThread); {$IFDEF FPC} [public , alias :'scheduling']; {$ENDIF}
var
  CurrentCPU: PCPU;
  CurrentThread: PThread;
begin
  CurrentCPU := @CPU[GetApicID];
  while True do
  begin
    // in the first moment I am here
    if CurrentCPU.Threads = nil then
    begin
      // spin of init
      while CurrentCPU.Threads = nil do
    		Inmigrating(CurrentCPU);
      CurrentCPU.CurrentThread := CurrentCPU.Threads;
      {$IFDEF DebugProcess} DebugTrace('Scheduling: Jumping to Current Thread, StackPointer return: %q', PtrUInt(CurrentCPU.CurrentThread.ret_thread_sp), 0, 0); {$ENDIF}
      SwitchStack(nil, @CurrentCPU.CurrentThread.ret_thread_sp);
      // jump to thread execution
      Exit;
    end;  
    Emigrating(CurrentCPU); // send new threads to others cpus
    Inmigrating(CurrentCPU); // give new threads to tq_ready of local CPU
    CurrentThread := CurrentCPU.CurrentThread;
    if Candidate = nil then
      Candidate := CurrentThread.Next;
    repeat
      if Candidate.State = tsReady then
        Break
      else if (Candidate.State = tsIOPending) and not Candidate.IOScheduler.DeviceState^ then
      begin
        // The device has completed its operation -> Candidate thread is ready to continue its process
        Candidate.State:= tsReady;
				Break;
      end else begin
    	Candidate := Candidate.Next;
      end;
    until Candidate = CurrentThread;
    if Candidate.State <> tsReady then
      Continue;
    CurrentCPU.CurrentThread := Candidate;
    {$IFDEF DebugProcess}DebugTrace('Scheduling: Jumping to Current Thread , stack pointer: %q', PtrUInt(Candidate.ret_thread_sp), 0, 0);{$ENDIF}
    if Candidate = CurrentThread then
      Exit;
    SwitchStack(@CurrentThread.ret_thread_sp, @Candidate.ret_thread_sp);
    Break;
  end;
end;

// Controls the execution of current thread flags
procedure Signaling;
begin
  if CPU[GetApicID].CurrentThread.Flags = tfKill then
  begin
    {$IFDEF DebugProcess} DebugTrace('Signaling - killing CurrentThread', 0, 0, 0); {$ENDIF}
    ThreadExit(0, True);
  end;
end;

//------------------------------------------------------------------------------
// Threadvar routines
//------------------------------------------------------------------------------

// Called by CreateInitThread
procedure SysInitThreadVar(var Offset: DWORD; Size: DWORD);
begin
  Offset := THREADVAR_BLOCKSIZE;
  THREADVAR_BLOCKSIZE := THREADVAR_BLOCKSIZE+Size;
end;

// Returns pointer to offset in the first block of memory of thread allocation
function SysRelocateThreadvar(Offset: DWORD): Pointer;
var
  CurrentThread: PThread;
begin
  CurrentThread := GetCurrentThread;
  Result := Pointer(PtrUInt(CurrentThread.TLS)+Offset)
end;

// Allocates in thread allocation memory for thread local storange . Is only use in the first moment for init thread
// the allocation for tls is in create thread procedure
procedure SysAllocateThreadVars;
var
  CpuID: Byte;
begin
  CpuID := GetApicID;
  CPU[CpuID].CurrentThread.TLS := ToroGetMem(THREADVAR_BLOCKSIZE) ;
  {$IFDEF DebugProcess} DebugTrace('SysAllocateThreadVars - pointer: %q , size: %d',SizeUint(CPU[CpuID].CurrentThread.TLS), THREADVAR_BLOCKSIZE, 0); {$ENDIF}
end;

// called from Kernel.KernelStart
// All begins here, the user program is executed like the init thread, the init thread can create additional threads.
procedure CreateInitThread(ThreadFunction: TThreadFunc; const StackSize: SizeUInt);
var
  InitThread: PThread;
  LocalCPU: PCPU;
begin
  PrintK_('CreateInitThread\n', 0);
  LocalCPU := @CPU[GetApicID];
  InitThread := ThreadCreate(StackSize, LocalCPU.ApicID, ThreadFunction, nil);
  if InitThread = nil then
  begin
    PrintK_('InitThread = nil\n', 0);
    hlt;
  end;
  InitThread.NextSibling := nil ;
  LocalCPU.CurrentThread := InitThread;
  InitialThreadID := TThreadID(InitThread);
  PrintK_('User Application Initialization ... \n', 0);
  // only performed explicitely for initialization procedure
  {$IFDEF FPC} InitThreadVars(@SysRelocateThreadvar); {$ENDIF}
  // TODO: InitThreadVars for DELPHI
  {$IFDEF DebugProcess} DebugTrace('CreateInitThread - InitialThreadID: %q', SizeUint(InitialThreadID), 0, 0); {$ENDIF}
  // now we have in the stack ip pointer for ret instruction
  // TODO: when compiling with DCC, check that previous assertion is correct
  // TODO: when previous IFDEF is activated, check that DebugTrace is not messing
  InitThread.ret_thread_sp := Pointer(PtrUInt(InitThread.ret_thread_sp)+SizeOf(Pointer));
  change_sp(InitThread.ret_thread_sp);
  // the procedure "PASCALMAIN" is executed (this is the ThreadFunction in parameter)
end;

// The current thread is remaining in tq_ready tail and the next thread is scheduled
procedure SysThreadSwitch;
begin
  Scheduling(nil);
  Signaling;
end;

// The execution of threads starts here, global variables are initialized
procedure ThreadMain;
var
  CurrentThread: PThread;
  ExitCode: PtrInt;
  ChildExitCode: PtrInt;
begin
  CurrentThread := GetCurrentThread ;
  // Open standard IO files, stack checking, iores, etc .
  {$IFDEF FPC} InitThread(CurrentThread.StackSize); {$ENDIF}
  // TODO: !!! InitThread() for Delphi
  {$IFDEF DebugProcess} DebugTrace('ThreadMain: #%q', PtrInt(CurrentThread), 0, 0); {$ENDIF}
  ExitCode := CurrentThread.ThreadFunc(CurrentThread.StartArg);
  // waiting for all child to terminate before main thread can terminate
  while CurrentThread.FirstChild <> nil do
    ThreadWait(ChildExitCode);
  if CurrentThread.ThreadID = InitialThreadID then
    SystemExit; // System is ending !
  ThreadExit(ExitCode, True);
end;

// Create new thread and return the thread id  , we don't need save context .
function SysBeginThread(SecurityAttributes: Pointer; StackSize: SizeUInt; ThreadFunction: TThreadFunc; Parameter: Pointer;
                         CPU: DWORD; var ThreadID: TThreadID): TThreadID;
var
  NewThread: PThread;
begin
  if (LongInt(CPU) = CPU_NIL) or (LongInt(CPU) > CPU_COUNT-1) then
    CPU := GetApicID; // Invalid CpuID -> create thread on current CPU
  NewThread := ThreadCreate(StackSize, CPU, ThreadFunction, Parameter);
  if NewThread = nil then
  begin
    ThreadID := 0;
    GetCurrentThread.ErrNo := -EAGAIN;
    {$IFDEF DebugProcess} DebugTrace('BeginThread - ThreadCreate Failed', 0, 0, 0); {$ENDIF}
    Result := 0;
    Exit;
  end;
  ThreadID := NewThread.ThreadID;
  {$IFDEF DebugProcess} DebugTrace('BeginThread - new ThreadID: %q in CPU %d', NewThread.ThreadID, NewThread.CPU.ApicID, 0); {$ENDIF}
  Result := NewThread.ThreadID;
end;

// Interface function matching the RTL declaration
function BeginThread(SecurityAttributes: Pointer; StackSize: SizeUInt; ThreadFunction: TThreadFunc; Parameter: Pointer; CreationFlags: DWORD; var ThreadID: TThreadID): TThreadID;
begin
  Result := SysBeginThread(SecurityAttributes, StackSize, ThreadFunction, Parameter, CreationFlags, ThreadID);
end;

// The thread is dead and ExitCode is set as Termination code in TThread
procedure SysEndThread(ExitCode: DWORD);
begin
  ThreadExit(ExitCode, True);
end;

// Return the ThreadID of the current running thread
function SysGetCurrentThreadID: TThreadID;
begin
  Result := CPU[GetApicID].CurrentThread.ThreadID;
end;

// When the initial thread exits, the system must be turned off
procedure SystemExit;
begin
  // here is needed fs for sync procedures
  {$IFDEF DebugProcess} DebugPrint('SystemExit\n', 0, 0, 0); {$ENDIF}
  printk_('\nSystem Termination, please turn off or reboot\n', 0);
  {$IFDEF DebugProcess} DebugPrint('SystemExit - Debug end -> hlt\n', 0, 0, 0); {$ENDIF}
  hlt;
end;

// Initialize all local structures and send the INIT IPI to all cpus  
procedure ProcessInit;
begin
  // initialize the exception and irq
  if HasException then
    InitializeINT;
  {$IFDEF DebugProcess} DebugTrace('CPU Speed: %d Mhz', 0, LocalCpuSpeed, 0); {$ENDIF}
  InitCores;
  // Functions to manipulate threads. Transparent for pascal programmers
{$IFDEF FPC}
  with ToroThreadManager do
  begin
    InitManager            := nil;
    DoneManager            := nil;
    BeginThread            := @SysBeginThread;
    EndThread              := @SysEndThread;
    SuspendThread          := @SysSuspendThread;
    ResumeThread           := @SysResumeThread;
    KillThread             := @SysKillthread;
    ThreadSwitch           := @SysThreadSwitch;
    WaitForThreadTerminate := nil;
    ThreadSetPriority      := nil;
    ThreadGetPriority      := nil;
    GetCurrentThreadId     := @SysGetCurrentThreadID;
    InitCriticalSection    := @SysInitCriticalSection;
    DoneCriticalSection    := nil;
    EnterCriticalSection   := @SysEnterCriticalSection ;
    LeaveCriticalSection   := @SysLeaveCriticalSection;
    InitThreadVar          := @SysInitThreadVar;
    RelocateThreadVar      := @SysRelocateThreadVar;
    AllocateThreadVars     := @SysAllocateThreadVars;
    ReleaseThreadVars      := nil;
    BasicEventCreate       := nil;
    BasicEventDestroy      := nil;
    BasicEventResetEvent   := nil;
    BasicEventSetEvent     := nil;
    BasiceventWaitFor      := nil;
    RTLEventCreate         := nil;
    RTLEventDestroy        := nil;
    RTLEventSetEvent       := nil;
    RTLEventResetEvent     := nil;
    RTLEventStartWait      := nil;
    RTLEventWaitFor        := nil;
    RTLEventWaitForTimeout := nil;
  end;
  SetThreadManager(ToroThreadManager);
{$ENDIF}
end;

end.

