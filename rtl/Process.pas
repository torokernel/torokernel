//
// Process.pas
//
// This unit contains the Scheduler and the Interruption Manager.
// It also does the SMP initialization and contains the API for thread manipulation.
//
// Copyright (c) 2003-2020 Matias Vara <matiasevara@gmail.com>
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

{$I Toro.inc}

interface

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, SysUtils;

type
  PThread = ^TThread;
  PCPU = ^TPerCPU;
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
  TThread = record
    ThreadID: TThreadID;
    Next: PThread;
    Previous: PThread;
    Parent: PThread;
    IOScheduler: IOInfo;
    State: Byte;
    PrivateHeap: Pointer;
    FlagKill: boolean;
    IsService: boolean;
    StartArg: Pointer;
    ThreadFunc: TThreadFunc;
    TLS: Pointer;
    StackAddress: Pointer;
    StackSize: SizeUInt;
    ret_thread_sp: Pointer;
    sleep_rdtsc: Int64;
    NetworkService: Pointer;
    CPU: PCPU;
  end;

  // PerCPU variables require to be padded to CACHELINE_LEN
  TPerCPU = record
    ApicID: LongInt;
    pad: LongInt;
    CurrentThread: PThread;
    Threads: PThread;
    LastIRQ: QWORD;
    pad1: array[1..CACHELINE_LEN-4] of QWORD;
    MsgsToBeDispatched: array[0..MAX_CPU-1] of PThreadCreateMsg;
  end;

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
procedure ThreadExit(Schedule: Boolean);
procedure Panic(const cond: Boolean; const Format: PChar; const Args: array of PtrUInt);
procedure UpdateLastIrq;
procedure SysSetCoreIdle;
function GetCPU: PCPU; inline;

{$push}
{$codealign varmin=64}
var
  CPU: array[0..MAX_CPU-1] of TPerCPU;
{$pop}

var
  CpuMxSlots: TMxSlots;
  ShutdownProcedure: procedure;

implementation

uses
  Console, Memory, lnfodwrfToro;

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}
{$DEFINE GetRBP := asm mov rbp_reg, rbp;end;}
{$DEFINE StoreRBP := asm mov rbp, rbp_reg;end;}
// only save/restore nonvolatile registers
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

const
  CPU_NIL: LongInt = -1;
  SPINLOCK_FREE = 3;
  SPINLOCK_BUSY = 4;
  EXCEP_TERMINATION = -1;
  THREADVAR_BLOCKSIZE: DWORD = 0;
  // this value should be longer than any timer
  WAIT_IDLE_CORE_MS = 2000;
  PERCPUCURRENTHREAD = 1;
  PERCPUCURRENTCPU = 2;

procedure SystemExit; forward;
procedure Scheduling(Candidate: PThread); forward;
procedure ThreadMain; forward;

var
{$IFDEF FPC}
  ToroThreadManager: TThreadManager;
{$ENDIF}
  InitialThreadID: TThreadID;

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

procedure UpdateLastIrq;
begin
  GetCPU.LastIrq := read_rdtsc;
end;

type
  EDivException = class(Exception);

procedure ExceptDIVBYZERO;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: Division by zero\n',[GetCoreId]);
  WriteConsoleF('Thread#%d registers:\n',[GetCurrentThread.ThreadID]);
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
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise EDivException.Create ('Division by Zero');
end;

// NMI handler just triggers the shutting down procedure
procedure ExceptNMI;
begin
  if @ShutdownProcedure <> nil then
    ShutdownProcedure;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  {$IFDEF ShutdownWhenFinished}
    ShutdownInQemu;
  {$ELSE}
    hlt;
  {$ENDIF}
end;

type
  EOverflowException = class(Exception);

procedure ExceptOVERFLOW;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: Overflow\n',[GetCoreId]);
  WriteConsoleF('Thread#%d registers dump:\n',[GetCurrentThread.ThreadID]);
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
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise EOverflowException.Create ('OverFlow');
end;

type
  EBoundException = class(Exception);

procedure ExceptBOUND;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: Bound instrucction\n',[GetCoreId]);
  WriteConsoleF('Thread#%d registers dump:\n',[GetCurrentThread.ThreadID]);
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
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise EBoundException.Create ('Bound');
end;

type
  EIllegalInsException = class(Exception);

procedure ExceptILLEGALINS;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: Illegal instrucction\n',[GetCoreId]);
  WriteConsoleF('Thread#%d registers dump:\n',[GetCurrentThread.ThreadID]);
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
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise EIllegalInsException.Create ('Illegal Instruction');
end;

type
  EDevnotAvaException = class(Exception);

procedure ExceptDEVNOTAVA;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: Device not available\n',[GetCoreId]);
  WriteConsoleF('Thread#%d registers dump:\n',[GetCurrentThread.ThreadID]);
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
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise EDevnotAvaException.Create ('Device not available');
end;

type
  EDFException = class(Exception);

procedure ExceptDF;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: Double fault\n',[GetCoreId]);
  WriteConsoleF('Thread#%d registers dump:\n',[GetCurrentThread.ThreadID]);
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
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise EDFException.Create ('Double Fault');
end;

type
  ESTACKFAULTException = class(Exception);

procedure ExceptSTACKFAULT;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: Stack fault\n',[GetCoreId]);
  WriteConsoleF('Thread#%d registers dump:\n',[GetCurrentThread.ThreadID]);
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
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise ESTACKFAULTException.Create ('Stack Fault');
end;

type
  EGENERALPException = class(Exception);

procedure ExceptGENERALP;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: General protection fault\n',[GetCoreId]);
  WriteConsoleF('Thread#%d registers dump:\n',[GetCurrentThread.ThreadID]);
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
  WriteConsoleF('Backtrace:\n',[]);
  {$IFDEF DebugCrash}
    WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  get_caller_stackinfo(pointer(rbp_reg), addr);
  PrintBackTraceStr(pointer(rip_reg));
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise EGENERALPException.Create ('General Protection');
end;

type
  EPageFaultPException = class(Exception);

procedure ExceptPAGEFAULT;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: Page Fault, cr2: %h\n',[GetCoreId, rcr2]);
  WriteConsoleF('Dumping ThreadID: %d\n',[GetCurrentThread.ThreadID]);
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
    DumpDebugRing;
 {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  get_caller_stackinfo(pointer(rbp_reg), addr);
  PrintBackTraceStr(pointer(rip_reg));
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise EPageFaultPException.Create ('Page Fault');
end;

type
  EFPUException = class(Exception);

procedure ExceptFPUE;
var
  rbx_reg: QWord;
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
  WriteConsoleF('[\t] CPU#%d Exception: FPU error\n',[GetCoreId]);
  WriteConsoleF('Thread#%d registers dump:\n',[GetCurrentThread.ThreadID]);
  WriteConsoleF('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
  WriteConsoleF('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
  WriteConsoleF('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
  {$IFDEF DebugCrash}
    WriteDebug('Exception: FPU error\n',[]);
    WriteDebug('Thread#%d registers dump:\n',[GetCurrentThread.ThreadID]);
    WriteDebug('rax: %h, rbx: %h,      rcx: %h\n',[rax_reg, rbx_reg, rcx_reg]);
    WriteDebug('rdx: %h, rbp: %h,  errcode: %h\n',[rdx_reg, rbp_reg, errc_reg]);
    WriteDebug('rsp: %h, rip: %h,   rflags: %h\n',[rsp_reg, rip_reg, rflags_reg]);
    WriteDebug('Backtrace:\n',[]);
  {$ENDIF}
  WriteConsoleF('Backtrace:\n',[]);
  while rbp_reg <> 0 do
  begin
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
  end;
  {$IFDEF EnableDebug}DumpDebugRing;{$ENDIF}
  EnableInt;
  raise EFPUException.Create ('FPU');
end;

procedure InitializeExceptions;
begin
  CaptureInt(EXC_DIVBYZERO, @ExceptDIVBYZERO);
  CaptureInt(EXC_NMI, @ExceptNMI);
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

procedure InitPerCPUProcessVar; forward;

procedure InitLocalData;
begin
  InitPerCPUProcessVar;
  Scheduling(nil);
end;

procedure InitCores;
var
  I, J: LongInt;
  Attemps: Longint;
begin
  for I := 0 to Max_CPU-1 do
  begin
    CPU[I].ApicID := 0 ;
    CPU[I].CurrentThread := nil;
    CPU[I].Threads := nil;
    CPU[I].LastIrq := 0;
    for J := 0 to Max_CPU-1 do
    begin
      CPU[I].MsgsToBeDispatched[J] := nil;
      CpuMxSlots[I][J] := nil;
    end;
  end;
  if CPU_COUNT = 1 then
  begin
    WriteConsoleF('Core#0 ... Running\n',[]);
    Exit;
  end;
  for I := 0 to CPU_COUNT-1 do
  begin
    if not Cores[I].CPUBoot and Cores[I].present then
    begin
      CPU[Cores[I].ApicID].ApicID := Cores[I].ApicID;
      Cores[I].InitProc := @InitLocalData;
      for Attemps:= 0 to 1 do
      begin
        if not InitCore(Cores[I].ApicID) then
        begin
          WriteConsoleF('Core#%d ... Hardware Issue\n', [Cores[I].ApicID]);
          break;
        end;
        if Cores[I].InitConfirmation then
         break;
      end;
      if Cores[I].InitConfirmation then
        WriteConsoleF('Core#%d ... Up\n', [Cores[I].ApicID])
      else
        WriteConsoleF('Core#%d ... Down\n', [Cores[I].ApicID]);
    end else if Cores[I].CPUBoot then
      WriteConsoleF('Core#0 ... Up\n',[]);
  end;
end;

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

procedure AddThreadMsg(Msg: PThreadCreateMsg);
var
  ApicID: LongInt;
  FirstMsg: PThreadCreateMsg;
  CurrentCPU: PCPU;
begin
  CurrentCPU := GetCPU;
  ApicID := Msg.CPU.ApicID;
  FirstMsg := CurrentCPU.MsgsToBeDispatched[ApicID];
  Msg.Next := FirstMsg;
  CurrentCPU.MsgsToBeDispatched[ApicID] := Msg;
end;

function GetCurrentThread: PThread; inline;
var
  th: ^PThread;
begin
  th := Pointer(GetGSOffset(PERCPUCURRENTHREAD * sizeof(QWORD)));
  Result := th^;
end;

function GetCPU: PCPU; inline;
begin
  Result := Pointer(GetGSOffset(PERCPUCURRENTCPU * sizeof(QWORD)));
end;

const
  Initialized: Boolean = False; // This is used only when the first thread in the system is created

function ThreadCreate(const StackSize: SizeUInt; CPUID: DWORD; ThreadFunction: TThreadFunc; Arg: Pointer): PThread;
var
  NewThread, Current: PThread;
  NewThreadMsg: TThreadCreateMsg;
  ip_ret: ^QWORD;
begin
  if CPUID = GetCoreId then
  begin
    NewThread := ToroGetMem(SizeOf(TThread));
    if NewThread = nil then
    begin
      {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread = nil\n', []); {$ENDIF}
      Result := nil;
      Exit;
    end;
    {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread: %h\n', [PtrUInt(NewThread)]); {$ENDIF}
    NewThread.StackAddress := ToroGetMem(StackSize);
    if NewThread.StackAddress = nil then
    begin
      {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread.StackAddress = nil\n',[]); {$ENDIF}
      ToroFreeMem(NewThread);
      Result := nil;
      Exit;
    end;
    if not Initialized then
    begin
      {$IFDEF DebugProcess} WriteDebug('ThreadCreate: First Thread -> Initialized=True\n', []); {$ENDIF}
      Initialized := True;
    end else if THREADVAR_BLOCKSIZE <> 0 then
    begin
      NewThread.TLS := ToroGetMem(THREADVAR_BLOCKSIZE) ;
      if NewThread.TLS = nil then
      begin
        {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread.TLS = nil\n', []); {$ENDIF}
        ToroFreeMem(NewThread.StackAddress);
        ToroFreeMem(NewThread);
        Result := nil;
        Exit;
      end;
    end;
    NewThread.StackSize := StackSize;
    NewThread.ret_thread_sp := Pointer(PtrUInt(NewThread.StackAddress) + StackSize-1);
    NewThread.sleep_rdtsc := 0;
    NewThread.FlagKill := False;
    NewThread.State := tsReady;
    NewThread.StartArg := Arg;
    NewThread.ThreadFunc := ThreadFunction;
    {$IFDEF DebugProcess} WriteDebug('ThreadCreate: NewThread.ThreadFunc: %h\n', [PtrUInt(@NewThread.ThreadFunc)]); {$ENDIF}
    NewThread.PrivateHeap := XHeapAcquire(CPUID);
    NewThread.ThreadID := TThreadID(NewThread);
    NewThread.CPU := GetCPU;
    NewThread.Parent :=  GetCurrentThread;
    ip_ret := NewThread.ret_thread_sp;
    Dec(ip_ret);
    ip_ret^ := PtrUInt(@ThreadMain);
    Dec(ip_ret);
    ip_ret^ := PtrUInt(NewThread.ret_thread_sp) - SizeOf(Pointer);
    NewThread.ret_thread_sp := Pointer(PtrUInt(NewThread.ret_thread_sp) - SizeOf(Pointer)*2);
    AddThreadReady(NewThread);
    Result := NewThread
  end else
  begin
    NewThreadMsg.StackSize := StackSize;
    NewThreadMsg.StartArg := Arg;
    NewThreadMsg.ThreadFunc := ThreadFunction;
    NewThreadMsg.CPU := @CPU[CPUID];
    Current := GetCurrentThread;
    NewThreadMsg.Parent := Current;
    NewThreadMsg.Next := nil;
    // Remote core wakes up current thread
    // once operation is finished
    Current.State := tsSuspended;
    AddThreadMsg(@NewThreadMsg);
    SysThreadSwitch;
    Result := NewThreadMsg.RemoteResult;
  end;
end;

procedure Sleep(Miliseg: LongInt);
var
  ResumeTime: Int64;
begin
  ResumeTime := read_rdtsc + Miliseg * LocalCPUSpeed * 1000;
  {$IFDEF DebugProcess} WriteDebug('Sleep: ResumeTime: %d\n', [ResumeTime]); {$ENDIF}
  while ResumeTime > read_rdtsc do
    Scheduling(nil);
  {$IFDEF DebugProcess} WriteDebug('Sleep: ResumeTime exiting\n', []); {$ENDIF}
end;

procedure ThreadExit(Schedule: Boolean);
var
  CurrentThread, NextThread: PThread;
begin
  CurrentThread := GetCurrentThread ;
  XHeapRelease(CurrentThread.PrivateHeap);
  if CurrentThread = PThread(InitialThreadID) then
  begin
    WriteConsoleF('ThreadExit: /RWarning!/n MainThread has been killed\n',[]);
    {$IFDEF DebugCrash}
      WriteDebug('ThreadExit: Warning! MainThread has been killed',[]);
    {$ENDIF}
  end;
  NextThread := CurrentThread.Next;
  RemoveThreadReady(CurrentThread);
  if THREADVAR_BLOCKSIZE <> 0 then
    ToroFreeMem(CurrentThread.TLS);
  ToroFreeMem(CurrentThread.StackAddress);
  ToroFreeMem(CurrentThread);
  {$IFDEF DebugProcess} WriteDebug('ThreadExit: ThreadID: %h\n', [CurrentThread.ThreadID]); {$ENDIF}
  if Schedule then
    Scheduling(NextThread);
end;

function SysKillThread(ThreadID: TThreadID): DWORD;
var
  CurrentThread: PThread;
  Thread: PThread;
begin
  Thread := PThread(ThreadID);
  CurrentThread := GetCurrentThread;
  if CurrentThread = nil then
  begin
    Result := 0;
    Exit;
  end;
  {$IFDEF DebugProcess} WriteDebug('SysKillThread - sending signal to Thread: %h in CPU: %d \n', [ThreadID, Thread.CPU.ApicID]); {$ENDIF}
  Thread.FlagKill := True;
  Result := 0;
end;

function SysSuspendThread(ThreadID: TThreadID): DWORD;
var
  CurrentThread: PThread;
  Thread: PThread;
begin
  Thread := PThread(ThreadID);
  CurrentThread := GetCurrentThread;
  if CurrentThread = nil then
  begin
    Result := 0;
    Exit;
  end;
  if (Thread = nil) or (CurrentThread.ThreadID = ThreadID) then
  begin
    CurrentThread.state := tsSuspended;
    SysThreadSwitch;
    {$IFDEF DebugProcess} WriteDebug('SuspendThread: Current Threads was Suspended\n',[]); {$ENDIF}
  end else
    Thread.State := tsSuspended;
  Result := 0;
end;

function SysResumeThread(ThreadID: TThreadID): DWORD;
var
  CurrentThread: PThread;
  Thread: PThread;
begin
  Thread := PThread(ThreadID);
  CurrentThread := GetCurrentThread;
  if CurrentThread = nil then
  begin
    Result := 0;
    Exit;
  end;
  Thread.State := tsReady;
  Result := 0;
end;

procedure Inmigrating(CurrentCPU: PCPU);
var
  RemoteCpuID: LongInt;
  RemoteMsgs: PThreadCreateMsg;
begin
  for RemoteCpuID := 0 to CPU_COUNT-1 do
  begin
    if CpuMxSlots[CurrentCPU.ApicID][RemoteCpuID] <> nil then
    begin
      RemoteMsgs := CpuMxSlots[CurrentCPU.ApicID][RemoteCpuID];
      while RemoteMsgs <> nil do
      begin
        RemoteMsgs.RemoteResult := ThreadCreate(RemoteMsgs.StackSize, CurrentCPU.ApicID, RemoteMsgs.ThreadFunc, RemoteMsgs.StartArg);
        RemoteMsgs.Parent.state := tsReady;
        RemoteMsgs := RemoteMsgs.Next;
      end;
      CpuMxSlots[CurrentCPU.ApicID][RemoteCpuID] := nil;
    {$IFDEF DebugProcessInmigrating}WriteDebug('Inmigrating - from CPU %d to LocalCPU %d\n', [RemoteCpuID, CurrentCPU.ApicID]);{$ENDIF}
    end;
  end;
end;

procedure Emigrating(CurrentCPU: PCPU);
var
  RemoteCpuID: LongInt;
begin
  for RemoteCpuID := 0 to CPU_COUNT-1 do
  begin
    if (CurrentCPU.MsgsToBeDispatched[RemoteCpuID] <> nil) and (CpuMxSlots[RemoteCpuID][CurrentCPU.ApicID] = nil) then
    begin
      CpuMxSlots[RemoteCpuID][CurrentCPU.ApicID] := CurrentCPU.MsgsToBeDispatched[RemoteCpuID];
      CurrentCPU.MsgsToBeDispatched[RemoteCpuID] := nil;
      {$IFDEF DebugProcessEmigrating} WriteDebug('Emigrating - Switch Threads of DispatchArray[%d] to EmigrateArray[%d]\n', [CurrentCPU.ApicID, RemoteCpuID]); {$ENDIF}
    end;
  end;
end;

// if Candidate <> nil, the scheduler assumes that CurrentThread can't be used
procedure Scheduling(Candidate: PThread); {$IFDEF FPC} [public , alias :'scheduling']; {$ENDIF}
var
  CurrentCPU: PCPU;
  CurrentThread, LastThread, Th, tmp: PThread;
  rbp_reg: pointer;
begin
  CurrentCPU := GetCPU;
  while True do
  begin
    if CurrentCPU.Threads = nil then
    begin
      {$IFDEF DebugProcess} WriteDebug('Scheduling: scheduler goes to inmigration loop\n', []); {$ENDIF}
      while CurrentCPU.Threads = nil do
      begin
        Inmigrating(CurrentCPU);
      end;
      CurrentCPU.CurrentThread := CurrentCPU.Threads;
      {$IFDEF DebugProcess} WriteDebug('Scheduling: current thread, stack: %h\n', [PtrUInt(CurrentCPU.CurrentThread.ret_thread_sp)]); {$ENDIF}
      SwitchStack(nil, @CurrentCPU.CurrentThread.ret_thread_sp);
      Exit;
    end;
    Emigrating(CurrentCPU);
    Inmigrating(CurrentCPU);
    CurrentThread := CurrentCPU.CurrentThread;
    tmp := Candidate;
    if Candidate <> nil then
      LastThread := Candidate
    else
    begin
      LastThread := CurrentCPU.CurrentThread;
      Candidate := LastThread.Next;
    end;
    repeat
    {$IFDEF DebugProcess} WriteDebug('Scheduling: Candidate %h, state: %d\n', [PtrUInt(Candidate), Candidate.State]); {$ENDIF}
      if Candidate.State = tsReady then
        Break
      else if (Candidate.State = tsIOPending) and not Candidate.IOScheduler.DeviceState^ then
      begin
        Candidate.State := tsReady;
        Break;
      end else
        Candidate := Candidate.Next;
    until Candidate = LastThread;
    {$IFDEF DebugProcess} WriteDebug('Scheduling: Candidate state: %d\n', [Candidate.state]); {$ENDIF}
    if Candidate.state <> tsReady then
      Continue;
    CurrentCPU.CurrentThread := Candidate;
    {$IFDEF DebugProcess} WriteDebug('Scheduling: thread %h, state: %d, stack: %h\n', [PtrUInt(Candidate), Candidate.State, PtrUInt(Candidate.ret_thread_sp)]); {$ENDIF}
    if Candidate = CurrentThread then
      Exit;
    GetRBP;
    If tmp = nil then
      CurrentThread.ret_thread_sp := rbp_reg;
    rbp_reg := Candidate.ret_thread_sp;
    StoreRBP;
    Break;
  end;
end;

procedure SysInitThreadVar(var Offset: DWORD; Size: DWORD);
begin
  Offset := THREADVAR_BLOCKSIZE;
  THREADVAR_BLOCKSIZE := THREADVAR_BLOCKSIZE+Size;
end;

function SysRelocateThreadvar(Offset: DWORD): Pointer;
var
  CurrentThread: PThread;
begin
  CurrentThread := GetCurrentThread;
  Result := Pointer(PtrUInt(CurrentThread.TLS)+Offset)
end;

procedure SysAllocateThreadVars;
begin
  GetCurrentThread.TLS := ToroGetMem(THREADVAR_BLOCKSIZE) ;
  Panic(GetCurrentThread.TLS = nil, 'SysAllocateThreadVars: Out of memory', []);
  {$IFDEF DebugProcess} WriteDebug('SysAllocateThreadVars - TLS: %h Size: %d\n', [PtrUInt(GetCurrentThread.TLS), THREADVAR_BLOCKSIZE]); {$ENDIF}
end;

procedure CreateInitThread(ThreadFunction: TThreadFunc; const StackSize: SizeUInt);
var
  InitThread: PThread;
  LocalCPU: PCPU;
begin
  {$IFDEF DebugProcess} WriteDebug('CreateInitThread: StackSize: %d\n', [StackSize]); {$ENDIF}
  LocalCPU := GetCPU;
  InitThread := ThreadCreate(StackSize, LocalCPU.ApicID, ThreadFunction, nil);
  if InitThread = nil then
  begin
    WriteConsoleF('InitThread = nil\n', []);
    hlt;
  end;
  LocalCPU.CurrentThread := InitThread;
  InitialThreadID := TThreadID(InitThread);
  WriteConsoleF('Starting MainThread: %h\n', [InitialThreadID]);
  // only performed explicitely for initialization procedure
  {$IFDEF FPC} InitThreadVars(@SysRelocateThreadvar); {$ENDIF}
  // TODO: InitThreadVars for DELPHI
  {$IFDEF DebugProcess} WriteDebug('CreateInitThread: InitialThreadID: %h\n', [InitialThreadID]); {$ENDIF}
  // TODO: when compiling with DCC, check that previous assertion is correct
  // TODO: when previous IFDEF is activated, check that WriteDebug is not messing
  InitThread.ret_thread_sp := Pointer(PtrUInt(InitThread.ret_thread_sp)+SizeOf(Pointer));
  {$IFDEF DebugProcess} WriteDebug('CreateInitThread: InitThread.ret_thread_sp: %h\n', [PtrUInt(InitThread.ret_thread_sp)]); {$ENDIF}
  change_sp(InitThread.ret_thread_sp);
end;

// Yield the current CPU to the next ready thread
procedure SysThreadSwitch;
var
 tmp: PCPU;
 Thread: PThread;
begin
  SaveContext;
  Scheduling(nil);
  //RestoreContext;
  if GetCurrentThread.FlagKill then
  begin
    {$IFDEF DebugProcess} WriteDebug('Signaling - killing CurrentThread\n', []); {$ENDIF}
    ThreadExit(True);
  end;
  // Restore at this point otherwise %rdi is not correctly restored
  RestoreContext;
end;

procedure ThreadMain;
var
  CurrentThread: PThread;
begin
  CurrentThread := GetCurrentThread ;
  {$IFDEF FPC} InitThread(CurrentThread.StackSize); {$ENDIF}
  // TODO: InitThread() for Delphi
  {$IFDEF DebugProcess} WriteDebug('ThreadMain: CurrentThread: #%h\n', [PtrUInt(CurrentThread)]); {$ENDIF}
  {$IFDEF DebugProcess} WriteDebug('ThreadMain: CurrentThread.ThreadFunc: %h\n', [PtrUInt(@CurrentThread.ThreadFunc)]); {$ENDIF}
  ExitCode := CurrentThread.ThreadFunc(CurrentThread.StartArg);
  {$IFDEF DebugProcess} WriteDebug('ThreadMain: returning from CurrentThread.ThreadFunc CurrentThread: %h\n', [PtrUInt(CurrentThread)]); {$ENDIF}
  if CurrentThread.ThreadID = InitialThreadID then
    SystemExit;
  ThreadExit(True);
end;

function SysBeginThread(SecurityAttributes: Pointer; StackSize: SizeUInt; ThreadFunction: TThreadFunc; Parameter: Pointer;
                         CPU: DWORD; var ThreadID: TThreadID): TThreadID;
var
  NewThread: PThread;
begin
  if (LongInt(CPU) = CPU_NIL) then
    CPU := GetCoreId
  else if (LongInt(CPU) > CPU_COUNT-1) or (not Cores[Longint(CPU)].InitConfirmation) then
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

function BeginThread(SecurityAttributes: Pointer; StackSize: SizeUInt; ThreadFunction: TThreadFunc; Parameter: Pointer; CreationFlags: DWORD; var ThreadID: TThreadID): TThreadID;
begin
  Result := SysBeginThread(SecurityAttributes, StackSize, ThreadFunction, Parameter, CreationFlags, ThreadID);
end;

procedure SysEndThread(ExitCode: DWORD);
begin
  ThreadExit(True);
end;

function SysGetCurrentThreadID: TThreadID;
begin
  Result := GetCurrentThread.ThreadID;
end;

procedure SystemExit; [public, alias : 'SYSTEMEXIT'];
begin
  {$IFDEF DebugProcess} WriteDebug('System_Exit due to ExitCode: %d\n', [ExitCode]); {$ENDIF}
  WriteConsoleF('\nSystem_Exit due to ExitCode: %d\n', [ExitCode]);
  {$IFDEF EnableDebug}
    DumpDebugRing;
  {$ENDIF}
  {$IFDEF ShutdownWhenFinished}
    ShutdownInQemu;
  {$ELSE}
    hlt;
  {$ENDIF}
end;

// Halt core if a Panic condition is reached
procedure Panic(const cond: Boolean; const Format: PChar; const Args: array of PtrUInt);
var
 rbp_reg: QWord;
 addr: pointer;
begin
  if not cond then
    Exit;
  DisableInt;
  WriteConsoleF('Panic:\n',[]);
  WriteConsoleF(Format, Args);
  {$IFDEF DebugProcess} WriteDebug('Panic: ', []); WriteDebug(Format, Args); {$ENDIF}
  {$IFDEF DebugCrash}
    WriteConsoleF('Backtrace:\n',[]);
    // FIXME: Print the whole stack
    GetRBP;
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
    get_caller_stackinfo(pointer(rbp_reg), addr);
    PrintBackTraceStr(addr);
    DumpDebugRing;
  {$ENDIF}
  while True do;
end;

// Halt core if time since last irq is longer than WAIT_IDLE_CORE_MS
// otherwise call the scheduler
procedure SysSetCoreIdle;
begin
  // TODO: Set the core idle in the table
  If (read_rdtsc - GetCPU.LastIrq) > (LocalCpuSpeed * 1000)* WAIT_IDLE_CORE_MS then
    hlt
  else
    SysThreadSwitch;
end;

// TODO: critical sections are important when using objpascal in multicore
procedure SysInitCriticalSection(var cs : TRTLCriticalSection);
begin
end;

procedure SysDoneCriticalSection(var cs : TRTLCriticalSection);
begin
end;

procedure SysLeaveCriticalSection(var cs : TRTLCriticalSection);
begin
end;

procedure SysEnterCriticalSection(var cs : TRTLCriticalSection);
begin
end;

procedure InitPerCPUProcessVar;
begin
  SetPerCPUVar(PERCPUCURRENTHREAD, PtrUInt(@CPU[GetCoreId].CurrentThread));
  SetPerCPUVar(PERCPUCURRENTCPU, PtrUInt(@CPU[GetCoreId]));
end;

procedure ProcessInit;
var
  j: LongInt;
begin
  if KernelParamCount > 0 then
  begin
    WriteConsoleF('Kernel Parameters:\n', []);
    for j:= 0 to KernelParamCount-1 do
      WriteConsoleF('param[%d]: %p\n', [j, PtrUInt(GetKernelParam(j))]);
  end;
  FillChar(CPU, sizeof(CPU), 0);
  Panic(LocalCpuSpeed = 0,'LocalCpuSpeed = 0\n', []);
  {$IFDEF DebugProcess}
    if LocalCpuSpeed = MAX_CPU_SPEED_MHZ then
      WriteDebug('ProcessInit: warning LocalCpuSpeed=MAX_CPU_SPEED_MHZ\n',[]);
  {$ENDIF}
  if HasException then
    InitializeExceptions;
  InitPerCPUProcessVar;
  InitCores;
  ShutdownProcedure := nil;
  {$IFDEF EnableDebug}
    WriteDebug('ProcessInit: LocalCpuSpeed: %d Mhz, Cores: %d\n', [LocalCpuSpeed, CPU_COUNT]);
  {$ENDIF}
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
    DoneCriticalSection    := @SysDoneCriticalSection;
    EnterCriticalSection   := @SysEnterCriticalSection;
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
    RTLEventWaitFor        := nil;
    RTLEventWaitForTimeout := nil;
  end;
  SetThreadManager(ToroThreadManager);
{$ENDIF}
end;

end.

