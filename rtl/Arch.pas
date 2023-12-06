//
// Arch.pas
//
// This units contains the the code that is platform-dependent.
//
// Copyright (c) 2003-2022 Matias Vara <matiasevara@torokernel.io>
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

unit Arch;

{$I Toro.inc}

interface

const
  EXC_DIVBYZERO = 0;
  EXC_INT3 = 3;
  EXC_INT1 = 1;
  EXC_NMI = 2;
  EXC_OVERFLOW = 4;
  EXC_BOUND = 5;
  EXC_ILLEGALINS = 6;
  EXC_DEVNOTAVA = 7;
  EXC_DF = 8;
  EXC_STACKFAULT = 12;
  EXC_GENERALP = 13;
  EXC_PAGEFAUL = 14;
  EXC_FPUE = 16;

  MEM_AVAILABLE = 1;
  MEM_RESERVED = 2;

  // Max CPU speed in Mhz
  MAX_CPU_SPEED_MHZ = 2393;

  PERCPUAPICID = 0;

  // Lenght of the cacheline in qwords
  CACHELINE_LEN = 8;

type
{$IFDEF UNICODE}
  XChar = AnsiChar;
  PXChar = PAnsiChar;
{$ELSE}
  XChar = Char;
  AnsiString = string;
  PXChar = PChar;
{$ENDIF} // Alias type XMLString for string or WideString
{$IFDEF FPC}
  UInt32 = Cardinal;
  UInt64 = QWORD;
{$ENDIF}
{$IFDEF DCC}
  DWORD = UInt32;
  PDWORD = ^DWORD;
  QWORD = UInt64;
  SizeUInt = QWORD;
  PtrInt = Int64;
  PtrUInt = UInt64;
{$ENDIF}
  TNow = record
    Sec : LongInt;
    Min: LongInt;
    Hour: LongInt;
    Day: LongInt;
    Month: LongInt;
    Year: LongInt
  end;
  PNow = ^TNow;

  TMemoryRegion = record
    Base: QWord;
    Length: QWord;
    Flag: Word; // MEM_RESERVED, MEM_AVAILABLE
  end;
  PMemoryRegion = ^TMemoryRegion;

  TPerCPUCore = record
    ApicID: LongInt;
    Present: Boolean;
    CPUBoot: Boolean;
    InitConfirmation: Boolean;
    pad0: Byte;
    InitProc: procedure;
    pad1: array[1..CACHELINE_LEN-2] of QWORD;
  end;

// Utils
procedure InttoStr(Value: PtrUInt; buff: PXChar);
function StrCmp(p1, p2: PXChar; Len: LongInt): Boolean;
procedure StrConcat(left, right, dst: PXChar);

procedure SetPerCPUVar(Off: Byte; Value: QWORD);
function GetGSOffset(off: Byte): QWORD;
procedure bit_reset(Value: Pointer; Offset: QWord);
procedure bit_set(Value: Pointer; Offset: QWord); assembler;
function bit_test ( Val : Pointer ; pos : QWord ) : Boolean;
procedure change_sp (new_esp : Pointer ) ;
procedure Delay(ms: LongInt);
function GetCoreId: Byte; inline;
function GetApicBaseAddr: Pointer;
procedure IOApicIrqOn(Irq: Byte);
function is_apic_ready: Boolean ;
procedure NOP;
function read_portb(port: Word): Byte;
procedure read_portd(Data: Pointer; Port: Word);
function read_rdtsc: QWORD;
procedure send_apic_init (apicid : Byte) ;
procedure send_apic_startup (apicid , vector : Byte );
function SpinLock(CmpVal, NewVal: UInt64; var addval: UInt64): UInt64; assembler;
procedure SwitchStack(sv: Pointer; ld: Pointer);
procedure write_portb(Data: Byte; Port: Word);
procedure write_portd(const Data: Pointer; const Port: Word);
procedure write_portw(Data: Word; Port: Word);
procedure CaptureInt (int: Byte; Handler: Pointer);
procedure CaptureException(Exception: Byte; Handler: Pointer);
procedure ArchInit;
procedure Now (Data: PNow);
procedure Interruption_Ignore;
function GetMemoryRegion (ID: LongInt ; Buffer : PMemoryRegion): LongInt;
function GetNextUsableMemoryRegion(Curr: LongInt): LongInt;
function InitCore(ApicID: Byte): Boolean;
procedure SetPageCache(Add: Pointer);
procedure RemovePageCache(Add: Pointer);
function SecondsBetween(const ANow: TNow;const AThen: TNow): LongInt;
procedure ShutdownInQemu;
procedure DelayMicro(microseg: LongInt);
function read_portw(port: Word): Word;
procedure SetPageReadOnly(Add: Pointer);
procedure send_apic_int (apicid, vector: Byte);
procedure eoi_apic;
procedure monitor(addr: Pointer; ext: DWORD; hint: DWORD);
procedure mwait(ext: DWORD; hint: DWORD);
procedure hlt; assembler;
procedure ReadBarrier;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
procedure ReadWriteBarrier;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
procedure WriteBarrier;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
function GetKernelParam(I: LongInt): Pchar;
function read_ioapic_reg(offset: dword): dword;
procedure write_ioapic_reg(offset, val: dword);
function find_msb_set(value: DWORD): LongInt; assembler;
function GetStealCPU: QWORD;

const
  MP_START_ADD = $e0000;
  RESET_VECTOR = $467; // when the IPI occurs the procesor jumps here
  cpu_type = 0;
  apic_type = 2;
  MAX_CPU = 16;  // Number of max CPU support
  ALLOC_MEMORY_START = $800000; // Address Start of Alloc Memory
  KERNEL_IMAGE_START = $400000;
  PAGE_SIZE = 2*1024*1024; // 2 MB per Page
  HasCacheHandler: Boolean = True;
  HasException: Boolean = True;
  HasFloatingPointUnit : Boolean = True;
  INTER_CORE_IRQ = 80;
  PVH_MEMMAP_PADDR = 40;
  PVH_MEMMAP_ENTRIES = 48;
  PVH_CMDLINE_PADDR = 24;
  BASE_IRQ = 32;
  MAX_ADDR_MEM = 512*1024*1014*1014;
  // The value of MAX_PERCPU_VAR shall be CACHELINE_LEN aligned
  MAX_PERCPU_VAR = CACHELINE_LEN * 2;

var
  CPU_COUNT: LongInt;
  AvailableMemory: QWord;
  LocalCpuSpeed: Int64 = 0; // LocalCpuSpeed has the speed of the local CPU in Mhz
  StartTime: TNow;
  Cores: array[0..MAX_CPU-1] of TPerCPUCore;
  LargestMonitorLine: longint;
  SmallestMonitorLine: longint;
  KernelParam: Pchar = Nil;
  KernelParamEnd: Pchar = Nil;
  KernelParamCount: LongInt = 0;
{$push}
{$codealign varmin=64}
  PerCPUVar: array[0..MAX_CPU-1] of array[0..MAX_PERCPU_VAR-1] of QWORD;
{$pop}

implementation

uses Kernel, Console;

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}

const
  IOApic_Base = $FEC00000;
  Apic_Base = $FEE00000; // $FFFFFFFF - $11FFFFF // = 18874368 -> 18MB from the top end
  apicid_reg = apic_base + $20;
  icrlo_reg = apic_base + $300;
  icrhi_reg = apic_base + $310;
  err_stat_reg = apic_base + $280;
  timer_reg = apic_base + $320;
  timer_init_reg = apic_base + $380;
  timer_curr_reg = apic_base + $390;
  divide_reg = apic_base + $3e0;
  eoi_reg = apic_base + $b0;
  svr_reg = apic_base + $f0;
  lint1_reg = apic_base + $360;

  // IDT descriptors
  gate_syst = $8E;

  // Address of Page Directory
  PDADD = $100000;
  KERNEL_PARAM = $200000;
  IDTADDRESS = $3080;
  GDTADDRESS = $3000;

  Kernel_Code_Sel = $18;
  Kernel_Data_Sel = $10;

  size_start_stack = 700;

  MSR_KVM_SYSTEM_TIME_NEW = $4b564d01;
  MSR_KVM_WALL_CLOCK_NEW =  $4b564d00;
  MSR_KVM_STEAL_TIME = $4b564d03;

  // Bootloader signatures
  SIG_PVH = 1;
  SIG_K64 = 2;
  SIG_BARE = 3;

  // first descriptor after Null, CS, DS, CS64
  FIRST_DESCRIPTOR = 4;

  BOOT_CMDLINE_OFFSET : array[1..3] of LongInt = (PVH_CMDLINE_PADDR, $1f1 + 55, 0);

type
  p_apicid_register = ^apicid_register ;
  apicid_register = record
    res : Word ;
    res0 : Byte ;
    apicid : Byte ;
  end;

  TGDTR = record
    limite: Word;
    res1, res2: DWORD;
  end;

  p_mp_floating_struct  = ^mp_floating_struct ;
  mp_floating_struct = record
    signature: array[0..3] of XChar;
    phys: DWORD;
    data: DWORD;
    mp_type: DWORD;
  end;

  p_mp_table_header = ^mp_table_header ;
  mp_table_header = record
    signature : array[0..3] of XChar ;
    len: Word;
    spec: byte;
    checksum: byte;
    oem: array[0..7] of Char;
    productid: array[0..11] of Char;
    prt: DWORD;
    size: Word ;
    oemcount: Word ;
    addres_apic: DWORD;
    resd: DWORD ;
  end;

  p_mp_processor_entry = ^mp_processor_entry ;
  mp_processor_entry = record
    tipe: Byte ;
    apic_id: Byte ;
    apic_ver: Byte ;
    flags: Byte ;
    signature: DWORD ;
    feature: DWORD ;
    res: array[0..1] of DWORD ;
  end;

  p_mp_apic_entry = ^mp_apic_entry ;
  mp_apic_entry = record
    tipe : Byte ;
    apic_id : Byte ;
    apic_ver : Byte ;
    flags : Byte ;
    addres_apic : DWORD ;
  end;

  TInteruptGate = record
    handler_0_15: Word;
    selector: Word;
    nu: Byte;
    tipe: Byte;
    handler_16_31: Word;
    handler_32_63: DWORD;
    res: DWORD;
  end;

  PDescriptor = ^TDescriptor;
  TDescriptor = record
    limit_0_15: Word;
    base_0_15: Word;
    base_23_16: Byte;
    tipe: Byte;
    limit_16_19: Byte;
    base_31_24: Byte;
  end;

  TInterruptGateArray = array[0..255] of TInteruptGate;
  PInterruptGateArray = ^TInterruptGateArray;
  p_intr_gate_struct = ^TInteruptGate;

  PDirectoryPage = ^TDirectoryPageEntry;
  TDirectoryPageEntry = record
    PageDescriptor: QWORD;
  end;

  PWallClock = ^TWallClock;
  TWallClock = packed record
    version: DWORD;
    pad0: DWORD;
    tsc_timestamp: QWORD;
    system_time: QWORD;
    tsc_to_system_mul: DWORD;
    tsc_shift: BYTE;
    flags: BYTE;
    pad: array[0..1] of BYTE;
  end;

  PKVMStealTime = ^TKVMStealTime;
  TKVMStealTime = packed record
      steal: QWORD;
      version: DWORD;
      flags: DWORD;
      preempted: Byte;
      u8_pad: array[0..2] of Byte;
      pad: array[0..10] of DWORD;
  end;


function GetApicId: Byte; forward;

var
  ToroStealClocks: array[0..MAX_CPU-1] of TKVMStealTime;

procedure InttoStr(Value: PtrUInt; buff: PXChar);
var
  I, Len: Byte;
  // 21 is the max number of characters needed to represent 64 bits number in decimal
  S: string[21];
begin
  Len := 0;
  I := 21;
  if Value = 0 then
  begin
    buff^ := '0';
    buff  := buff + 1;
    buff^ := #0;
  end else
  begin
    while Value <> 0 do
    begin
      S[I] := AnsiChar((Value mod 10) + $30);
      Value := Value div 10;
      I := I-1;
      Len := Len+1;
    end;
    S[0] := Char(Len);
   for I := (sizeof(S)-Len) to sizeof(S)-1 do
   begin
    buff^ := S[I];
    buff +=1;
   end;
   buff^ := #0;
  end;
end;

function StrCmp(p1, p2: PXChar; Len: LongInt): Boolean;
var
  i: LongInt;
begin
  Result := False;
  for i := 0 to Len-1 do
  begin
    if p1^ <> p2^ then
      Exit;
    p1 += 1;
    p2 += 1;
  end;
  Result := true;
end;

procedure StrConcat(left, right, dst: PXChar);
begin
  Move(left^,dst^,Length(left));
  dst := dst + Length(left);
  Move(right^,dst^,Length(right));
  dst +=Length(right);
  dst^ := #0;
end;

var
  idt_gates: PInterruptGateArray; // Pointer to IDT
  // pointer to start of the day structure
  sodpointer: Pointer;
  // bootloader signature
  bootsig: LongInt;
  ToroClock: TWallClock;

procedure CaptureInt(int: Byte; Handler: Pointer);
begin
  Move(PtrUInt(Handler), idt_gates^[int].handler_0_15, sizeof(WORD));
  idt_gates^[int].selector := kernel_code_sel;
  idt_gates^[int].tipe := gate_syst;
  idt_gates^[int].handler_16_31 := Word((PtrUInt(Handler) shr 16) and $ffff);
  idt_gates^[int].handler_32_63 := DWORD(PtrUInt(Handler) shr 32);
  idt_gates^[int].res := 0;
  idt_gates^[int].nu := 0;
end;

procedure LoadGs(Des: Longint); assembler;
asm
   mov gs, word Des
end;

procedure InitGS;
var
  gdt_p : PDescriptor;
  sel: LongInt;
  CoreId: Byte;
  base: Pointer;
begin
  CoreId := GetApicId;
  PerCPUVar[CoreId][PERCPUAPICID] := CoreId;
  base := @PerCPUVar[CoreId][PERCPUAPICID];
  sel := sizeof(TDescriptor) * (CoreId + FIRST_DESCRIPTOR);
  gdt_p := Pointer(GDTADDRESS + sel);
  gdt_p.limit_0_15 := $ffff;
  gdt_p.base_0_15 := DWORD(PtrUInt(base)) and $ffff;
  gdt_p.base_23_16 := (DWORD(PtrUInt(base)) and $ff0000) shr 16;
  gdt_p.tipe := $93;
  gdt_p.limit_16_19 := $cf;
  gdt_p.base_31_24 := (DWORD(PtrUInt(base)) and $ff000000) shr 24;
  LoadGs(sel);
end;

function GetGSOffset(off: byte): QWORD; assembler;
asm
  mov rax, QWORD PTR gs:off
end;

function GetCoreId: Byte; inline;
begin
  Result := Byte(GetGSOffset(PERCPUAPICID));
end;

procedure SetPerCPUVar(Off: Byte; Value: QWORD);
begin
  PerCPUVar[GetApicId][Off] := Value;
end;

procedure CaptureException(Exception: Byte; Handler: Pointer);
begin
  Move(PtrUInt(Handler), idt_gates^[Exception].handler_0_15, sizeof(WORD));
  idt_gates^[Exception].selector := kernel_code_sel;
  idt_gates^[Exception].tipe := gate_syst ;
  idt_gates^[Exception].handler_16_31 := Word((PtrUInt(Handler) shr 16) and $ffff);
  idt_gates^[Exception].handler_32_63 := DWORD(PtrUInt(Handler) shr 32);
  idt_gates^[Exception].res := 0 ;
  idt_gates^[Exception].nu := 0 ;
end;

procedure write_portb(Data: Byte; Port: Word); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  {$IFDEF LINUX} mov dx, port {$ENDIF}
  mov al, data
  out dx, al
end;

procedure write_portw(Data: Word; Port: Word); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  {$IFDEF LINUX} mov dx, port {$ENDIF}
  mov ax, data
  out dx, ax
end;

function read_portb(port: Word): Byte; assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov dx, port
  in al, dx
end;

function read_portw(port: Word): Word; assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov dx, port
  in ax, dx
end;

procedure write_portd(const Data: Pointer; const Port: Word); {$IFDEF ASMINLINE} inline; {$ENDIF}
asm // RCX: data, RDX: port
  push rsi
  {$IFDEF LINUX} mov dx, port {$ENDIF}
  mov rsi, data // DX=port
  outsd
  pop rsi
end;

procedure read_portd(Data: Pointer; Port: Word); {$IFDEF ASMINLINE} inline; {$ENDIF}
asm // RCX: data, RDX: port
  push rdi
  {$IFDEF LINUX} mov dx, port {$ENDIF}
  mov rdi, data // DX=port
  insd
  pop rdi
end;

procedure send_apic_init(apicid: Byte);
var
  icrl, icrh: ^DWORD;
begin
  icrl := Pointer(icrlo_reg);
  icrh := Pointer(icrhi_reg) ;
  icrh^ := apicid shl 24 ;
  icrl^ := $500 or $8000 or $4000; // INIT or LEVEL or ASSERT
  DelayMicro(200);
  icrl^ := $500 or $8000; // INIT or LEVEL
  DelayMicro(200);
end;

procedure send_apic_startup(apicid, vector: Byte);
var
  icrl, icrh: ^DWORD;
begin
  icrl := Pointer(icrlo_reg);
  icrh := Pointer(icrhi_reg) ;
  icrh^ := apicid shl 24 ;
  // mode: init, destination no shorthand
  icrl^ := $600 or vector;
end;

procedure send_apic_int (apicid, vector: Byte);
var
  icrl, icrh: ^DWORD;
begin
  Delay(10);
  icrl := Pointer(icrlo_reg);
  icrh := Pointer(icrhi_reg) ;
  icrh^ := apicid shl 24 ;
  icrl^ := vector;
end;

procedure enable_local_apic;
var
  svr: ^DWORD;
begin
  svr := Pointer(svr_reg);
  svr^ := svr^ or $100;
  Delay(10);
end;

procedure eoi_apic;
var
  tmp: ^DWORD;
begin
  tmp := Pointer(eoi_reg);
  tmp^ := 0;
end;

procedure write_ioapic_reg(offset, val: dword);
var
  tmp: ^dword;
begin
  tmp := pointer(IOApic_Base);
  tmp^ := offset;
  tmp := pointer(IOApic_Base + $10);
  tmp^ := val;
end;

function read_ioapic_reg(offset: dword): dword;
var
  tmp: ^dword;
begin
  tmp := pointer(IOApic_Base);
  tmp^:= offset;
  tmp := pointer(IOApic_Base+ $10);
  Result := tmp^;
end;

function SpinLock(CmpVal, NewVal: UInt64; var addval: UInt64): UInt64; assembler;
asm
    cmp CPU_COUNT, 1
    je @break
  @spin:
    mov rax, CmpVal
    {$IFDEF LINUX} lock cmpxchg [rdx], rsi {$ENDIF}
    {$IFDEF WINDOWS} lock cmpxchg [r8], rdx {$ENDIF}
    pause
    jnz @spin
 @break:
end;

function GetApicId: Byte; inline;
begin
  Result := PDWORD(apicid_reg)^ shr 24;
end;

function GetApicBaseAddr: Pointer;
var
  basehigh, baselow: DWORD;
begin
  asm
    mov ecx, 1bh
    xor eax, eax
    xor edx, edx
    rdmsr
    mov baselow, eax
    mov basehigh, edx
  end ['ECX', 'EAX', 'EDX'];
  Result := Pointer(PtrUInt((baselow and $fffff000) or ((basehigh and $f) shr 32)));
end;


function is_apic_ready: Boolean;{$IFDEF ASMINLINE} inline; {$ENDIF}
var
  r: PDWORD;
begin
  r := Pointer(icrlo_reg) ;
  if (r^ and $1000) = 0 then
    Result := True
  else
    Result := False;
end;

procedure NOP;
asm
  nop;
  nop;
  nop;
end;

procedure EnableLint1;
var
 vector: ^DWORD;
begin
  vector := Pointer(lint1_reg);
  // lint1 triggers vector 2 as NMI (4)
  vector^ := 2 or (4 shl 8);
end;

procedure Delay(ms: LongInt);
var
  tmp : ^DWORD ;
begin
  tmp := Pointer (divide_reg);
  tmp^ := $b;
  tmp := Pointer(timer_init_reg); // set the count
  tmp^ := (LocalCpuSpeed * 1000)*ms; // the count is aprox.
  tmp := Pointer (timer_curr_reg); // wait for the counter
  while tmp^ <> 0 do
  begin
    NOP;
  end;
  // send the end of interruption
  tmp := Pointer(eoi_reg);
  tmp^ := 0;
end;

procedure DelayMicro(microseg: LongInt);
var
  tmp : ^DWORD ;
begin
  tmp := Pointer (divide_reg);
  tmp^ := $b;
  tmp := Pointer(timer_init_reg); // set the count
  tmp^ := LocalCpuSpeed*microseg;
  tmp := Pointer (timer_curr_reg); // wait for the counter
  while tmp^ <> 0 do
  begin
    NOP;
  end;
  tmp := Pointer(eoi_reg); // send the end of interruption
  tmp^ := 0;
end;

procedure RelocateAPIC;
asm
  mov ecx, 27
  mov edx, 0
//  mov eax, Apic_Base
  wrmsr
end;

const
  Level = $8000;
// TODO: all irq are sent to core #0
procedure IOApicIrqOn(Irq: Byte);
begin
  // from linux, set to level otherwise remote-IRR is not clear
  write_ioapic_reg(irq * 2 + $10, irq + BASE_IRQ + Level);
end;

// This code has been extracted from DelphineOS <delphineos.sourceforge.net>
// Return the CPU speed in Mhz
function CalculateCpuSpeed: Word;
var
  count_lo, count_hi, family, features: DWORD;
  speed: WORD;
begin
  asm
    mov eax, 1
    cpuid
    mov features, edx
  end ['EAX', 'EDX'];

  // we verify if there is timecounter
  if (features and $10) <> $10 then
  begin
    Result := 0;
    Exit
  end;

  asm
    mov eax , 1
    cpuid
    and eax , $0f00
    shr eax , 8
    mov family , eax
    in    al , 61h
    nop
    nop
    and   al , 0FEh
    out   61h, al
    nop
    nop
    mov   al , 0B0h
    out   43h, al
    nop
    nop
    mov   al , 0FFh
    out   42h, al
    nop
    nop
    out   42h, al
    nop
    nop
    in    al , 61h
    nop
    nop
    or    al , 1
    out   61h, al
    rdtsc
    add   eax, 3000000
    adc   edx, 0
    cmp   family, 6
    jb    @TIMER1
    add   eax, 3000000
    adc   edx, 0
  @TIMER1:
    mov   count_lo, eax
    mov   count_hi, edx
  @TIMER2:
    rdtsc
    cmp   edx, count_hi
    jb    @TIMER2
    cmp   eax, count_lo
    jb    @TIMER2
    in    al , 61h
    nop
    nop
    and   al , 0FEh
    out   61h, al
    nop
    nop
    mov   al , 80h
    out   43h, al
    nop
    nop
    in    al , 42h
    nop
    nop
    mov   dl , al
    in    al , 42h
    nop
    nop
    mov   dh , al
    mov   cx , -1
    sub   cx , dx
    xor   ax , ax
    xor   dx , dx
    cmp   cx , 110
    jb    @CPUS_SKP
    mov   ax , 11932
    mov   bx , 300
    cmp   family, 6
    jb    @TIMER3
    add   bx , 300
  @TIMER3:
    mul   bx
    div   cx
    push  ax
    push  bx
    mov   ax , dx
    mov   bx , 10
    mul   bx
    div   cx
    mov   dx , ax
    pop   bx
    pop   ax
  @CPUS_SKP:
    mov speed, ax
  end ['EAX', 'EDX', 'EBX', 'ECX'];

  if speed = 0 then
  begin
    speed := MAX_CPU_SPEED_MHZ;
  end;

  Result := speed;
end;

procedure ShutdownInQemu;
begin
  // the following code triggers a triple-fault
  asm
    lidt [$400]
    db $ff, $ff
  end;
end;

function read_rdtsc: QWORD;
var
  l, h: QWORD;
begin
  // TODO: to check why using eax does not work
  asm
    rdtsc
    mov l, rax
    mov h, rdx
  end ['RAX', 'RDX'];
  Result := QWORD(h shl 32) or (l and $ffffffff);
end;

function bit_test(Val: Pointer; pos: QWord): Boolean;
asm
  {$IFDEF WINDOWS} bt  [rcx], rdx {$ENDIF}
  {$IFDEF LINUX} bt [rdi], rsi {$ENDIF}
  jc  @True
  @False:
   mov rax , 0
   jmp @salir
  @True:
    mov rax , 1
  @salir:
end;

procedure bit_reset(Value: Pointer; Offset: QWord); assembler;
asm
  {$IFDEF WINDOWS} btr [rcx], rdx {$ENDIF}
  {$IFDEF LINUX} btr [rdi], rsi {$ENDIF}
end;

procedure bit_set(Value: Pointer; Offset: QWord); assembler;
asm
  {$IFDEF WINDOWS} bts [rcx], rdx {$ENDIF}
  {$IFDEF LINUX} bts [rdi], rsi {$ENDIF}
end;

// This function returns 32 if all bits are zero
function find_msb_set(value: DWORD): LongInt; assembler;
asm
  mov rax, 32
  bsf rax, rdi
end;

// change_sp() is only used to start executing PASCALMAIN
procedure change_sp(new_esp: Pointer); [nostackframe] assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  xor rbp, rbp
  mov rsp, new_esp
  ret
end;

procedure SwitchStack(sv: Pointer; ld: Pointer); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov [sv] , rbp
  mov rbp , [ld]
end;

type
  Int15h_info = record
    Base   : QWord;
    Length : QWord;
    tipe   : DWORD;
    Res    : DWORD;
  end;
  PInt15h_info = ^Int15h_info;

  PPVHentry = ^TPVHentry;
  TPVHentry = packed record
    Addr: qword;
    Size: qword;
    Tp: dword;
    res: dword;
  end;

  PBoote820Entry = ^TBoote820Entry;
  TBoote820Entry = packed record
    Addr: QWord;
    Size: QWord;
    tp: Dword;
  end;

const
  INT15H_TABLE = $30000;

var
  CounterID: LongInt;

function GetMemoryRegion(ID: LongInt; Buffer: PMemoryRegion): LongInt;
var
  Desc: PInt15h_info;
  DescMB: PPVHentry;
  DescMBe820: PBoote820Entry;
  mbp: ^QWORD;
begin
  Result := 0;
  if ID >= CounterID then
    Exit
  else
    Result := SizeOf(TMemoryRegion);
  case bootsig of
    SIG_BARE:
      begin
        Desc := Pointer(INT15H_TABLE + SizeOf(Int15h_info) * ID);
        Buffer.Base := Desc.Base;
        Buffer.Length := Desc.Length;
        Buffer.Flag := Desc.tipe;
      end;
    SIG_PVH:
      begin
        mbp := Pointer(sodpointer + PVH_MEMMAP_PADDR);
        DescMB := Pointer(PtrUInt(mbp^));
        Inc(DescMB, ID);
        Buffer.Base := DescMB.Addr;
        Buffer.Length := DescMB.Size;
        Buffer.Flag := DescMB.Tp;
      end;
    SIG_K64:
      begin
        DescMBe820 := Pointer(sodpointer + $2d0);
        Inc(DescMBe820, ID);
        Buffer.Base := DescMBe820.Addr;
        Buffer.Length := DescMBe820.Size;
        Buffer.Flag := DescMBe820.Tp;
      end;
  end;
end;

function GetNextUsableMemoryRegion(Curr: LongInt): LongInt;
var
  tmp: TMemoryRegion;
begin
  Result := 0;
  Inc(Curr);
  While GetMemoryRegion(Curr, @tmp) <> 0 do
  begin
    if tmp.Flag = MEM_AVAILABLE Then
    begin
      Result := Curr;
      Exit;
    end;
    Inc(Curr);
  end;
end;

const
  E820_TYPE_RAM = 1;

// Count available memory after $100000
procedure MemoryCounterInit;
var
  Magic: ^DWORD;
  mapaddr: ^QWORD;
  maplen: ^Byte;
  Desc: PInt15h_info;
  DescPVH: PPVHentry;
  DescE820: PBoote820Entry;
  Count: DWORD;
begin
  CounterID := 0;
  AvailableMemory := 0;
   case bootsig of
    SIG_BARE:
      begin
        Magic := Pointer(INT15H_TABLE);
        Desc := Pointer(INT15H_TABLE);
        while Magic^ <> $1234 do
        begin
          if (Desc.tipe = 1) and (Desc.Base >= $100000) then
            AvailableMemory := AvailableMemory + Desc.Length;
          Inc(Magic);
          Inc(Desc);
        end;
        AvailableMemory := AvailableMemory;
        CounterID := (QWord(Magic)-INT15H_TABLE);
        CounterID := CounterID div SizeOf(Int15h_info);
      end;
    SIG_PVH:
      begin
        maplen := sodpointer + PVH_MEMMAP_ENTRIES;
        mapaddr := sodpointer + PVH_MEMMAP_PADDR;
        DescPVH := Pointer(PtrUInt(mapaddr^));
        Count := maplen^;
        while count <> 0 do
        begin
          if (DescPVH.tp = E820_TYPE_RAM) and (DescPVH.addr >= $100000) then
            AvailableMemory := AvailableMemory + DescPVH.Size;
          Inc(DescPVH);
          Inc(CounterID);
          Dec(Count);
        end;
      end;
    SIG_K64:
      begin
        maplen := sodpointer + $1e8;
        DescE820 := Pointer(sodpointer + $2d0);
        Count := maplen^;
        while count <> 0 do
        begin
          if (DescE820.tp = E820_TYPE_RAM) and (DescE820.addr >= $100000) then
            AvailableMemory := AvailableMemory + DescE820.Size;
          Inc(DescE820);
          Inc(CounterID);
          Dec(Count);
        end;
      end;
   end;
end;

procedure Bcd_To_Bin(var val: LongInt); inline;
begin
  val := (val and 15) + ((val shr 4) * 10);
end;

// this is not used
procedure KVMInstallClock(PClock: PWallClock);
var
  l, h: DWORD;
begin
  l := (PTrUInt(PClock) and $ffffffff ) or 1;
  h := PTrUInt(PClock) shr 32;
  asm
    mov eax, l
    mov edx, h
    mov ecx, MSR_KVM_SYSTEM_TIME_NEW
    wrmsr
  end ['EAX', 'EDX', 'ECX'];
end;

procedure KVMSetStealClock;
var
  l, h: DWORD;
  PClock: PKVMStealTime;
begin
  PClock := @ToroStealClocks[GetCoreId];
  l := (PTrUInt(PClock) and $ffffffff) or 1;
  h := (PTrUInt(PClock) and $ffffffff00000000) shr 32;
  asm
    mov eax, l
    mov edx, h
    mov ecx, MSR_KVM_STEAL_TIME
    wrmsr
  end ['EAX', 'EDX', 'ECX'];
end;

function GetStealCPU: QWORD;
begin
  Result := ToroStealClocks[GetApicId].steal;
end;

Type
  PKVMClock = ^KVMClock;
  KVMClock = packed record
    version: DWORD;
    sec: DWORD;
    nsec: DWORD;
  end;

procedure KVMGetClock(Clock: PKVMClock);
var
  l, h: DWORD;
begin
  l := PTrUInt(Clock) and $ffffffff;
  h := PTrUInt(Clock) shr 32;
  asm
    mov eax, l
    mov edx, h
    mov ecx, MSR_KVM_WALL_CLOCK_NEW
    wrmsr
    sfence
  end ['EAX', 'EDX', 'ECX'];
end;

procedure Now(Data: PNow);
var
  Sec, Min, Hour: LongInt;
begin
  Sec  := (StartTime.sec + (ToroClock.system_time div 1000000000)) mod 86400;
  Min  := (Sec div 60) mod 60 + StartTime.Min;
  Hour := Sec div 3600 + StartTime.Hour;
  Sec := Sec mod 60;
  Data.Sec := Sec;
  Data.Min := min;
  Data.Hour := hour;
  // TODO: add year, month and day
  Data.Month:= 2;
  Data.Day := 27;
  Data.Year := 1987;
end;

function SecondsBetween(const ANow: TNow;const AThen: TNow): Longint;
var
  julnow, julthen, a1, a2: LongInt;
  NowYear, NowMonth: LongInt;
  ThenYear, ThenMonth: LongInt;
begin
  a1 := (14 - ANow.Month) div 12;
  a2 := (14 - AThen.Month) div 12;
  NowMonth:= ANow.Month + 12 * a1 - 3;
  ThenMonth:= AThen.Month + 12 * a2 - 3;
  NowYear:=  ANow.Year + 4800 - a1;
  ThenYear:=  AThen.Year + 4800 - a2;
  julnow := ANow.Day + ((153 * NowMonth+2) div 5) + 365*NowYear + (NowYear div 4) - (NowYear div 100) + (NowYear div 400);
  julthen := AThen.Day + ((153*ThenMonth+2) div 5) + 365*ThenYear + (ThenYear div 4) - (ThenYear div 100) + (ThenYear div 400);
  Result := (julnow - julthen ) * 3600 * 24 + Abs(ANow.Hour - AThen.Hour) * 3600 + Abs (ANow.Min -  AThen.Min) * 60 + Abs(ANow.Sec - AThen.Sec);
end;

{$IFDEF FPC}
procedure nolose3;  [public, alias: '__FPC_specific_handler'];
begin

end;
{$ENDIF}

procedure Interruption_Ignore; {$IFDEF FPC} [nostackframe]; assembler ; {$ENDIF}
asm
  db $48, $cf
end;

procedure Apic_IRQ_Ignore; {$IFDEF FPC} [nostackframe]; assembler ; {$ENDIF}
asm
  call eoi_apic
  db $48, $cf
end;

// Initialize SSE and SSE2 extensions
// Do this for every core
// TODO : Floating-Point exception is ignored
{$IFDEF FPC}
procedure SSEInit; assembler;
asm
  xor rax , rax
  // set OSFXSR bit
  mov rax, cr4
  or ah , 10b
  mov cr4 , rax
  xor rax , rax
  mov rax, cr0
  // clear MP and EM bit
  and al ,11111001b
  mov cr0 , rax
end;
{$ENDIF}
{$IFDEF DCC}
procedure SSEInit; assembler;
asm
  xor rax , rax
  // set OSFXSR bit
  mov eax, cr4
  or ah , 10b
  mov cr4 , eax
  xor rax , rax
  mov eax, cr0
  // clear MP and EM bit
  and al ,11111001b
  mov cr0 , eax
end;
{$ENDIF}

var
  esp_tmp: Pointer; // Pointer to Stack for each CPU during SMP Initialization
  start_stack: array [0..MAX_CPU-1] of array [1..size_start_stack] of Byte; // temporary stack for each CPU

{$IFDEF FPC}

procedure boot_confirmation;
var
  CpuID: Byte;
begin
  enable_local_apic;
  CpuID := GetApicID;
  InitGS;
  Cores[CPUID].InitConfirmation := True;
  Cores[CPUID].InitProc;
end;

// Stack for BSP
var
  stack : array[1..5000] of Byte ;

const
  pstack: Pointer = @stack[5000] ;

procedure InitCpu; assembler;
asm
  mov rax, Kernel_Data_Sel
  mov ss, ax
  mov es, ax
  mov ds, ax
  mov gs, ax
  mov fs, ax
  mov rsp, esp_tmp
  xor rbp, rbp
  sti
  call SSEInit
  call KVMSetStealClock
  call boot_confirmation
end;

// Entry point of PE64 EXE
// This procedure is executed in parallel by all CPUs when booting
procedure main; [public, alias: '_mainCRTStartup']; assembler;
asm
  cmp edx, 1987h
  je InitCpu
  mov rsp, pstack
  xor rbp, rbp
  mov sodpointer, rbx
  mov bootsig, rcx
  call KernelStart
end;
{$ENDIF}

// Boot CPU using IPI messages.
function InitCore(ApicID: Byte): Boolean;
begin
  Result := True;
  // wakeup the remote core with IPI-INIT
  send_apic_init(apicid);
  Delay(10);
  // send the first startup
  send_apic_startup(ApicID, 2);
  Delay(10);
  // remote CPU has read the IPI?
  if not is_apic_ready then
  begin
    Delay(100);
    if not is_apic_ready then
    begin
     Result := False;
     Exit;
    end;
  end;
  send_apic_startup(ApicID, 2);
  Delay(10);
  esp_tmp := Pointer(SizeUInt(esp_tmp) - size_start_stack);
end;

// Detect cores by using the MP table
// The algorithm assumes that the first structure
// is a p_mp_processor_entry and they are stored
// one after the other
procedure mp_apic_detect(table: p_mp_table_header);
var
  m: ^Byte;
  cp: p_mp_processor_entry ;
begin
  m := Pointer(PtrUInt(table) + SizeOf(mp_table_header));
  while (m^ = cpu_type) and (CPU_COUNT < MAX_CPU) do
  begin
    cp := Pointer(m);
    Inc(CPU_COUNT);
    Cores[cp.Apic_id].ApicID := cp.Apic_id;
    Cores[cp.Apic_id].Present := True;
    m := Pointer(PtrUInt(m)+SizeOf(mp_processor_entry));
    // boot core doesn't need initialization
    if (cp.flags and 2 ) = 2 then
    begin
      Cores[cp.Apic_id].CpuBoot := True;
      Cores[cp.Apic_id].InitConfirmation := True;
      Cores[cp.Apic_id].Present := True;
    end;
  end;
end;

// look for the ACPI version 1.4
procedure mp_table_detect;
var
  find: p_mp_floating_struct;
begin
  find := Pointer(0) ;
  while PtrUInt(find) < $fffff do
  begin
    if (find.signature[0]='_') and (find.signature[1]='M')
    and (find.signature [2] = 'P') and (find.signature[3] = '_') then
    begin
      if PtrUInt(find.phys) <> 0 then
      begin
        mp_apic_detect(Pointer(PtrUInt(find.phys)));
        Exit;
      end;
      Exit;
    end;
    Inc(find);
   end;
end;

// detect cores using MP's Intel table
procedure SMPInitialization;
var
  J: LongInt;
begin
  for J :=0 to MAX_CPU-1 do
  begin // clear fields
    Cores[J].Present := False;
    Cores[J].CPUBoot:= False;
    Cores[J].ApicID := 0;
    Cores[J].InitConfirmation := False;
    Cores[J].InitProc := nil;
  end;
  CPU_COUNT := 0;
  mp_table_detect;
  if CPU_COUNT = 0 then
    CPU_COUNT := 1;
  // setting boot core
  Cores[0].Present := True;
  Cores[0].CPUBoot := True;
  Cores[0].ApicID := GetApicID;
  Cores[0].InitConfirmation := True;
  // temporary stack used to initialize every Core
  esp_tmp := @start_stack[MAX_CPU-1][size_start_stack];
end;

var
  PML4_Table: PDirectoryPage;

// Refresh the TLB's Cache
procedure FlushCr3; assembler;
asm
  mov rax, PDADD
  {$IFDEF FPC} mov cr3, rax {$ENDIF}
  {$IFDEF DCC} mov cr3, eax {$ENDIF}
end;

// Set Page as cacheable
// "Add" points to the page, It's a multiple of 2MB (Page Size)
procedure SetPageCache(Add: Pointer);
var
  I_PML4,I_PPD,I_PDE: LongInt;
  PDD_Table, PDE_Table, Entry: PDirectoryPage;
  Page: QWord;
begin
  Page := QWord(Add);
  I_PML4:= Page div 512*1024*1024*1024;
  I_PPD := (Page div (1024*1024*1024)) mod 512;
  I_PDE := (Page div (1024*1024*2)) mod 512;
  Entry:= Pointer(SizeUInt(PML4_Table) + SizeOf(TDirectoryPageEntry)*I_PML4);
  PDD_Table := Pointer((entry.PageDescriptor shr 12)*4096);
  Entry := Pointer(SizeUInt(PDD_Table) + SizeOf(TDirectoryPageEntry)*I_PPD);
  PDE_Table := Pointer((Entry.PageDescriptor shr 12)*4096);
  // 2 MB page's entry
  // PCD bit is Reset --> Page In Cached
  Bit_Reset(Pointer(SizeUInt(PDE_Table) + SizeOf(TDirectoryPageEntry)*I_PDE), 4);
end;

// Set Page as not-cacheable
// "Add" is Pointer to page, It's a multiple of 2MB (Page Size)
procedure RemovePageCache(Add: Pointer);
var
  I_PML4,I_PPD,I_PDE: LongInt;
  PDD_Table, PDE_Table, Entry: PDirectoryPage;
  page: QWord;
begin
  page:= QWord(Add);
  I_PML4:= Page div 512*1024*1024*1024;
  I_PPD := (Page div (1024*1024*1024)) mod 512;
  I_PDE := (Page div (1024*1024*2)) mod 512;
  Entry:= Pointer(SizeUInt(PML4_Table) + SizeOf(TDirectoryPageEntry)*I_PML4);
  PDD_Table := Pointer((Entry.PageDescriptor shr 12)*4096);
  Entry := Pointer(SizeUInt(PDD_Table) + SizeOf(TDirectoryPageEntry)*I_PPD);
  PDE_Table := Pointer((Entry.PageDescriptor shr 12)*4096);
  // 2 MB page's entry
  // PCD bit is Reset --> Page is cached
  Bit_Set(Pointer(SizeUInt(PDE_Table) + SizeOf(TDirectoryPageEntry)*I_PDE),4);
end;


// Set Page as Read Only
// "Add" is Pointer to page, It's a multiple of 2MB (Page Size)
procedure SetPageReadOnly(Add: Pointer);
var
  I_PML4,I_PPD,I_PDE: LongInt;
  PDD_Table, PDE_Table, Entry: PDirectoryPage;
  Page: QWord;
begin
  Page := QWord(Add);
  I_PML4:= Page div 512*1024*1024*1024;
  I_PPD := (Page div (1024*1024*1024)) mod 512;
  I_PDE := (Page div (1024*1024*2)) mod 512;
  Entry:= Pointer(SizeUInt(PML4_Table) + SizeOf(TDirectoryPageEntry)*I_PML4);
  PDD_Table := Pointer((entry.PageDescriptor shr 12)*4096);
  Entry := Pointer(SizeUInt(PDD_Table) + SizeOf(TDirectoryPageEntry)*I_PPD);
  PDE_Table := Pointer((Entry.PageDescriptor shr 12)*4096);
  // 2 MB page's entry
  Bit_Reset(Pointer(SizeUInt(PDE_Table) + SizeOf(TDirectoryPageEntry)*I_PDE), 1);
end;

// NOTE: addr must be set as a write-back memory
procedure monitor(addr: Pointer; ext: DWORD; hint: DWORD);
begin
  if LargestMonitorLine <> 0 then
  begin
    asm
     mov rax, addr
     mov ecx, ext
     mov edx, hint
     monitor
    end ['RAX', 'ECX', 'EDX'];
  end;
end;

// NOTE: processor has to support mwait/monitor instrucctions
procedure mwait(ext: DWORD; hint: DWORD);
begin
  if LargestMonitorLine <> 0 then
  begin
    asm
      mov ecx, ext
      mov eax, hint
      mwait
    end ['ECX', 'EAX']
  // halt if mwait is not supported
  end else
  begin
    asm
     hlt
    end;
  end;
end;

// Check if Monitor/MWait is supported
procedure MWaitInit;
begin
  asm
    mov eax, 05h
    cpuid
    mov LargestMonitorLine, ebx
    mov SmallestMonitorLine, eax
  end ['EAX', 'EBX'];
end;

procedure hlt;assembler;
asm
  hlt
end;

procedure ReadBarrier;assembler;nostackframe;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
  lfence
end;

procedure ReadWriteBarrier;assembler;nostackframe;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
  lock add DWORD [rsp] - 4, 0
end;

procedure WriteBarrier;assembler;nostackframe;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
  sfence
end;

function GetKernelParam(I: LongInt): PChar;
var
  tmp: Pchar;
begin
  Result := nil;
  If I >= KernelParamCount then
    Exit;
  if I = 0 then
  begin
    Result := KernelParam;
    Exit;
  end;
  // only I > 0 cases
  tmp := KernelParam;
  while (I > 0) and (tmp < KernelParamEnd) do
  begin
    if tmp^ = #0 then
      Dec(I);
    Inc(tmp);
  end;
  Result := tmp;
end;

procedure ParseKernelParams;
var
  tmp: ^DWORD;
  Len: LongInt;
  p: PChar;
begin
  tmp := sodpointer + BOOT_CMDLINE_OFFSET[bootsig];
  p := PChar(PtrUInt(tmp^));
  KernelParam := Pointer(KERNEL_PARAM);
  Len := 0;
  while p^ <> #0 do
  begin
    Inc(Len);
    if (p^ = ',') or (p^ = ' ') then
    begin
      // ignore arguments with only spaces
      if Len = 1 Then
      begin
        Len := 0;
        Inc(p);
        Continue;
      end;
      KernelParam^ := #0;
      Len := 0;
      Inc(KernelParamCount)
    end
    else
      KernelParam^ := p^;
    Inc(KernelParam);
    Inc(p);
  end;
  KernelParam^ := #0;
  if Len > 0 then
    Inc(KernelParamCount);
  KernelParamEnd := KernelParam;
  KernelParam := Pointer(KERNEL_PARAM);
end;

procedure EnableNMI;
begin
  write_portb(read_portb($70) and $7F, $70);
  NOP;
end;

procedure ArchInit;
var
  I, Len: LongInt;
  clk: KVMClock;
begin
  idt_gates := Pointer(IDTADDRESS);
  FillChar(PChar(IDTADDRESS)^, SizeOf(TInteruptGate)*256, 0);
  InitGS;
  ParseKernelParams;
  MemoryCounterInit;
  PML4_Table := Pointer(PDADD);
  LocalCpuSpeed := PtrUInt(CalculateCpuSpeed);
  for I := 0 to 32 do
    CaptureInt(I, @Interruption_Ignore);
  CaptureInt(INTER_CORE_IRQ, @Apic_IRQ_Ignore);
  EnableInt;
  KVMInstallClock(@ToroClock);
  FillChar(PChar(@ToroStealClocks)^, sizeof(ToroStealClocks), 0);
  KVMSetStealClock;
  KVMGetClock(@clk);
  StartTime.Sec := clk.sec mod 86400;
  StartTime.Min := (StartTime.Sec  div 60) mod 60;
  StartTime.Hour := StartTime.Sec div 3600;
  StartTime.Sec := StartTime.Sec  mod 60;
  enable_local_apic;
  EnableLint1;
  SMPInitialization;
  SSEInit;
  MWaitInit;
end;

end.
