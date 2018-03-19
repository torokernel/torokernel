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
// 11 / 12 / 2011 : Fixing a critical issue on remote thread create.
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
// Copyright (c) 2003-2016 Matias Vara <matiasevara@gmail.com>
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
  PThreadCreateMsg = ^TThreadCreateMsg; 
  TMxSlot = Pointer;
  // MxSlots[SenderID][ReceiverID] can be assigned only if slot is empty (nil)
  TMxSlots = array[0..MAX_CPU-1, 0..MAX_CPU-1] of TMxSlot;

  // Mechanism to transfer data between CPU[SenderID] --> CPU[ReceiverID] without locking mechanism
  // There is 1 global matrix of message passing slots [CPU SenderID x CPU ReceiverID]
  // 1. a Thread to be dispatched on a remote CPU is queued in CurrentCPU.MsgsToBeDispatched[RemoteCpuID]
  // 2. Scheduling[CurrentCPU] set threads queue in CpuMxSlots[CurrentCpuID][RemoteCpuID] if empty (nil)
  // 3. Scheduling[RemoteCPU] ForEach CpuMxSlots[][RemoteCpuID] read slot and reset slot (if not empty)
  
  // Drivers fill this structure
  IOInfo = record
    DeviceState: ^boolean;
  end;

  TThreadFunc = function(Param: Pointer): PtrInt;
  TThread = record // in Toro a task is a Thread
    ThreadID: TThreadID; // thread identifier
    Next: PThread; 	 // Next and Previous are independant of the thread created from the Parent
    Previous: PThread;   // and are used for the scheduling to scan all threads for a CPU
    NextPollingThread: PThread; // next thread in polling queue
    Parent: PThread;
    IOScheduler: IOInfo;
    State: Byte;
    PrivateHeap: Pointer;
    FlagKill: boolean;
    // used for indicate a service thread
    IsService: boolean;
    // used by ThreadMain to pass argumments
    StartArg: Pointer;
    // thread main function
    ThreadFunc: TThreadFunc;
    TLS: Pointer;
    StackAddress: Pointer;
    StackSize: SizeUInt;
    ret_thread_sp: Pointer;
    sleep_rdtsc: Int64; // sleep counter
    IdleTime: Int64;
    IsPollThread: Boolean;
    // Interface between the threads with Network Sockets
    NetworkService: Pointer;
    CPU: PCPU; // CPU on which this thread is running
  end;

  // each CPU has this entry
  TCPU = record 
    ApicID: LongInt;
    Idle: Boolean;
    CurrentThread: PThread; // thread running in this moment  , in this CPU
    Threads: PThread; // this tail is use by scheduler
    PollingThreads: PThread;
    PollingThreadsTail: PThread;
    PollingThreadCount: LongInt;
    PollingThreadTotal: Longint;
    MsgsToBeDispatched: array[0..MAX_CPU-1] of PThreadCreateMsg;
  end;

  // Structure used by ThreadCreate in order to pass the arguments to create a remote thread
  TThreadCreateMsg = record
    StartArg: pointer;
    ThreadFunc: TThreadFunc;
    StackSize: SizeUInt;
    RemoteResult: Pointer; 
    Parent: PThread;
    CPU: PCPU;
    Next: PThreadCreateMsg;
  end;

  

const
  // Thread State
  tsIOPending = 5 ; // GetDevice and FreeDevice use this state
  tsReady = 2 ;
  tsSuspended = 1 ;
  tsZombie = 4 ;
  tsIdle = 6;
  
  
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
procedure SysThreadSwitch(const Idle: Boolean = False);
procedure ThreadExit(Schedule: Boolean);
procedure Panic(const cond: Boolean; const Format: AnsiString);
procedure SysThreadActive;

var
  CPU: array[0..MAX_CPU-1] of TCPU;
  CpuMxSlots: TMxSlots;

implementation

uses
  {$IFDEF DEBUG} Debug, {$ENDIF}
  Console, Memory, lnfodwrfToro;

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}
{$DEFINE GetRBP := asm mov rbp_reg, rbp;end;}
{$DEFINE StoreRBP := asm mov rbp, rbp_reg;end;}

const
  CPU_NIL: LongInt = -1; // cpu_emigrate register
  SPINLOCK_FREE = 3 ; // flags for spinlock
  SPINLOCK_BUSY = 4 ;
  EXCEP_TERMINATION = -1 ; // code of termination for exception
  THREADVAR_BLOCKSIZE: DWORD = 0 ; // size of local variables storage for every thread
  WAIT_IDLE_THREAD_MS = 200;
  
// private procedures 
procedure SystemExit; forward;
procedure Scheduling(Candidate: PThread); forward;
procedure ThreadMain; forward;

var
{$IFDEF FPC}
  ToroThreadManager: TThreadManager;
{$ENDIF}
  InitialThreadID: TThreadID;  // ThreadID of initial thread

//------------------------------------------------------------------------------
// Routines to capture all exceptions
//------------------------------------------------------------------------------

function get_caller_frame(framebp:pointer;addr:pointer=nil):pointer;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  get_caller_frame:=framebp;
  if assigned(framebp) then
    get_caller_frame:=PPointer(framebp)^;
end;

function get_caller_addr(framebp:pointer;addr:pointer=nil):pointer;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  get_caller_addr:=framebp;
  if assigned(framebp) then
    get_caller_addr:=PPointer(framebp)[1];
end;

procedure get_caller_stackinfo(var framebp : pointer; var addr : pointer);
var
  nextbp : pointer;
  nextaddr : pointer;
begin
  nextbp:=get_caller_frame(framebp,addr);
  nextaddr:=get_caller_addr(framebp,addr);
  framebp:=nextbp;
  addr:=nextaddr;
end;


procedure ExceptionHandler;
begin
  EnableInt;
  ThreadExit(True);
end;


procedure ExceptDIVBYZERO;
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: Qword;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 8
 mov rip_reg, rax
 mov rax, [rbx] + 24
 mov rflags_reg, rax
 mov rbp, rbp_reg
end;
  WriteConsoleF('[\t] CPU#%d Exception: /RDivision by zero/n\n',[GetApicid]);
  WriteConsoleF('Thread#%d registers:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
     WriteDebug('Exception: Division by zero\n',[]);
     WriteDebug('Thread dump:\n',[]);
     WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
     WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
     WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
     WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
  begin
       get_caller_stackinfo(pointer(rbp_reg), addr);
       PrintBackTraceStr(addr);
  end;
  ExceptionHandler;
end;

procedure ExceptOVERFLOW;
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: Qword;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 8
 mov rip_reg, rax
 mov rax, [rbx] + 24
 mov rflags_reg, rax
 mov rbp, rbp_reg
end;
  WriteConsoleF('[\t] CPU#%d Exception: /ROverflow/n\n',[GetApicid]);
  WriteConsoleF('Thread#%d registers dump:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
     WriteDebug('Exception: Overflow\n',[]);
     WriteDebug('Thread dump:\n',[]);
     WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
     WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
     WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
     WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
  begin
       get_caller_stackinfo(pointer(rbp_reg), addr);
       PrintBackTraceStr(addr);
  end;
  ExceptionHandler;
end;

procedure ExceptBOUND;
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: Qword;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 8
 mov rip_reg, rax
 mov rax, [rbx] + 24
 mov rflags_reg, rax
 mov rbp, rbp_reg
end;
  WriteConsoleF('[\t] CPU#%d Exception: /RBound instrucction/n\n',[GetApicid]);
  WriteConsoleF('Thread#%d registers dump:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
     WriteDebug('Exception: Bound instrucction\n',[]);
     WriteDebug('Thread dump:\n',[]);
     WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
     WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
     WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
     WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
  begin
       get_caller_stackinfo(pointer(rbp_reg), addr);
       PrintBackTraceStr(addr);
  end;
  ExceptionHandler;
end;


procedure ExceptILLEGALINS;
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: Qword;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 8
 mov rip_reg, rax
 mov rax, [rbx] + 24
 mov rflags_reg, rax
 mov rbp, rbp_reg
end;
  WriteConsoleF('[\t] CPU#%d Exception: /RIllegal instrucction/n\n',[GetApicid]);
  WriteConsoleF('Thread#%d registers dump:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
     WriteDebug('Exception: Illegal instrucction\n',[]);
     WriteDebug('Thread dump:\n',[]);
     WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
     WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
     WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
     WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
  begin
       get_caller_stackinfo(pointer(rbp_reg), addr);
       PrintBackTraceStr(addr);
  end;
  ExceptionHandler;
end;

procedure ExceptDEVNOTAVA; 
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: Qword;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 8
 mov rip_reg, rax
 mov rax, [rbx] + 24
 mov rflags_reg, rax
 mov rbp, rbp_reg
end;
  WriteConsoleF('[\t] CPU#%d Exception: /RDevice not available/n\n',[GetApicid]);
  WriteConsoleF('Thread#%d registers dump:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
     WriteDebug('Exception: Device not available\n',[]);
     WriteDebug('Thread dump:\n',[]);
     WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
     WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
     WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
     WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
  begin
       get_caller_stackinfo(pointer(rbp_reg), addr);
       PrintBackTraceStr(addr);
  end;
  ExceptionHandler;
end;

procedure ExceptDF; 
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: Qword;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 8
 mov rip_reg, rax
 mov rax, [rbx] + 24
 mov rflags_reg, rax
 mov rbp, rbp_reg
end;
  WriteConsoleF('[\t] CPU#%d Exception: /RDouble fault/n\n',[GetApicid]);
  WriteConsoleF('Thread#%d registers dump:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
     WriteDebug('Exception: Double fault\n',[]);
     WriteDebug('Thread dump:\n',[]);
     WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
     WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
     WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
     WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
  begin
       get_caller_stackinfo(pointer(rbp_reg), addr);
       PrintBackTraceStr(addr);
  end;
  ExceptionHandler;
end;

procedure ExceptSTACKFAULT;
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: Qword;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 8
 mov rip_reg, rax
 mov rax, [rbx] + 24
 mov rflags_reg, rax
 mov rbp, rbp_reg
end;
  WriteConsoleF('[\t] CPU#%d Exception: /RStack fault/n\n',[GetApicid]);
  WriteConsoleF('Thread#%d registers dump:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
     WriteDebug('Exception: Stack fault\n',[]);
     WriteDebug('Thread dump:\n',[]);
     WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
     WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
     WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
     WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
  begin
       get_caller_stackinfo(pointer(rbp_reg), addr);
       PrintBackTraceStr(addr);
  end;
  ExceptionHandler;
end;

procedure ExceptGENERALP;
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: Qword;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 16
 mov rip_reg, rax
 mov rax, [rbx] + 32
 mov rflags_reg, rax
 mov rbp, rbp_reg
end;
  WriteConsoleF('[\t] CPU#%d Exception: /RGeneral protection fault/n\n',[GetApicid]);
  WriteConsoleF('Thread#%d registers dump:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
     WriteDebug('Exception: General protection fault\n',[]);
     WriteDebug('Thread dump:\n',[]);
     WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
     WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
     WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$ENDIF}
  // FIXME: check if rip_reg is valid
  if (rip_reg <> 0) then
  begin
    WriteConsoleF('Backtrace:\n',[]);
    {$IFDEF DebugCrash}
     WriteDebug('Backtrace:\n',[]);
    {$ENDIF}
    PrintBackTraceStr(pointer(rip_reg));
    get_caller_stackinfo(pointer(rbp_reg), addr);
    while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
    begin
     get_caller_stackinfo(pointer(rbp_reg), addr);
     PrintBackTraceStr(addr);
    end;
  end;
  ExceptionHandler;
end;


procedure ExceptPAGEFAULT;
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: QWord;
    rcr2: QWord;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 16
 mov rip_reg, rax
 mov rax, [rbx] + 32
 mov rflags_reg, rax
 mov rbp, rbp_reg
 mov rax, cr2
 mov rcr2, rax
end;
  WriteConsoleF('[\t] CPU#%d Exception: /RPage Fault/n, cr2: %h\n',[GetApicid, rcr2]);
  WriteConsoleF('Dumping ThreadID: %d\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
 {$IFDEF DebugCrash}
   WriteDebug('Exception: Page Fault, cr2: %h\n',[rcr2]);
   WriteDebug('Thread dump:\n',[]);
   WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
   WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
   WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
   WriteDebug('Backtrace:\n',[]);
 {$ENDIF}
 WriteConsoleF('Backtrace:\n',[]);
 PrintBackTraceStr(pointer(rip_reg));
 get_caller_stackinfo(pointer(rbp_reg), addr);
 while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
 begin
     get_caller_stackinfo(pointer(rbp_reg), addr);
     PrintBackTraceStr(addr);
 end;
 ExceptionHandler;
end;

procedure ExceptFPUE;
var rbx_reg: QWord;
    rcx_reg: QWord;
    rax_reg: QWord;
    rdx_reg: QWord;
    rsp_reg: QWord;
    rip_reg: QWord;
    rbp_reg: QWord;
    errc_reg: QWord;
    rflags_reg: Qword;
    addr: pointer;
begin
 errc_reg := 0;
asm
 mov  rbx_reg, rbx
 mov  rcx_reg, rcx
 mov  rax_reg, rax
 mov  rdx_reg, rdx
 mov  rsp_reg, rsp
 mov  rbp_reg, rbp
 mov rbx, rbp
 mov rax, [rbx] + 8
 mov rip_reg, rax
 mov rax, [rbx] + 24
 mov rflags_reg, rax
 mov rbp, rbp_reg
end;
  WriteConsoleF('[\t] CPU#%d Exception: /RFPU error/n\n',[GetApicid]);
  WriteConsoleF('Thread#%d registers dump:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
     WriteDebug('Exception: FPU error\n',[]);
     WriteDebug('Thread#%d registers dump:\n',[CPU[GetApicid].CurrentThread.ThreadID]);
     WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
     WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
     WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
     WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  while (rbp_reg < (PtrUInt(CPU[GetApicid].CurrentThread.ret_thread_sp))) do
  begin
       get_caller_stackinfo(pointer(rbp_reg), addr);
       PrintBackTraceStr(addr);
  end;
  ExceptionHandler;
end;


procedure InitializeExceptions;
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
  Attemps: Longint;
begin
  WriteConsoleF('Multicore Initialization ...\n',[]);
  // cleaning all table
  for I := 0 to Max_CPU-1 do
  begin
    CPU[I].ApicID := 0 ;
    CPU[I].CurrentThread := nil;
    CPU[I].Threads := nil;
    CPU[I].Idle:= False;
    CPU[I].PollingThreads := nil;
    CPU[I].PollingThreadsTail := nil;
    CPU[I].PollingThreadCount:= 0;
    CPU[I].PollingThreadTotal:= 0;
    for J := 0 to Max_CPU-1 do
    begin
      CPU[I].MsgsToBeDispatched[J] := nil;
      CpuMxSlots[I][J] := nil;
    end;
  end;
  if CPU_COUNT = 1 then
  begin // with one cpu we do not need any initialization proc.
    WriteConsoleF('Core#0 ... /VRunning\n/n',[]);
    Exit;
  end;
  for I := 0 to CPU_COUNT-1 do
  begin
    if not Cores[I].CPUBoot and Cores[I].present then
    begin
      CPU[Cores[I].ApicID].ApicID := Cores[I].ApicID;
      Cores[I].InitProc := @Scheduling;
      // try to initialize the CPU twice
      for Attemps:= 0 to 1 do
      begin
        If not InitCore(Cores[I].ApicID) then
        begin
          WriteConsoleF('Core#%d ... /RHardware Issue\n/n', [Cores[I].ApicID]);
          break;
        end;
        If Cores[I].InitConfirmation then
         break;
      end;
      if Cores[I].InitConfirmation then
        WriteConsoleF('Core#%d ... /VUp\n/n', [Cores[I].ApicID])
      else
        WriteConsoleF('Core#%d ... /RDown\n/n', [Cores[I].ApicID]);
    end else if Cores[I].CPUBoot then
      WriteConsoleF('Core#0 ... /VUp\n/n',[]);
  end;
end;

//------------------------------------------------------------------------------
// Threads list management
//------------------------------------------------------------------------------


// reset idle counter
procedure SysThreadActive;
var
 T: PThread;
begin
  T := GetCurrentThread;
  if (T.State = tsIdle) then
  begin
    T.IdleTime := 0;
    T.State := tsReady;
    T.CPU.PollingThreadCount -=1 ;
  end;
end;

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

// Enqueue a New Msg to emigrate array
procedure AddThreadMsg(Msg: PThreadCreateMsg);
var
  ApicID: LongInt;
  FirstMsg: PThreadCreateMsg;
  CurrentCPU: PCPU;
begin
  CurrentCPU := @CPU[GetApicID];
  ApicID := Msg.CPU.ApicID;
  FirstMsg := CurrentCPU.MsgsToBeDispatched[ApicID];
  Msg.Next := FirstMsg;
  CurrentCPU.MsgsToBeDispatched[ApicID] := Msg;
  // wake up cpu
  if CPU[ApicID].Idle then
     send_apic_int(ApicID, INTER_CORE_IRQ);
end;

// Returns current Thread pointer running on this CPU
function GetCurrentThread: PThread; 
begin
  Result := CPU[GetApicID].CurrentThread;
end;


const
  // Used only by CreateInitThread when the first thread is created
  Initialized: Boolean = False; 

// Create a new thread
function ThreadCreate(const StackSize: SizeUInt; CPUID: DWORD; ThreadFunction: TThreadFunc; Arg: Pointer): PThread;
var
  NewThread, Current: PThread;
  NewThreadMsg: TThreadCreateMsg; 
  ip_ret: ^THandle;
begin
  // creating a local thread
  if CPUID = GetApicID then
  begin
    NewThread := ToroGetMem(SizeOf(TThread));
    {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread: %h\n', [PtrUInt(NewThread)]); {$ENDIF}
    if NewThread = nil then
    begin
      {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread = nil\n', []); {$ENDIF}
      Result := nil;
      Exit;
    end;
    NewThread^.StackAddress := ToroGetMem(StackSize);
    if NewThread.StackAddress = nil  then
    begin
      {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread.StackAddress = nil\n',[]); {$ENDIF}
      ToroFreeMem(NewThread);
      Result := nil;
      Exit;
    end;
    // is this the first thread ?
    if not Initialized then
    begin
      {$IFDEF DebugProcess} WriteDebug('ThreadCreate: First Thread -> Initialized=True\n', []); {$ENDIF}
      Initialized := True;
    end else if THREADVAR_BLOCKSIZE <> 0 then
    begin
      NewThread.TLS := ToroGetMem(THREADVAR_BLOCKSIZE) ;
      if NewThread.TLS = nil then
      begin // not enough memory, Thread cannot be created
        {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread.TLS = nil\n', []); {$ENDIF}
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
    NewThread.FlagKill := False;
    NewThread.State := tsReady;
    NewThread.StartArg := Arg; // this argument we will read by thread main
    NewThread.ThreadFunc := ThreadFunction;
    {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread.ThreadFunc: %h\n', [PtrUInt(@NewThread.ThreadFunc)]); {$ENDIF}
    NewThread.PrivateHeap := XHeapAcquire(CPUID); // private heap allocator init
    NewThread.ThreadID := TThreadID(NewThread);
    NewThread.CPU := @CPU[CPUID];
    NewThread.Parent :=  GetCurrentThread;
    NewThread.IsPollThread := False;
    NewThread.NextPollingThread:= nil;
    NewThread.IdleTime:= 0;
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
    // enqueu the new thread in the local tail
    AddThreadReady(NewThread);
    Result := NewThread
  end else begin 
    // We have to send a msg to the remote core using the CpuMxSlot
    NewThreadMsg.StackSize := StackSize;
    NewThreadMsg.StartArg := Arg; 
    NewThreadMsg.ThreadFunc := ThreadFunction;
    NewThreadMsg.CPU := @CPU[CPUID];
    Current := GetCurrentThread;
    NewThreadMsg.Parent := Current; 
    NewThreadMsg.Next := nil;
    // the msg in enqueue to be emigrated
    AddThreadMsg(@NewThreadMsg);
    // parent thread will sleep
    Current.State := tsSuspended;
    // calling the scheduler
    SysThreadSwitch;
    // we come back
    Result := NewThreadMsg.RemoteResult;
  end;   
end;

// Sleep current thread for SleepTime .
procedure Sleep(Miliseg: LongInt);
var
  ResumeTime: Int64;
begin
  ResumeTime := read_rdtsc + Miliseg*LocalCPUSpeed*1000;
  {$IFDEF DebugProcess} WriteDebug('Sleep: ResumeTime: %d\n', [ResumeTime]); {$ENDIF}
  while ResumeTime > read_rdtsc do
  begin
     Scheduling(nil);
  end;
  {$IFDEF DebugProcess} WriteDebug('Sleep: ResumeTime exiting\n', []); {$ENDIF}
end;


// Kill current Thread and call to the scheduler if Schedule is True
procedure ThreadExit(Schedule: Boolean);
var
  CurrentThread, NextThread: PThread;
begin
  CurrentThread := GetCurrentThread ;
  // free memory allocated by PrivateHeap
  XHeapRelease(CurrentThread.PrivateHeap);
  // inform that the main thread is being killed
  if CurrentThread = PThread(InitialThreadID) then
  begin
   WriteConsoleF('ThreadExit: /RWarning!/n MainThread has been killed\n',[]);
   {$IFDEF DebugCrash}
    WriteDebug('ThreadExit: Warning! MainThread has been killed',[]);
   {$ENDIF}
  end;
  NextThread := CurrentThread.Next;
  // removing from scheduling queue
  RemoveThreadReady(CurrentThread);
  // free memory allocated by Parent thread
  if THREADVAR_BLOCKSIZE <> 0 then
    ToroFreeMem(CurrentThread.TLS);
  ToroFreeMem (CurrentThread.StackAddress);
  ToroFreeMem(CurrentThread);
  {$IFDEF DebugProcess} WriteDebug('ThreadExit: ThreadID: %h\n', [CurrentThread.ThreadID]); {$ENDIF}
  if Schedule then  
    // try to Schedule a new thread
    Scheduling(NextThread);
end;

// Kill the thread given by ThreadID
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
  {$IFDEF DebugProcess} WriteDebug('SysKillThread - sending signal to Thread: %h in CPU: %d \n', [ThreadID, Thread.CPU.ApicID]); {$ENDIF}
  // setting the kill flag 
  Thread.FlagKill := True;
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
    {$IFDEF DebugProcess} WriteDebug('SuspendThread: Current Threads was Suspended\n',[]); {$ENDIF}
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

// Import on CurrentCPU pending threads from foreign CPUs
procedure Inmigrating(CurrentCPU: PCPU);
var
  RemoteCpuID: LongInt;
  RemoteMsgs: PThreadCreateMsg; // tail to threads in emigrate array
begin
  for RemoteCpuID := 0 to CPU_COUNT-1 do
  begin
    if CpuMxSlots[CurrentCPU.ApicID][RemoteCpuID] <> nil then
    begin
      RemoteMsgs := CpuMxSlots[CurrentCPU.ApicID][RemoteCpuID];
      While RemoteMsgs <> nil do 
      begin
       // we invoke TreadCreate() with remote parameters
       RemoteMsgs.RemoteResult := ThreadCreate(RemoteMsgs.StackSize, CurrentCPU.ApicID, RemoteMsgs.ThreadFunc, RemoteMsgs.StartArg);
       // wake up the parent
       RemoteMsgs.Parent.state := tsReady;
       // wake up cpu if it is idle
       if CPU[RemoteCpuID].Idle then
       begin
          send_apic_int(RemoteCpuID, INTER_CORE_IRQ);
       // check two times if cpu is idle
       end else
       begin
           Delay(100);
           if CPU[RemoteCpuID].Idle then
             send_apic_int(RemoteCpuID, INTER_CORE_IRQ);
       end;
       RemoteMsgs := RemoteMsgs.Next;
      end;      
      CpuMxSlots[CurrentCPU.ApicID][RemoteCpuID] := nil;
      {$IFDEF DebugProcessInmigrating}WriteDebug('Inmigrating - from CPU %d to LocalCPU %d\n', [RemoteCpuID, CurrentCPU.ApicID]);{$ENDIF}
    end;
  end;
end;

// Move pending msg to remote CPUs waiting list
procedure Emigrating(CurrentCPU: PCPU);
var
  RemoteCpuID: LongInt;
begin
  for RemoteCpuID := 0 to CPU_COUNT-1 do
  begin
    if (CurrentCPU.MsgsToBeDispatched[RemoteCpuID] <> nil) and (CpuMxSlots[RemoteCpuID][CurrentCPU.ApicID] = nil) then
    begin
      CpuMxSlots[RemoteCpuID][CurrentCPU.ApicID] := CurrentCPU.MsgsToBeDispatched[RemoteCpuID];
      CurrentCPU.MsgsToBeDispatched[RemoteCpuID]:= nil;
      // wake up cpu
      if CPU[RemoteCpuID].Idle then
         send_apic_int(RemoteCpuID, INTER_CORE_IRQ);
      {$IFDEF DebugProcessEmigrating} WriteDebug('Emigrating - Switch Threads of DispatchArray[%d] to EmigrateArray[%d]\n', [CurrentCPU.ApicID, RemoteCpuID]); {$ENDIF}
    end;
  end;
end;

// Schedule next thread, the current thread must be added in the appropriate list (CPU[].MsgsToBeDispatched) and have saved its registers
procedure Scheduling(Candidate: PThread); {$IFDEF FPC} [public , alias :'scheduling']; {$ENDIF}
var
  CurrentCPU: PCPU;
  CurrentThread, Th: PThread;
  NextTurnHalt: Boolean;
  rbp_reg: pointer;
begin
  NextTurnHalt:= False;
  CurrentCPU := @CPU[GetApicID];
  while True do
  begin
    // go to save-power state if queue is empty
    if CurrentCPU.Threads = nil then
    begin
      {$IFDEF DebugProcess} WriteDebug('Scheduling: scheduler goes to inmigration loop\n', []); {$ENDIF}
      while CurrentCPU.Threads = nil do
      begin
        CurrentCPU.Idle := True;
        hlt;
        CurrentCPU.Idle := False;
        Inmigrating(CurrentCPU);
      end;
      CurrentCPU.CurrentThread := CurrentCPU.Threads;
      {$IFDEF DebugProcess} WriteDebug('Scheduling: current thread, stack: %h\n', [PtrUInt(CurrentCPU.CurrentThread.ret_thread_sp)]); {$ENDIF}
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
    {$IFDEF DebugProcess} WriteDebug('Scheduling: Candidate %h, state: %d\n', [PtrUInt(Candidate), Candidate.State]); {$ENDIF}
      if Candidate.State = tsReady then
        Break
      else if (Candidate.State = tsIdle) and (CurrentCPU.PollingThreadCount <> CurrentCPU.PollingThreadTotal) then
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

    {$IFDEF DebugProcess} WriteDebug('Scheduling: Candidate state: %d, PollingThreadCount: %d, PollingThreadTotal: %d\n', [Candidate.state, CurrentCPU.PollingThreadCount, CurrentCPU.PollingThreadTotal]); {$ENDIF}

    if (Candidate.State = tsIdle) and (CurrentCPU.PollingThreadCount <> CurrentCPU.PollingThreadTotal) then
      // do thing in this case
    else
    begin
    if (Candidate.State <> tsReady) then
    begin
      // is the whole system in polling mode?
      if (CurrentCPU.PollingThreadCount = CurrentCPU.PollingThreadTotal) and (CurrentCPU.PollingThreadCount <> 0) then
      begin
        {$IFDEF DebugProcess} WriteDebug('Scheduling: whole system in poll, sleeping\n', []); {$ENDIF}
        CurrentCPU.Idle := True;
        hlt;
        CurrentCPU.Idle := False;
        {$IFDEF DebugProcess} WriteDebug('Scheduling: waking up from poll mode\n', []); {$ENDIF}
        // when we wake up, we set all polling threads in ready state
        Th := CurrentCPU.PollingThreads;
        while Th <> nil do
        begin
         Th.State := tsReady;
         Th.IdleTime := 0;
         Dec(CurrentCPU.PollingThreadCount);
         Th := th.NextPollingThread;
        end;
        Continue;
      end;
      // halt the core when there is no ready thread
      // we do two turns before halt it
      if NextTurnHalt then
      begin
        CurrentCPU.Idle := True;
        hlt;
        CurrentCPU.Idle := False;
        NextTurnHalt:= False;
      end else
      begin
         DelayMicro(50);
         NextTurnHalt:= True;
      end;
      Continue;
    end;
    end;
    NextTurnHalt:= False;
    CurrentCPU.CurrentThread := Candidate;
    {$IFDEF DebugProcess} WriteDebug('Scheduling: thread %h, state: %d, stack: %h\n', [PtrUInt(Candidate),Candidate.State,PtrUInt(Candidate.ret_thread_sp)]); {$ENDIF}
    if Candidate = CurrentThread then
      Exit;
    // switch stack frame
    GetRBP;
    CurrentThread.ret_thread_sp := rbp_reg;
    rbp_reg := Candidate.ret_thread_sp;
    StoreRBP;
    Break;
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
  {$IFDEF DebugProcess} WriteDebug('SysAllocateThreadVars - TLS: %h Size: %d\n', [PtrUInt(CPU[CpuID].CurrentThread.TLS), THREADVAR_BLOCKSIZE]); {$ENDIF}
end;

// called from Kernel.KernelStart
// All begins here, the user program is executed like the init thread, the init thread can create additional threads.
procedure CreateInitThread(ThreadFunction: TThreadFunc; const StackSize: SizeUInt);
var
  InitThread: PThread;
  LocalCPU: PCPU;
begin
  {$IFDEF DebugProcess} WriteDebug('CreateInitThread: StackSize: %d\n', [StackSize]); {$ENDIF}
  LocalCPU := @CPU[GetApicID];
  InitThread := ThreadCreate(StackSize, LocalCPU.ApicID, ThreadFunction, nil);
  if InitThread = nil then
  begin
    WriteConsoleF('InitThread = nil\n', []);
    hlt;
  end;
  LocalCPU.CurrentThread := InitThread;
  InitialThreadID := TThreadID(InitThread);
  WriteConsoleF('Starting MainThread: /V%d/n\n', [InitialThreadID]);
  // only performed explicitely for initialization procedure
  {$IFDEF FPC} InitThreadVars(@SysRelocateThreadvar); {$ENDIF}
  // TODO: InitThreadVars for DELPHI
  {$IFDEF DebugProcess} WriteDebug('CreateInitThread: InitialThreadID: %h\n', [InitialThreadID]); {$ENDIF}
  // now we have in the stack ip pointer for ret instruction
  // TODO: when compiling with DCC, check that previous assertion is correct
  // TODO: when previous IFDEF is activated, check that WriteDebug is not messing
  InitThread.ret_thread_sp := Pointer(PtrUInt(InitThread.ret_thread_sp)+SizeOf(Pointer));
  {$IFDEF DebugProcess} WriteDebug('CreateInitThread: InitThread.ret_thread_sp: %h\n', [PtrUInt(InitThread.ret_thread_sp)]); {$ENDIF}
  change_sp(InitThread.ret_thread_sp);
  // the procedure "PASCALMAIN" is executed (this is the ThreadFunction in parameter)
end;

// The current thread is remaining in tq_ready tail and the next thread is scheduled
procedure SysThreadSwitch(const Idle: Boolean = False);
var
 idletime: Int64;
 tmp: PCPU;
 Thread: PThread;
begin
  // thread is idle
  if Idle then
  begin
     {$IFDEF DebugProcess} WriteDebug('SysThreadSwitch: Idle = True\n', []); {$ENDIF}
     // the thread is enqueue first time
     if not GetCurrentThread.IsPollThread then
     begin
      {$IFDEF DebugProcess} WriteDebug('SysThreadSwitch: IsPollThread = True\n', []); {$ENDIF}
      Thread := GetCurrentThread;
      tmp := Thread.CPU;
      Thread.IsPollThread:= True;
      Inc(tmp.PollingThreadTotal);
      if tmp.PollingThreads = nil then
      begin
       tmp.PollingThreads := Thread;
       tmp.PollingThreadsTail:= Thread;
      end else begin
       tmp.PollingThreadsTail.NextPollingThread := Thread;
       tmp.PollingThreadsTail := Thread;
      end;
     end;
     idletime := GetCurrentThread.IdleTime;
     if (idletime = 0) then
     begin
       GetCurrentThread.IdleTime := read_rdtsc;
       {$IFDEF DebugProcess} WriteDebug('SysThreadSwitch: setting GetCurrentThread.IdleTime = %d\n', [read_rdtsc]); {$ENDIF}
     end else
     begin
       // it waits 200ms to set the thread in idle
       if (read_rdtsc - idletime) > (LocalCpuSpeed * 1000)*WAIT_IDLE_THREAD_MS then
       begin
          if GetCurrentThread.State <> tsIdle then
          begin
           GetCurrentThread.State := tsIdle;
           Inc(GetCurrentThread.CPU.PollingThreadCount);
           {$IFDEF DebugProcess} WriteDebug('SysThreadSwitch: thread in idle state\n', []); {$ENDIF}
          end;
        end;
     end;
  end else
  begin
   {$IFDEF DebugProcess} WriteDebug('SysThreadSwitch: thread is active\n', []); {$ENDIF}
   SysThreadActive;
  end;
  Scheduling(nil);
  // checking kill flag
  if CPU[GetApicID].CurrentThread.FlagKill then
  begin
    {$IFDEF DebugProcess} WriteDebug('Signaling - killing CurrentThread\n', []); {$ENDIF}
    ThreadExit(True);
  end;
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
  {$IFDEF DebugProcess} WriteDebug('ThreadMain: CurrentThread: #%h\n', [PtrUInt(CurrentThread)]); {$ENDIF}
  {$IFDEF DebugProcess} WriteDebug('ThreadMain: CurrentThread.ThreadFunc: %h\n', [PtrUInt(@CurrentThread.ThreadFunc)]); {$ENDIF}
  ExitCode := CurrentThread.ThreadFunc(CurrentThread.StartArg);
  {$IFDEF DebugProcess} WriteDebug('ThreadMain: returning from CurrentThread.ThreadFunc CurrentThread: %h\n', [PtrUInt(CurrentThread)]); {$ENDIF}
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
  if (LongInt(CPU) = CPU_NIL) then
    CPU := GetApicID
  // invalid CPU argument, we return with error
  else if ((LongInt(CPU) > CPU_COUNT-1) or (not Cores[Longint(CPU)].InitConfirmation)) then  
  begin
    ThreadID := 0;
    Result := 0;
    Exit;
  end;
  NewThread := ThreadCreate(StackSize, CPU, ThreadFunction, Parameter);
  if NewThread = nil then
  begin
    ThreadID := 0;
    {$IFDEF DebugProcess} WriteDebug('SysBeginThread: ThreadCreate Failed\n', []); {$ENDIF}
    Result := 0;
    Exit;
  end;
  ThreadID := NewThread.ThreadID;
  {$IFDEF DebugProcess} WriteDebug('SysBeginThread: ThreadID: %h on CPU %d\n', [NewThread.ThreadID, NewThread.CPU.ApicID]); {$ENDIF}
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
  {$IFDEF DebugProcess} WriteDebug('SystemExit\n', []); {$ENDIF}
  WriteConsoleF('\nSystem Termination, please turn off or reboot\n', []);
  {$IFDEF DebugProcess} WriteDebug('SystemExit - Debug end -> hlt\n', []); {$ENDIF}
  hlt;
end;

// A Panic condition has been reached, stops core execution
// TODO: add parameters
procedure Panic(const cond: Boolean; const Format: AnsiString);
var
 rbp_reg: QWord;
 addr: pointer;
begin
  if not cond then exit;
  DisableInt;
  WriteConsoleF('/RPanic/n:\n',[]);
  WriteConsoleF(Format,[]);
  {$IFDEF DebugProcess} WriteDebug('Panic: ', []); WriteDebug(Format, []); {$ENDIF}
  {$IFDEF DebugCrash}
  WriteConsoleF('Backtrace:\n',[]);
  // FIXME: Print the whole stack
  GetRBP;
  get_caller_stackinfo(pointer(rbp_reg), addr);
  PrintBackTraceStr(addr);
  get_caller_stackinfo(pointer(rbp_reg), addr);
  PrintBackTraceStr(addr);
  {$ENDIF}
  while true do;
end;

// Initialize all local structures and send the INIT IPI to all cpus  
procedure ProcessInit;
begin  
  // do Panic() if we can't calculate LocalCpuSpeed
  Panic(LocalCpuSpeed = 0,'LocalCpuSpeed = 0\n');
  {$IFDEF DebugProcess}
  	if (LocalCpuSpeed = MAX_CPU_SPEED_MHZ) then
  	begin
           WriteDebug('ProcessInit: warning LocalCpuSpeed=MAX_CPU_SPEED_MHZ',[]);
  	end;
  {$ENDIF}
  // initialize the exception and irq
  if HasException then
    InitializeExceptions;
  InitCores;
  {$IFDEF DEBUG}
     WriteDebug('ProcessInit: LocalCpuSpeed: %d Mhz, Cores: %d\n', [LocalCpuSpeed, CPU_COUNT]);
  {$ENDIF}
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

