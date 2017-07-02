//
// Arch.pas
//
// This unit makes possible port Toro kernel to others architectures.
// The declared procedures here MUST BE the same for all architectures.
//
// Changes :
//
// 18/01/2017 Adding DisableInt() and RestoreInt().
// 11/12/2011 Fixed a bug at boot core initilization.
// 08/08/2011 Fixed bugs caused for a wrong convention calling understanding.
// 27/10/2009 Cache Managing Implementation.
// 10/05/2009 SMP Initialization moved to Arch.pas. Supports Multicore.
// 09/05/2009 Size of memory calculated using INT15H.
// 12/10/2008 RelocateApic  is not used for the moment.
// 12/01/2006 RelocateApic procedure, QEMU does not support the relocation of APIC register.
// 11/01/2006 Some modifications in Main procedure by Matias Vara.
// 28/12/2006 First version by Matias Vara.
//
// Copyright (c) 2003-2016 Matias Vara <matiasevara@gmail.com>
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

unit Arch;

{$I Toro.inc}

interface

const
  // Exceptions Types
  EXC_DIVBYZERO = 0;
  EXC_OVERFLOW = 4;
  EXC_BOUND = 5;
  EXC_ILLEGALINS = 6;
  EXC_DEVNOTAVA = 7;
  EXC_DF = 8;
  EXC_STACKFAULT = 12;
  EXC_GENERALP = 13;
  EXC_PAGEFAUL = 14;
  EXC_FPUE = 16;
 
  // Regions Memory Types
  MEM_AVAILABLE = 1;
  MEM_RESERVED = 2;

  // Max CPU speed in Mhz
  // if it fails to get the right value
  MAX_CPU_SPEED_MHZ = 2393;

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

  TCore = record
    ApicID: LongInt; // Core Identification
    Present: Boolean; // It's present?
    CPUBoot: Boolean;
    InitConfirmation: Boolean; // Synchronization variable between core to INIT-core
    InitProc: procedure; // Procedure to initialize the core
  end;

procedure bit_reset(Value: Pointer; Offset: QWord);
procedure bit_set(Value: Pointer; Offset: QWord); assembler;
function bit_test ( Val : Pointer ; pos : QWord ) : Boolean;
procedure change_sp (new_esp : Pointer ) ;
// only used in the debug unit to synchronize access to serial port
procedure Delay(milisec: LongInt);
procedure eoi;
function GetApicID: Byte;
function get_irq_master: Byte;
function get_irq_slave: Byte;
procedure hlt;
procedure IrqOn(irq: Byte);
procedure IrqOff(irq: Byte);
function is_apic_ready: Boolean ;
procedure NOP;
function read_portb(port: Word): Byte;
function read_rdtsc: Int64;
procedure send_apic_init (apicid : Byte) ;
procedure send_apic_startup (apicid , vector : Byte );
function SpinLock(CmpVal, NewVal: UInt64; var addval: UInt64): UInt64; assembler;
procedure SwitchStack(sv: Pointer; ld: Pointer);
procedure write_portb(Data: Byte; Port: Word);
procedure CaptureInt (int: Byte; Handler: Pointer);
procedure CaptureException(Exception: Byte; Handler: Pointer);
procedure ArchInit;
procedure Now (Data: PNow);
procedure Interruption_Ignore;
procedure IRQ_Ignore;
function PciReadDWORD(const bus, device, func, regnum: UInt32): UInt32;
function GetMemoryRegion (ID: LongInt ; Buffer : PMemoryRegion): LongInt;
procedure InitCore(ApicID: Byte);
procedure SetPageCache(Add: Pointer);
procedure RemovePageCache(Add: Pointer);
function SecondsBetween(const ANow: TNow;const AThen: TNow): LongInt;
procedure ShutdownInQemu;
procedure DelayMicro(microseg: LongInt);
procedure PciWriteWord (const bus, device, func, regnum, value: Word);
function read_portw(port: Word): Word;
function PciReadWORD(const bus, device, func, regnum: UInt32): Word;

const
  MP_START_ADD = $e0000; // we will start the search of mp_floating_point begin this address
  RESET_VECTOR = $467; // when the IPI occurs the procesor jumps here
  cpu_type = 0;
  apic_type = 2;
  MAX_CPU = 8;  // Number of max CPU support
  ALLOC_MEMORY_START = $800000; // Address Start of Alloc Memory
  KERNEL_IMAGE_START = $400000;
  PAGE_SIZE = 2*1024*1024; // 2 MB per Page
  HasCacheHandler: Boolean = True;
  HasException: Boolean = True;
  HasFloatingPointUnit : Boolean = True;

var
  CPU_COUNT: LongInt; // Number of CPUs detected while smp_init
  AvailableMemory: QWord; // Memory in the system
  // LocalCpuSpeed has the speed of the local CPU in Mhz
  // It is used to calculate the delays
  LocalCpuSpeed: Int64 = 0;
  StartTime: TNow;
  Cores: array[0..MAX_CPU-1] of TCore;
    
implementation

uses Kernel, Console;

const
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
  
  // IDT descriptors
  gate_syst = $8E;
  
  // Address of Page Directory
  PDADD = $100000;
  IDTADDRESS = $3020;
	
  // 64bits selector
  Kernel_Code_Sel = $18;
  Kernel_Data_Sel = $10;

  // minimal stack for initialization procedure, in bytes
  size_start_stack = 700;

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
    res: array[0..6] of DWORD ;
    size: Word ;
    count: Word ;
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

  //  AMD X86-64  interrupt gate
  TInteruptGate = record
    handler_0_15: Word;
    selector: Word;
    nu: Byte;
    tipe: Byte;
    handler_16_31: Word;
    handler_32_63: DWORD;
    res: DWORD;
  end;

  TInterruptGateArray = array[0..255] of TInteruptGate;
  PInterruptGateArray = ^TInterruptGateArray;
  p_intr_gate_struct = ^TInteruptGate;

  PDirectoryPage = ^TDirectoryPageEntry;
  TDirectoryPageEntry = record
    PageDescriptor: QWORD;
  end;

var
  idt_gates: PInterruptGateArray; // Pointer to IDT

// Put interruption gate in the idt
procedure CaptureInt(int: Byte; Handler: Pointer);
begin
  idt_gates^[int].handler_0_15 := Word(PtrUInt(Handler) and $ffff);
  idt_gates^[int].selector := kernel_code_sel;
  idt_gates^[int].tipe := gate_syst;
  idt_gates^[int].handler_16_31 := Word((PtrUInt(Handler) shr 16) and $ffff);
  idt_gates^[int].handler_32_63 := DWORD(PtrUInt(Handler) shr 32);
  idt_gates^[int].res := 0;
  idt_gates^[int].nu := 0;
end;	

procedure CaptureException(Exception: Byte; Handler: Pointer);
begin
  idt_gates^[Exception].handler_0_15 := Word(PtrUInt(Handler) and $ffff) ;
  idt_gates^[Exception].selector := kernel_code_sel;
  idt_gates^[Exception].tipe := gate_syst ;
  idt_gates^[Exception].handler_16_31 := Word((PtrUInt(Handler) shr 16) and $ffff);
  idt_gates^[Exception].handler_32_63 := DWORD(PtrUInt(Handler) shr 32);
  idt_gates^[Exception].res := 0 ;
  idt_gates^[Exception].nu := 0 ;
end;

// IO port access
procedure write_portb(Data: Byte; Port: Word); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
     {$IFDEF LINUX} mov dx, port {$ENDIF}
          mov al, data
          out dx, al
end;

// IO port access
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
  {$IFDEF DCC} push rsi {$ENDIF} // it is obvious that rsi should also be saved for FPC
  {$IFDEF LINUX} mov dx, port {$ENDIF}
	mov rsi, data // DX=port
        outsd
  {$IFDEF DCC} pop rsi {$ENDIF}
end;

procedure read_portd(Data: Pointer; Port: Word); {$IFDEF ASMINLINE} inline; {$ENDIF}
asm // RCX: data, RDX: port
  {$IFDEF DCC} push rdi {$ENDIF} // it is obvious that rdi should also be saved for FPC
        {$IFDEF LINUX} mov dx, port {$ENDIF}
	mov rdi, data // DX=port
	insd
  {$IFDEF DCC} pop rdi {$ENDIF}
end;

// Send init interrupt to apicid
// Used only during initialization procedure
procedure send_apic_init(apicid: Byte);
var
	icrl, icrh: ^DWORD;
begin
	icrl := Pointer(icrlo_reg);
	icrh := Pointer(icrhi_reg) ;
	icrh^ := apicid shl 24 ;
	// mode: init   , destination no shorthand
	icrl^ := $500;
end;

// Send the startup IPI for initialize for processor 
procedure send_apic_startup(apicid, vector: Byte);
var
  icrl, icrh: ^DWORD;
begin
  Delay(10);
  icrl := Pointer(icrlo_reg);
  icrh := Pointer(icrhi_reg) ;
  icrh^ := apicid shl 24 ;
  // mode: init   , destination no shorthand
  icrl^ := $600 or vector;
end;

// It implements atomic compare and change
function SpinLock(CmpVal, NewVal: UInt64; var addval: UInt64): UInt64; assembler;
asm
@spin:
  nop
  nop
  nop
  nop
  mov rax, cmpval
  {$IFDEF LINUX} lock cmpxchg [rdx], rsi {$ENDIF}
  {$IFDEF WINDOWS} lock cmpxchg [r8], rdx {$ENDIF}
  jnz @spin
end;

// Get local Apic id
function GetApicID: Byte; inline;
begin
  Result := PDWORD(apicid_reg)^ shr 24;
end;

// Read the IPI delivery status
// Check Delivery Status register
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

// Wait a number of miliseconds
// It uses the Local Apic
procedure Delay(milisec: LongInt);
var
  tmp : ^DWORD ;
begin
  tmp := Pointer (divide_reg);
  tmp^ := $b;
  tmp := Pointer(timer_init_reg); // set the count
  tmp^ := (LocalCpuSpeed * 1000)*milisec; // the count is aprox.
  tmp := Pointer (timer_curr_reg); // wait for the counter
  while tmp^ <> 0 do
  begin
    NOP;
  end;
  // send the end of interruption
  tmp := Pointer(eoi_reg);
  tmp^ := 0;
end;

// Wait a number of microseconds
// It uses the Local Apic
procedure DelayMicro(microseg: LongInt);
var
  tmp : ^DWORD ;
begin
  tmp := Pointer (divide_reg);
  tmp^ := $b;
  tmp := Pointer(timer_init_reg); // set the count
  tmp^ := LocalCpuSpeed*microseg; // the count is aprox.
  tmp := Pointer (timer_curr_reg); // wait for the counter
  while tmp^ <> 0 do
  begin
    NOP;
  end;
  // send the end of interruption
  tmp := Pointer(eoi_reg);
  tmp^ := 0;
end;



// Change the Address of Apic registers
procedure RelocateAPIC;
asm
  mov ecx, 27
  mov edx, 0
  mov eax, Apic_Base
  wrmsr
end;

const
  Status_Port : array[0..1] of Byte = ($20,$A0);
  Mask_Port : array[0..1] of Byte = ($21,$A1);
  PIC_MASK: array [0..7] of Byte =(1,2,4,8,16,32,64,128);
  
// move the irq of 0-15 to 31-46 vectors
procedure RelocateIrqs ;
asm
    mov   al , 00010001b
    out   20h, al
    nop
    nop
    nop
    out  0A0h, al
    nop
    nop
    nop
    mov   al , 20h
    out   21h, al
    nop
    nop
    nop
    mov   al , 28h
    out  0A1h, al
    nop
    nop
    nop
    mov   al , 00000100b
    out   21h, al
    nop
    nop
    nop
    mov   al , 2
    out  0A1h, al
    nop
    nop
    nop
    mov   al , 1
    out   21h, al
    nop
    nop
    nop
    out  0A1h, al
    nop
    nop
    nop

    mov   al , 0FFh
    out   21h, al
    mov   al , 0FFh
    out  0A1h, al
end;

// turn on  the irq
procedure IrqOn(irq: Byte);
begin
  if irq > 7 then
    write_portb(read_portb($a1) and (not pic_mask[irq-8]), $a1)
  else
    write_portb(read_portb($21) and (not pic_mask[irq]), $21);
end;

// turn off the irq
procedure IrqOff(irq: Byte);
begin
  if irq > 7 then
    write_portb(read_portb($a1) or pic_mask[irq-8], $a1)
  else
    write_portb(read_portb($21) or pic_mask[irq], $21);
end;

// send the end of interruption
procedure eoi;
begin
  write_portb($20, status_port[0]);
  write_portb($20, status_port[1]);
end;

// turn off all irqs
procedure all_irq_off;
begin
  write_portb($ff, mask_port[0]);
  write_portb($ff, mask_port[1]);
end;

// get the irq's number
function get_irq_master: Byte ;
begin
  write_portb($b, $20);
  NOP;
  Result := read_portb($20);
end;

function get_irq_slave : Byte ;
begin
  write_portb($b, $a0);
  NOP;
  Result := read_portb($a0);
end;

const 
  cmos_port_reg = $70 ;
  cmos_port_rw  = $71 ;

// write a cmos' register
procedure cmos_write(Data, Reg: Byte);
begin
  write_portb(Reg, cmos_port_reg);
  write_portb(Data, cmos_port_rw);
end;

// read a cmos' register
function cmos_read(Reg: Byte): Byte;
begin
	write_portb(Reg, cmos_port_reg);
	Result := read_portb(cmos_port_rw);
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
  end;

  // we verify if there is timecounter
  // if not we cannot calculate the speed so we exit
  if ((features and $10) <> $10 ) then
  begin
   result := 0;
   exit
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
  end;
  
  if speed = 0 then
  begin
    speed := MAX_CPU_SPEED_MHZ;
  end;

  result := speed;
end;

// Stop the execution of CPU
procedure hlt; assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  hlt
end;

// Turn off Qemu VM
// it is needed to add "-device isa-debug-exit,iobase=0xf4,iosize=0x04"
procedure ShutdownInQemu;
begin
  write_portb(0, $f4);
end;

// Get the rdtsc counter
// Beware of specific code due to qemu x64 which is not handling rdtsc instruction properly
function read_rdtsc: Int64;
var
  lw, hg: DWORD;
asm
  rdtsc
  mov lw, eax
  mov hg, edx
  mov eax, hg
  shl rax, 32
  add eax, lw
end;

// Next procedures aren't atomic
//
function bit_test(Val: Pointer; pos: QWord): Boolean;
asm
  {$IFDEF WINDOWS} bt  [rcx], rdx {$ENDIF}
  {$IFDEF LINUX} bt [rdi], rsi {$ENDIF}
  jc  @true
  @false:
   mov rax , 0
   jmp @salir
  @true:
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

procedure change_sp(new_esp: Pointer); assembler ;{$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov rsp, new_esp
  ret
end;

procedure SwitchStack(sv: Pointer; ld: Pointer); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov [sv] , rbp
  mov rbp , [ld]
end;

//------------------------------------------------------------------------------
// Memory Detection .From Int 15h information.
//------------------------------------------------------------------------------

type
  Int15h_info = record
    Base   : QWord;
    Length : QWord;
    tipe   : DWORD;
    Res    : DWORD;
  end;
  PInt15h_info = ^Int15h_info;

const
  INT15H_TABLE = $30000;

var
  CounterID: LongInt; // starts with CounterID = 1

// Return information about Memory Region
function GetMemoryRegion(ID: LongInt; Buffer: PMemoryRegion): LongInt;
var
  Desc: PInt15h_info;
begin
  if ID > CounterID then
    Result :=0
  else
    Result := SizeOf(TMemoryRegion);
  Desc := Pointer(INT15H_TABLE + SizeOf(Int15h_info) * (ID-1));
  Buffer.Base := Desc.Base;
  Buffer.Length := Desc.Length;
  Buffer.Flag := Desc.tipe;
end;

// Initialize Memory table. It uses information from bootloader.
// The bootloader uses INT15h.
// Usable memory is above 1MB
procedure MemoryCounterInit;
var
  Magic: ^DWORD;
  Desc: PInt15h_info;
begin
  CounterID:=0;
  AvailableMemory := 0;
  Magic := Pointer(INT15H_TABLE);
  Desc := Pointer(INT15H_TABLE);
  while Magic^ <> $1234 do
  begin
    if (Desc.tipe = 1) and (Desc.Base >= $100000) then
      AvailableMemory := AvailableMemory + Desc.Length;
    Inc(Magic);
    Inc(Desc);
  end;
  // Allocation starts at ALLOC_MEMORY_START
  AvailableMemory := AvailableMemory;
  CounterID := (QWord(Magic)-INT15H_TABLE);
  CounterID := counterId div SizeOf(Int15h_info);
end;

procedure Bcd_To_Bin(var val: LongInt); inline;
begin
  val := (val and 15) + ((val shr 4) * 10);
end;

// Now: Return the time from the CMOS
procedure Now(Data: PNow);
var
  Sec, Min, Hour,
  Day, Mon, Year: LongInt;
begin
  repeat
    Sec  := Cmos_Read(0);
    Min  := Cmos_Read(2);
    Hour := Cmos_Read(4);
    Day  := Cmos_Read(7);
    Mon  := Cmos_Read(8);
    Year := Cmos_Read(9);
  until Sec = Cmos_Read(0);
  Bcd_To_Bin(Sec);
  Bcd_To_Bin(Min);
  Bcd_To_Bin(Hour);
  Bcd_To_Bin(Day);
  Bcd_To_Bin(Mon);
  Bcd_To_Bin(Year);
  if 0 >= Mon then
  begin
    Mon := Mon + 12 ;
    Year := Year + 1;
  end;
  Data.Sec := sec;
  Data.Min := min;
  Data.Hour := hour;
  Data.Month:= Mon;
  Data.Day := Day;
  if (Year < 90) then
      Data.Year := 2000 + Year
  else
      Data.Year := 1900 + Year;
end;

// Calculate the number of seconds between two dates
function SecondsBetween(const ANow: TNow;const AThen: TNow): Longint;
var
  julnow, julthen, a1, a2: longint;
  NowYear, NowMonth: longint;
  ThenYear, ThenMonth: longint;
begin
  a1 := (14 - ANow.Month) div 12;
  a2 := (14 - AThen.Month) div 12;
  NowMonth:= ANow.Month + 12 * a1 - 3;
  ThenMonth:= AThen.Month + 12 * a2 - 3;
  NowYear:=  ANow.Year + 4800 - a1;
  ThenYear:=  AThen.Year + 4800 - a2;
  // we first calculate the julian date
  julnow := ANow.Day + ((153 * NowMonth+2) div 5) + 365*NowYear + (NowYear div 4) - (NowYear div 100) + (NowYear div 400);
  julthen := AThen.Day + ((153*ThenMonth+2) div 5) + 365*ThenYear + (ThenYear div 4) - (ThenYear div 100) + (ThenYear div 400);
  Result := (julnow - julthen ) * 3600 * 24 + Abs(ANow.Hour - AThen.Hour) * 3600 + Abs (ANow.Min -  AThen.Min) * 60 + Abs(ANow.Sec - AThen.Sec);
end;

{$IFDEF FPC}
procedure nolose; [public, alias: 'FPC_ABSMASK_DOUBLE'];
begin
end;

procedure nolose2; [public, alias: 'FPC_EMPTYINTF'];
begin
end;

procedure nolose3;  [public, alias: '__FPC_specific_handler'];
begin

end;

procedure nolose4;  [public, alias: 'FPC_DONEEXCEPTION'];
begin

end;


{$ENDIF}

// Procedures to capture unhandle interruptions
procedure Interruption_Ignore; {$IFDEF FPC} [nostackframe]; assembler ; {$ENDIF}
asm
  db $48, $cf
end;

// Ignoring Hardware interruption
procedure IRQ_Ignore; {$IFDEF FPC} [nostackframe]; assembler ; {$ENDIF}
asm
  call EOI;
  db $48, $cf
end;

// PCI bus access
const
 PCI_CONF_PORT_INDEX = $CF8;
 PCI_CONF_PORT_DATA  = $CFC;

function PciReadDword(const bus, device, func, regnum: UInt32): UInt32;
var
  Send: DWORD;
begin
  Send := $80000000 or (bus shl 16) or (device shl 11) or (func shl 8) or (regnum shl 2);
  write_portd(@Send, PCI_CONF_PORT_INDEX);
  read_portd(@Send, PCI_CONF_PORT_DATA);
  Result := Send;
end;

function PciReadWord(const bus, device, func, regnum: UInt32): Word;
var
  Send: DWORD;
  tmp: Word;
begin
  Send := $80000000 or (bus shl 16) or (device shl 11) or (func shl 8) or (regnum and $fc);
  write_portd(@Send, PCI_CONF_PORT_INDEX);
  tmp := read_portw(PCI_CONF_PORT_DATA);
  Result := (tmp shr ((regnum and 2) * 8 )) and $ffff;
end;

procedure PciWriteWord (const bus, device, func, regnum, value: Word);
var
  Send: DWORD;
begin
  Send := $80000000 or (bus shl 16) or (device shl 11) or (func shl 8) or (regnum and $fc);
  write_portd(@Send, PCI_CONF_PORT_INDEX);
  write_portw(value, PCI_CONF_PORT_DATA);
end;

// Initialization of the SSE and SSE2 Extensions
// Every Core need to perform this initialization
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

//------------------------------------------------------------------------------
//                               Multicore Initialization
//------------------------------------------------------------------------------

var
  esp_tmp: Pointer; // Pointer to Stack for each CPU during SMP Initilization
  start_stack: array[0..MAX_CPU-1] of array[1..size_start_stack] of Byte; // temporary stack for each CPU

{$IFDEF FPC}

// synchronization with bsp CPU
procedure boot_confirmation;
var
  CpuID: Byte;
begin
  CpuID := GetApicID;
  Cores[CPUID].InitConfirmation := True;
  // Local Kernel Initialization
  Cores[CPUID].InitProc;
end;

// Start stack for Initialization of CPU#0
var
  stack : array[1..5000] of Byte ;

const
  pstack: Pointer = @stack[5000] ;

// Initialize the CPU in SMP initialization
procedure InitCpu; assembler;
asm
  mov rax, Kernel_Data_Sel
  mov ss, ax
  mov es, ax
  mov ds, ax
  mov gs, ax
  mov fs, ax
  mov rsp, esp_tmp
  // load new Page Directory
  mov rax, PDADD
  {$IFDEF FPC} mov cr3, rax {$ENDIF}
  {$IFDEF DCC} mov cr3, eax {$ENDIF}
  xor rbp, rbp
  sti
  call SSEInit
  call boot_confirmation
end;

// Entry point of PE64 EXE
// The Toro bootloader is starting all CPUs(Cores) with this entry point
// ie: this procedure is executed in parallel by all CPUs when booting
procedure main; [public, alias: '_mainCRTStartup']; assembler;
asm
  mov rax, cr3 // Cannot remove this warning! using eax generates error at compile-time.
  cmp rax, 90000h  // rax = $100000 when executed the first time from the bootloader (debugged once using FPC version)
  je InitCpu
  mov rsp, pstack
  xor rbp, rbp
  call KernelStart
end;
{$ENDIF}

// Boot CPU using IPI messages.
// Warning this procedure must be do it just one time per CPU
procedure InitCore(ApicID: Byte);
var
  Attempt: LongInt;
begin
  // tray two times two wake up each core
  Attempt := 2;
  while Attempt > 0 do
  begin
    // wakeup the remote core with IPI-INIT
    send_apic_init(apicid);
    Delay(10);
    // send the first startup
    send_apic_startup(ApicID, 2);
    Delay(10);
    // remote CPU read the IPI?
    if not is_apic_ready then
    begin // some problem ?? we wait
      Delay(100);
      // Serious problem -> exit
      if not is_apic_ready then
        Exit;
    end;
    send_apic_startup(ApicID, 2);
    Delay(10);
    Dec(Attempt);
  end;
  esp_tmp := Pointer(SizeUInt(esp_tmp) - size_start_stack);
end;

// Detect APICs on MP table
procedure mp_apic_detect(table: p_mp_table_header);
var
  m: ^Byte;
  I: LongInt;
  tmp: Pointer;
  cp: p_mp_processor_entry ;
begin
  m := Pointer(SizeUInt(table) + SizeOf(mp_table_header));
  I := 0;
  while I < table.count do
  begin
    if (m^  = cpu_type) and (CPU_COUNT < MAX_CPU-1) then
    begin
    // I must do ^Byte > Pointer > p_mp_processor_entry
      tmp := m;
      cp := tmp;
      CPU_COUNT:=CPU_COUNT+1;
      Cores[cp.Apic_id].ApicID := cp.Apic_id;
      Cores[cp.Apic_id].Present := True;
      m := Pointer(SizeUInt(m)+SizeOf(mp_processor_entry));
      // boot core doesn't need initilization
      if (cp.flags and 2 ) = 2 then
      begin
        Cores[cp.Apic_id].CpuBoot := True ;
        Cores[cp.Apic_id].InitConfirmation := true;
	Cores[cp.Apic_id].Present := true;
      end;
    end else
    begin
      m := Pointer(SizeUInt(m)+SizeOf(mp_apic_entry));
    end;
    Inc(I);
  end;
end;

// search and read the Mp configuration table version 1.4, the begin of search is in $e000 address
procedure mp_table_detect;
var
  find: p_mp_floating_struct;
begin
  find := Pointer(MP_START_ADD) ;
  while SizeUInt(find) < $fffff do
  begin
    if (find.signature[0]='_') and (find.signature[1]='M') then
    begin
      if SizeUInt(find.phys) <> 0 then
      begin
        mp_apic_detect(Pointer(SizeUint(find.phys)));
        Exit;
      end
      else exit;
    end;
    Inc(find); // := find+1;
   end;
end;

//------------------------------------------------------------------------------
// Structures of ACPI table.
//------------------------------------------------------------------------------

type
  TAcpiRsdp = packed record
    Signature: array[0..7] of XChar;
    Checksum: Byte;
    oem_id:array[0..5] of Byte;
    Revision: Byte;
    rsdt_address: DWORD;
    Length: DWORD;
    xsdt_address: QWord;
    ext_checksum: Byte;
    Reserved: array[0..2] of Byte;
  end;
  PAcpiRsdp = ^TAcpiRsdp;

  TAcpiTableHeader = packed record
    Signature: array[0..3] of XChar;
    Length: DWORD;
    Revision: Byte;
    Checksum: Byte;
    oem_id: array[0..5] of XChar;
    oem_table_id : array[0..7] of XChar;
    oem_revision: DWORD;
    asl_compiler_id:array[0..3] of XChar;
    asl_compiler_revision: DWORD;
  end;
  PAcpiTableHeader = ^TAcpiTableHeader;

  TAcpiRstd = packed record
    Header: TAcpiTableHeader;
    Entry: array[0..8] of DWORD;
  end;
  PAcpiRstd = ^TAcpiRstd;

  TAcpiMadt = packed record
    Header: TAcpiTableHeader;
    ApicAddr: DWORD;
    Res: DWORD;
  end;
  PAcpiMadt = ^TAcpiMadt;

  TAcpiMadtEntry = packed record
    nType: Byte;
    Length: Byte;
  end;
  PAcpiMadtEntry = ^TAcpiMadtEntry;

  TAcpiMadtProcessor = packed record
    Header: TAcpiMadtEntry;
    AcpiId: Byte;
    ApicId: Byte;
    Flags: DWORD;
  end;
  PAcpiMadtProcessor = ^TAcpiMadtProcessor;

// search and read the ACPI table
procedure acpi_table_detect;
var
  Counter, J: LongInt;
  Entry: PAcpiMadtEntry;
  madt: PAcpiMadt;
  MadEnd: Pointer;
  P: PChar;
  Processor: PAcpiMadtProcessor;
  RSDP: PAcpiRsdp;
  RSTD: PAcpiRstd;
  TableHeader: PAcpiTableHeader;
begin
  P := Pointer($e0000);
  while p < Pointer($100000) do
  begin
    // looking for RSD sign
    if (p[0] = 'R') and (p[1]='S') and (p[2]='D') then
    begin
      RSDP :=  Pointer(p);
      // maybe some sing detection on RSTD
      RSTD := Pointer(QWord(RSDP.rsdt_address));
      // number of entries in table
      Counter:= (RSTD.Header.Length - SizeOf(TAcpiTableHeader)) div 4;
      for J := 0 to Counter-1 do
      begin
        TableHeader := Pointer(QWord(RSTD.Entry[j])); // table header
        // "APIC" signature
        if (TableHeader.Signature[0] = 'A') and (TableHeader.Signature[1] = 'P')  then
        begin
          madt := Pointer(TableHeader);
          MadEnd := Pointer(SizeUInt(madt) + TableHeader.Length);
          Entry := Pointer(SizeUInt(madt) + SizeOf(TAcpiMadt));
          while SizeUInt(Entry) < SizeUInt(MadEnd) do
          begin // that 's a new Processor.
            if Entry.nType=0 then
            begin
              Processor := Pointer(Entry);
              // Is Processor Enabled ??
              if Processor.flags and 1 = 1 then
              begin
                Inc(CPU_COUNT);
                Cores[Processor.apicid].ApicID := Processor.apicid;
                Cores[Processor.apicid].Present := True;
                // CPU#0 is a BOOT cpu
                if Processor.apicid = 0 then
                begin
                  Cores[Processor.apicid].CPUBoot := True;
                  Cores[Processor.apicid].InitConfirmation := true;
		  Cores[Processor.apicid].Present := true;
                end;
              end;
            end;
            Entry := Pointer(SizeUInt(Entry) + Entry.Length);
          end;
        end;
      end;
      Break;
    end;
    Inc(P, 16);
  end;
end;

// Detect all Cores using MP's Intel tables and ACPI Tables.
procedure SMPInitialization;
var
  J: LongInt;
begin
  // cleaning a bit
  for J :=0 to MAX_CPU-1 do
  begin // clear fields
    Cores[J].Present := False;
    Cores[J].CPUBoot:= False;
    Cores[J].ApicID := 0;
    Cores[J].InitConfirmation := False;
    Cores[J].InitProc := nil;
  end;
  CPU_COUNT := 0;
  acpi_table_detect; // ACPI detection
  if CPU_COUNT = 0 then
    mp_table_detect; // if cpu_count is zero then use a MP Tables
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

//------------------------------------------------------------------------------
// Paging and Cache Manager
//------------------------------------------------------------------------------

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
// "Add" is Pointer to page, It's a multiple of 2MB (Page Size)
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

// Cache Manager Initialization
procedure CacheManagerInit;
var
  Page: Pointer;
begin
  Page := nil;
  PML4_Table := Pointer(PDADD);
  // first two pages aren't cacheable (0-2*PAGE_SIZE)
  RemovePageCache(Page);
  Page := Pointer(SizeUInt(Page) + PAGE_SIZE);
  RemovePageCache(Page);
  // The whole kernel is cacheable from bootloader
  FlushCr3;
end;

// Architecture's variables initialization
procedure ArchInit;
var
  I: LongInt;
begin
  // the bootloader creates the idt
  idt_gates := Pointer(IDTADDRESS);
  FillChar(PChar(IDTADDRESS)^, SizeOf(TInteruptGate)*256, 0);
  RelocateIrqs;
  MemoryCounterInit;
  // cache Page structures
  CacheManagerInit;
  // CPU speed in Mhz
  LocalCpuSpeed := PtrUInt(CalculateCpuSpeed);
  IrqOn(2);
  // hardware Interruptions
  for I := 33 to 47 do
    CaptureInt(I, @IRQ_Ignore);
  // CPU Exceptions
  for I := 0 to 32 do
    CaptureInt(I, @Interruption_Ignore);
  EnableInt;
  Now(@StartTime);
  SMPInitialization;
  // initialization of Floating Point Unit
  SSEInit;
end;

end.

