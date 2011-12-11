//
// Process.pas
//
// Interruption handler, SMP initialization, protection, scheduler and thread manipulation
//
// Notes :
// - Stack and tls blocks of memory are not optimize by kmalloc() functions
// - The scheduler is implemented using the Cooperative Threading model approach
// - This model does not need lock protection
// - MAX_CPU limits the size of cpu array
// - This units implements routines for the FPC thread manager
// - the procedure CreateInitThread, create the first thread on the system with epi pointer  to PASCALMAIN procedure
// - RemoveThreadReady is only used by systhreadkill() function
//
// Changes:
// 05 / 12 / 2011 : Removing Threadwait, Errno, and other non-used code.
// 27 / 03 / 2011 : Renaming Exchange slot to MxSlots.
// 14 / 10 / 2009 : Bug Fixed in the Scheduler.
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
    ThreadID: TThreadID; // thread identifier
    Next: PThread; 	 // Next and Previous are independant of the thread created from the Parent
    Previous: PThread;   // and are used for the scheduling to scan all threads for a CPU
    IOScheduler: IOInfo;
    State: Byte;
    PrivateHeap: Pointer;
    FlagKill: boolean;
    // used by ThreadMain to pass argumments
    StartArg: Pointer;
    // thread main function
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
    ApicID: LongInt;
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
procedure Sleep(Miliseg: LongInt);
procedure SysEndThread(ExitCode: DWORD);
function SysResumeThread(ThreadID: TThreadID): DWORD;
function SysSuspendThread(ThreadID: TThreadID): DWORD;
function SysKillThread(ThreadID: TThreadID): DWORD;
procedure SysThreadSwitch;

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
  EXCEP_TERMINATION = -1 ; // code of termination for exception
  THREADVAR_BLOCKSIZE: DWORD = 0 ; // size of local variables storage for every thread

  
// private procedures 
procedure SystemExit; forward;
procedure Scheduling(Candidate: PThread); forward;
procedure ThreadExit(Schedule: Boolean); forward;
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
  ThreadExit(True);
end;

procedure ExceptDIVBYZERO; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: Division by zero', 0, 0, 0); {$ENDIF}
  PrintK_('Exception: /RDivision by zero/n\n',0);
  ExceptionHandler;
end;

procedure ExceptOVERFLOW; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: Overflow',  0, 0, 0); {$ENDIF}
  PrintK_('Exception: /ROverflow/n\n',0);
  ExceptionHandler;
end;

procedure ExceptBOUND; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: Bound instruction',  0, 0, 0); {$ENDIF}
  PrintK_('Exception: /RBound instruction/n\n',0);
  ExceptionHandler;
end;

procedure ExceptILLEGALINS; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: Illegal instruction',  0, 0, 0); {$ENDIF}
  PrintK_('Exception: /RIllegal instruction/n\n',0);
  ExceptionHandler;
end;

procedure ExceptDEVNOTAVA; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: Device not available',  0, 0, 0); {$ENDIF}
  PrintK_('Exception: /RDevice not available/n\n',0);
  ExceptionHandler;
end;

procedure ExceptDF; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: Double fault',  0, 0, 0); {$ENDIF}
  PrintK_('Exception: /RDouble Fault/n\n',0);
  ExceptionHandler
end;

procedure ExceptSTACKFAULT; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: Stack fault',  0, 0, 0); {$ENDIF}
  PrintK_('Exception: /RStack fault/n',0);
  ExceptionHandler
end;

procedure ExceptGENERALP; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: General protection',  0, 0, 0); {$ENDIF}
  PrintK_('Exception: /RGeneral protection/n\n',0);
  ExceptionHandler
end;

procedure ExceptPAGEFAULT; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: Page fault',  0, 0, 0); {$ENDIF}
  PrintK_('Exception: /RPage fault/n\n',0);
  ExceptionHandler
end;

procedure ExceptFPUE; {$IFDEF FPC} [nostackframe]; {$ENDIF}
begin
  {$IFDEF DebugProcess} DebugTrace('Exception: FPU error',  0, 0, 0); {$ENDIF}
  PrintK_('Exception: /RFPU error/n\n',0);
  ExceptionHandler
end;

// Exceptions are captured
procedure InitializeINT;
begin
  CaptureInt(EXC_DIVBYZERO, @ExceptDIVBYZERO);
  CaptureInt(EXC_OVERFLOW, @ExceptOVERFLOW);
  CaptureInt(EXC_BOUND, @ExceptBOUND);
  CaptureInt(EXC_ILLEGALINS, @ExceptILLEGALINS);
  CaptureInt(EXC_DEVNOTAVA, @ExceptDEVNOTAVA);
  CaptureInt(EXC_DF, @ExceptDF);
  CaptureInt(EXC_STACKFAULT, @ExceptSTACKFAULT);
  CaptureInt(EXC_GENERALP, @ExceptGENERALP);
  CaptureInt(EXC_PAGEFAUL, @ExceptPAGEFAULT);
  CaptureInt(EXC_FPUE, @ExceptFPUE);
end;

// Initialization of each Core in the system
procedure InitCores;
var
  I, J: LongInt;
begin
  PrintK_('Multicore Initialization ...\n',0);
  // cleaning all table
  for I := 0 to Max_CPU-1 do
  begin
    CPU[I].ApicID := 0 ;
    CPU[I].CurrentThread := nil;
    CPU[I].Threads :=nil;
    for J := 0 to Max_CPU-1 do
    begin
      CPU[I].ThreadsToBeDispatched[J] := nil;
      CpuMxSlots[I][J] := nil;
    end;
  end;
  if CPU_COUNT = 1 then
  begin // with one cpu we do not need any initialization proc.
    PrintK_('Core#0 ... /VOk\n/n',0);
    Exit;
  end;
  for I := 0 to CPU_COUNT-1 do
  begin
    if not Cores[I].CPUBoot and Cores[I].present then
    begin
      CPU[Cores[I].ApicID].ApicID := Cores[I].ApicID;
      Cores[I].InitProc := @Scheduling; 
      InitCore(Cores[I].ApicID); // initialize the CPU
      if Cores[I].InitConfirmation then
        PrintK_('Core#%d ... /VOk\n/n', Cores[I].ApicID)
      else
        PrintK_('Core#%d ... /RFault\n/n', Cores[I].ApicID);
    end else if Cores[I].CPUBoot then
      PrintK_('Core#0 ... /VOk\n/n',0);
  end;
end;

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


const
  // used only for the first thread to flag if initialized
  Initialized: Boolean = False; 

// Create a new thread
function ThreadCreate(const StackSize: SizeUInt; CPUID: DWORD; ThreadFunction: TThreadFunc; Arg: Pointer): PThread;
var
  NewThread: PThread;
  ip_ret: ^THandle;
begin
  NewThread := ToroGetMem(SizeOf(TThread));
  {$IFDEF DebugProcess} DebugTrace('ThreadCreate - NewThread: %h', PtrUInt(NewThread), 0, 0); {$ENDIF}
  if NewThread = nil then
  begin
    {$IFDEF DebugProcess} DebugTrace('ThreadCreate - NewThread = nil', 0, 0, 0); {$ENDIF}
    Result := nil;
    Exit;
  end;
  NewThread^.StackAddress := ToroGetMem(StackSize);
  if NewThread.StackAddress = nil  then
  begin
    {$IFDEF DebugProcess} DebugTrace('ThreadCreate - NewThread.StackAddress = nil', 0, 0, 0); {$ENDIF}
    ToroFreeMem(NewThread);
    Result := nil;
    Exit;
  end;
  // is this the first thread ?
  if not Initialized then
  begin
    {$IFDEF DebugProcess} DebugTrace('ThreadCreate - First Thread -> Initialized=True', 0, 0, 0); {$ENDIF}
    Initialized := True;
  end else if THREADVAR_BLOCKSIZE <> 0 then
  begin
    NewThread.TLS := ToroGetMem(THREADVAR_BLOCKSIZE) ;
    if NewThread.TLS = nil then
    begin // not enough memory, Thread cannot be created
      {$IFDEF DebugProcess} DebugTrace('ThreadCreate - NewThread.TLS = nil', 0, 0, 0); {$ENDIF}
      ToroFreeMem(NewThread.StackAddress);
      ToroFreeMem(NewThread);
      Result := nil;
      Exit;
    end;
  end;
  // stack initialization
  NewThread.StackSize := StackSize;
  NewThread.ret_thread_sp := Pointer(PtrUInt(NewThread.StackAddress) + StackSize-1);
  NewThread.sleep_rdtsc := 0;
  NewThread.FlagKill := false;
  NewThread.State := tsReady;
  NewThread.StartArg := Arg; // this argument we will read by thread main
  NewThread.ThreadFunc := ThreadFunction;
  {$IFDEF DebugProcess} DebugTrace('ThreadCreate - NewThread.ThreadFunc: %h', PtrUInt(@NewThread.ThreadFunc), 0, 0); {$ENDIF}
  NewThread.PrivateHeap := XHeapAcquire(CPUID); // private heap allocator init
  NewThread.ThreadID := TThreadID(NewThread);
  NewThread.CPU := @CPU[CPUID];
  // when executing ret_to_thread  this stack is pushed in esp register
  // when scheduling() returns (is a procedure!) return to this eip pointer
  // when thread is executed for first time thread_sp_register pointer to stack base (or end)
  ip_ret := NewThread.ret_thread_sp;
  Dec(ip_ret);
  // scheduler return
  ip_ret^ := PtrUInt(@ThreadMain);
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

// Sleep current thread for SleepTime .
procedure Sleep(Miliseg: LongInt);
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


// Kill current Thread and call to the scheduler if Schedule is true
procedure ThreadExit(Schedule: Boolean);
var
  CurrentThread, NextThread: PThread;
begin
  CurrentThread := GetCurrentThread ;
  // free memory allocated by PrivateHeap
  XHeapRelease(CurrentThread.PrivateHeap);
  // inform that the main thread is being killed
  if CurrentThread = PThread(InitialThreadID) then
   PrintK_('ThreadExit: /Rwarning/n killing MainThread\n',0);
  NextThread := CurrentThread.Next;
  // removing from scheduling queue
  RemoveThreadReady(CurrentThread);
  // free memory allocated by Parent thread
  // TODO: rice condition, leaving non local memory!
  if THREADVAR_BLOCKSIZE <> 0 then
    ToroFreeMem(CurrentThread.TLS);
  ToroFreeMem (CurrentThread.StackAddress);
  ToroFreeMem(CurrentThread);
  {$IFDEF DebugProcess} DebugTrace('ThreadExit - ThreadID: %h', CurrentThread.ThreadID, 0, 0); {$ENDIF}
  if Schedule then  
    // try to Schedule a new thread
    Scheduling(NextThread);
end;

// Kill the thread given by ThreadID
// It does not need parent dependency
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
  {$IFDEF DebugProcess} DebugTrace('SysKillThread - sending signal to Thread: %h in CPU: %d \n', ThreadID, Thread.CPU.ApicID,0); {$ENDIF}
  // setting the kill flag 
  Thread.FlagKill := true;
  Result := 0;
end;

// Suspend the thread given by ThreadID
// It does not need parent dependency
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
  if (Thread = nil) or (CurrentThread.ThreadID = ThreadID) then
  begin
    // suspending current thread
    CurrentThread.state := tsSuspended;
    // calling the scheduler
    SysThreadSwitch;
    {$IFDEF DebugProcess} DebugTrace('SuspendThread: Current Threads was Suspended',0,0,0); {$ENDIF}
  end 
  else begin
    // suspending the given thread
    Thread.State := tsSuspended;
  end;
  Result := 0;
end;

// Wake up the thread given by ThreadID 
// It does not need parent dependency
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
  // set the thread state as ready
  Thread.State := tsReady;
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
      {$IFDEF DebugProcess} DebugTrace('Scheduling: Jumping to Current Thread, StackPointer return: %h', PtrUInt(CurrentCPU.CurrentThread.ret_thread_sp), 0, 0); {$ENDIF}
      SwitchStack(nil, @CurrentCPU.CurrentThread.ret_thread_sp);
      // jump to thread execution
      Exit;
    end;  
    Emigrating(CurrentCPU); // enqueue newly created threads to others CPUs
    Inmigrating(CurrentCPU); // Import new threads to CurrentCPU.Threads
    CurrentThread := CurrentCPU.CurrentThread;
    if Candidate = nil then
      Candidate := CurrentThread.Next;
    repeat
      if Candidate.State = tsReady then
        Break
      else if (Candidate.State = tsIOPending) and not Candidate.IOScheduler.DeviceState^ then
      begin
        // the device has completed its operation -> Candidate thread is ready to continue its process
        Candidate.State:= tsReady;
				Break;
      end else begin
    	Candidate := Candidate.Next;
      end;
    until Candidate = CurrentThread;
    if Candidate.State <> tsReady then
      Continue;
    CurrentCPU.CurrentThread := Candidate;
    {$IFDEF DebugProcess}DebugTrace('Scheduling: Jumping to Current Thread , stack pointer: %h', PtrUInt(Candidate.ret_thread_sp), 0, 0);{$ENDIF}
    if Candidate = CurrentThread then
      Exit;
    SwitchStack(@CurrentThread.ret_thread_sp, @Candidate.ret_thread_sp);
    Break;
  end;
end;

// Controls the execution of thread flags
procedure Signaling;
begin
  if CPU[GetApicID].CurrentThread.FlagKill then
  begin
    {$IFDEF DebugProcess} DebugTrace('Signaling - killing CurrentThread', 0, 0, 0); {$ENDIF}
    ThreadExit(True);
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
  {$IFDEF DebugProcess} DebugTrace('SysAllocateThreadVars - TLS: %h Size: %d', PtrUInt(CPU[CpuID].CurrentThread.TLS), THREADVAR_BLOCKSIZE, 0); {$ENDIF}
end;

// called from Kernel.KernelStart
// All begins here, the user program is executed like the init thread, the init thread can create additional threads.
procedure CreateInitThread(ThreadFunction: TThreadFunc; const StackSize: SizeUInt);
var
  InitThread: PThread;
  LocalCPU: PCPU;
begin
  {$IFDEF DebugProcess} DebugTrace('CreateInitThread - StackSize: %d', 0, StackSize, 0); {$ENDIF}
  LocalCPU := @CPU[GetApicID];
  InitThread := ThreadCreate(StackSize, LocalCPU.ApicID, ThreadFunction, nil);
  if InitThread = nil then
  begin
    PrintK_('InitThread = nil\n', 0);
    hlt;
  end;
  LocalCPU.CurrentThread := InitThread;
  InitialThreadID := TThreadID(InitThread);
  PrintK_('User Application Initialization ... \n', 0);
  // only performed explicitely for initialization procedure
  {$IFDEF FPC} InitThreadVars(@SysRelocateThreadvar); {$ENDIF}
  // TODO: InitThreadVars for DELPHI
  {$IFDEF DebugProcess} DebugTrace('CreateInitThread - InitialThreadID: %h', InitialThreadID, 0, 0); {$ENDIF}
  // now we have in the stack ip pointer for ret instruction
  // TODO: when compiling with DCC, check that previous assertion is correct
  // TODO: when previous IFDEF is activated, check that DebugTrace is not messing
  InitThread.ret_thread_sp := Pointer(PtrUInt(InitThread.ret_thread_sp)+SizeOf(Pointer));
  {$IFDEF DebugProcess} DebugTrace('CreateInitThread - InitThread.ret_thread_sp: %h -> change_sp to execute ThreadMain with this stack address', PtrUInt(InitThread.ret_thread_sp), 0, 0); {$ENDIF}
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
begin
  CurrentThread := GetCurrentThread ;
  // open standard IO files, stack checking, iores, etc .
  {$IFDEF FPC} InitThread(CurrentThread.StackSize); {$ENDIF}
  // TODO: !!! InitThread() for Delphi
  {$IFDEF DebugProcess} DebugTrace('ThreadMain - CurrentThread: #%h', PtrUInt(CurrentThread), 0, 0); {$ENDIF}
  {$IFDEF DebugProcess} DebugTrace('ThreadMain - CurrentThread.ThreadFunc: %h', PtrUInt(@CurrentThread.ThreadFunc), 0, 0); {$ENDIF}
  ExitCode := CurrentThread.ThreadFunc(CurrentThread.StartArg);
  {$IFDEF DebugProcess} DebugTrace('ThreadMain - returning from CurrentThread.ThreadFunc CurrentThread: %h', PtrUInt(CurrentThread), 0, 0); {$ENDIF}
  if CurrentThread.ThreadID = InitialThreadID then
    SystemExit; // System is ending !
  ThreadExit(True);
end;

// Create new thread and return the thread id  , we do not need save context .
function SysBeginThread(SecurityAttributes: Pointer; StackSize: SizeUInt; ThreadFunction: TThreadFunc; Parameter: Pointer;
                         CPU: DWORD; var ThreadID: TThreadID): TThreadID;
var
  NewThread: PThread;
begin
  if (LongInt(CPU) = CPU_NIL) or (LongInt(CPU) > CPU_COUNT-1) then
    CPU := GetApicID; // invalid CpuID -> create thread on current CPU
  NewThread := ThreadCreate(StackSize, CPU, ThreadFunction, Parameter);
  if NewThread = nil then
  begin
    ThreadID := 0;
    {$IFDEF DebugProcess} DebugTrace('BeginThread - ThreadCreate Failed', 0, 0, 0); {$ENDIF}
    Result := 0;
    Exit;
  end;
  ThreadID := NewThread.ThreadID;
  {$IFDEF DebugProcess} DebugTrace('BeginThread - ThreadID: %h on CPU %d', NewThread.ThreadID, NewThread.CPU.ApicID, 0); {$ENDIF}
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
  ThreadExit(True);
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
  // functions to manipulate threads. Transparent for pascal programmers
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
    InitCriticalSection    := nil;
    DoneCriticalSection    := nil;
    EnterCriticalSection   := nil;
    LeaveCriticalSection   := nil;
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
    RTLEventWaitFor        := nil;
    RTLEventWaitForTimeout := nil;
  end;
  SetThreadManager(ToroThreadManager);
{$ENDIF}
end;

end.

