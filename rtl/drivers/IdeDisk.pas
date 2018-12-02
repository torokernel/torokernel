//
// IdeDisk.pas
//
// This unit contains the driver ATA disks.
//
// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
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

unit IdeDisk;

interface

{$I ..\Toro.inc}
{$IFDEF EnableDebug}
//{$DEFINE DebugIdeDisk}
{$ENDIF}

uses
 {$IFDEF EnableDebug} Debug, {$ENDIF}
  Console, Arch, FileSystem, Process;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}

const
  MAX_ATA_CONTROLLER= 4; // number of supported drivers
  MAX_SATA_DISK = 32;
  MAX_ATA_MINORS = 10;
  NOT_FILESYSTEM = $ff;

  // ATA Commands
  ATA_IDENTIFY = $EC;
  ATA_WRITE = $30;
  ATA_READ = $20;

  // ATA Driver Type
  MASTER = 0;
  SLAVE = 1;

  // size of physic blocks
  BLKSIZE = 512;

  // nameing interface
  ATANAMES : array[0..3] of AnsiString = ('ATA0', 'ATA1', 'ATA2', 'ATA3');

  // ATA Ports
  ATA_DATA = 0;
  ATA_ERROR = 1;
  ATA_COUNT = 2;
  ATA_SECTOR = 3;
  ATA_CYLLOW = 4;
  ATA_CYLHIG = 5;
  ATA_DRIVHD = 6;
  ATA_CMD_STATUS = 7;

type
  PIDEBlockDisk = ^TIDEBlockDisk;
  PIDEController = ^TIDEController;
  PPartitionEntry = ^TPartitionEntry;

  TIDEBlockDisk = record
    StartSector : LongInt;
    Size: LongInt;
    FsType: LongInt;
    FileDesc: TFileBlock;
    Next: PIDEBlockDisk;
  end;

  TIDEController = record
    IOPort: LongInt;
    IRQ: LongInt;
    IrqReady: Boolean;
    IrqHandler: Pointer;
    Driver: TBlockDriver;
    Minors: array[0..MAX_ATA_MINORS-1] of TIDEBlockDisk;
  end;

  DriverId = record
    config         : word;    // General configuration (obselete)
    cyls           : word;    // Number of cylinders
    reserved2      : word;    // Specific configuration
    heads          : word;    // Number of logical heads
    track_Bytes    : word;    // Obsolete
    sector_Bytes   : word;    // Obsolete
    sectors        : word;    // Number of logical sectors per logical track
    vendor0        : word;    // vendor unique
    vendor1        : word;    // vendor unique
    vendor2        : word;    // vendor unique
    serial_no      : array[1..20] of XChar;    // Serial number
    buf_type       : word;    // Obsolete
    buf_size       : word;    // 512 Byte increments; 0 = not_specified
    ecc_Bytes      : word;    // Obsolete
    fw_rev         : array[1..8] of XChar;      // Firmware revision
    model          : array[1..40] of XChar;     // Model number
    max_mulsect    : Byte;    // read/write multiple support
    vendor3        : Byte;    // vendor unique
    dword_io       : word;    // 0 = not_implemented; 1 = implemented
    vendor4        : Byte;    // vendor unique
    capability     : Byte;    // bits 0:DMA 1:LBA 2:IORDYsw 3:IORDYsup
    reserved50     : word;    // reserved (word 50)
    vendor5        : Byte;    // vendor unique
    tPIO           : Byte;    // 0=slow, 1=medium, 2=fast
    vendor6        : Byte;    // vendor unique
    tDMA           : Byte;    // vitesse du DMA ; 0=slow, 1=medium, 2=fast }
    field_valid    : word;    // bits 0:cur_ok 1:eide_ok
    cur_cyls       : word;    // cylindres logiques
    cur_heads      : word;    // tetes logique
    cur_sectors    : word;    // secteur logique par piste
    cur_capacity0  : word;    // nombre total de secteur logique
    cur_capacity1  : word;    // 2 words, misaligned int
    multsect       : Byte;    // compteur secteur multiple courrant
    multsect_valid : Byte;    // quand (bit0==1) multsect is ok
    lba_capacity   : dword;   // nombre total de secteur
    dma_1word      : word;    // informations sur le DMA single-word
    dma_mword      : word;    // multiple-word dma info
    eide_pio_modes : word;    // bits 0:mode3 1:mode4
    eide_dma_min   : word;    // min mword dma cycle time (ns)
    eide_dma_time  : word;    // recommended mword dma cycle time (ns)
    eide_pio       : word;    // min cycle time (ns), no IORDY
    eide_pio_iordy : word;    // min cycle time (ns), with IORDY
    word69         : word;
    word70         : word;
    word71         : word;
    word72         : word;
    word73         : word;
    word74         : word;
    word75         : word;
    word76         : word;
    word77         : word;
    word78         : word;
    word79         : word;
    word80         : word;
    word81         : word;
    command_sets   : word;    // bits 0:Smart 1:Security 2:Removable 3:PM
    word83         : word;    // bits 14:Smart Enabled 13:0 zero
    word84         : word;
    word85         : word;
    word86         : word;
    word87         : word;
    dma_ultra      : word;
    word89         : word;
    word90         : word;
    word91         : word;
    word92         : word;
    word93         : word;
    word94         : word;
    word95         : word;
    word96         : word;
    word97         : word;
    word98         : word;
    word99         : word;
    word100        : word;
    word101        : word;
    word102        : word;
    word103        : word;
    word104        : word;
    word105        : word;
    word106        : word;
    word107        : word;
    word108        : word;
    word109        : word;
    word110        : word;
    word111        : word;
    word112        : word;
    word113        : word;
    word114        : word;
    word115        : word;
    word116        : word;
    word117        : word;
    word118        : word;
    word119        : word;
    word120        : word;
    word121        : word;
    word122        : word;
    word123        : word;
    word124        : word;
    word125        : word;
    word126        : word;
    word127        : word;
    security       : word;    // bits 0:support 1:enable 2:locked 3:frozen
    reserved       : array[1..127] of word;
  end;

  TPartitionEntry = record
    boot: Byte;
    BeginHead: Byte;
    BeginSectCyl: word;
    pType: Byte;
    EndHead: Byte;
    EndSecCyl: word;
    FirstSector: dword;
    Size: dword;
  end;

var
  ATAControllers: array[0..MAX_ATA_CONTROLLER-1] of TIDEController;

procedure ATASelectDisk(Ctr: PIDEController; Drv: LongInt); inline;
begin
  if Drv < 5 then
    Drv := $a0
  else
    Drv := $b0;
  write_portb(Drv, Ctr.IOPort+ATA_DRIVHD);
end;

procedure ATASendCommand(Ctr: PIDEController; Cmd: LongInt); inline;
begin
  DisableInt;
  write_portb(Cmd, Ctr.IOPort+ATA_CMD_STATUS);
  RestoreInt;
end;

function ATAWork(Ctr: PIDEController): Boolean; inline;
begin
  Result := read_portb(Ctr.IOPort+ATA_CMD_STATUS) <> $ff;
end;

function ATABusy(Ctr: PIDEController): Boolean; inline;
var
  Temp: Byte;
begin
  Temp := read_portb(Ctr.IOPort+ATA_CMD_STATUS);
  Result := (Temp and (1 shl 7)) <> 0;
end;

function ATAError(Ctr: PIDEController): Boolean; inline;
var
  Temp: Byte;
begin
  Temp := read_portb(Ctr.IOPort+ATA_CMD_STATUS);
  Result := (Temp and 1)  <> 0;
end;

function ATADataReady (Ctr:PIDEController): Boolean; inline;
var
  Temp: Byte;
begin
  Temp := read_portb(Ctr.IOPort+ATA_CMD_STATUS);
  Result := (Temp and (1 shl 3)) <> 0;
end;

procedure ATAIn(Buffer: Pointer; IOPort: LongInt);
asm // RCX: Buffer, RDX: IOPort
   push rdi
  {$IFDEF LINUX} mov edx, IOPort {$ENDIF}
  mov rdi, Buffer
  add rdx, ATA_DATA
  mov rcx, 256
  rep insw
  pop rdi
end;

procedure ATAOut(Buffer: Pointer; IOPort: LongInt);
asm // RCX: Buffer, RDX: IOPort
  push rsi
  {$IFDEF LINUX} mov edx, IOPort {$ENDIF}
  mov rsi, Buffer
  add rdx, ATA_DATA
  mov rcx, 256
  rep outsw
  pop rsi
end;

procedure ATAPrepare(Ctr:PIDEController;Drv: LongInt;Sector: LongInt;count: LongInt);
var
 lba1, lba2, lba3, lba4: Byte;
begin
  DisableInt;
  lba1 := Sector and $FF;
  lba2 := (Sector shr 8) and $FF;
  lba3 := (Sector shr 16) and $FF;
  lba4 := (Sector shr 24) and $F;
  write_portb(Byte(count),Ctr.IOPort+ATA_COUNT);
  write_portb(lba1,Ctr.IOPort+ATA_SECTOR);
  write_portb(lba2,Ctr.IOPort+ATA_CylLow);
  write_portb(lba3,Ctr.IOPort+ATA_CylHig);
  if Drv < 5 then
    Drv := $a0
  else
    Drv := $b0;
  write_portb(lba4 or Byte(drv) or $40,Ctr.IOPort+ATA_DRIVHD);
  RestoreInt;
end;

procedure ATADetectPartition(Ctr: PIDEController; Minor: LongInt);
var
  I: LongInt;
  Buff: array[0..511] of Byte;
  Entry: PPartitionEntry;
begin
  ATAPrepare(Ctr,Minor,0,1);
  ATASendCommand(Ctr,ATA_READ);
  while AtaBusy(Ctr) do
    NOP;
  if not AtaError(Ctr) and ATADataReady(Ctr) then
  begin
    ATAIn(@Buff[0], Ctr.IOPort);
    if (Buff[511] = $AA) and (Buff[510] = $55) then
    begin
      Entry:= @Buff[446];
      for I := 1 to 4 do
      begin
        if Entry.pType <> 0 then
        begin
          Ctr.Minors[Minor+I].StartSector:= Entry.FirstSector;
          Ctr.Minors[Minor+I].Size:= Entry.Size;
          Ctr.Minors[Minor+I].FsType:= Entry.pType;
          Ctr.Minors[Minor+I].FileDesc.BlockDriver:= @Ctr.Driver;
          Ctr.Minors[Minor+I].FileDesc.Minor:=Minor+I;
          Ctr.Minors[Minor+I].FileDesc.BlockSize:= BLKSIZE;
          Ctr.Minors[Minor+I].FileDesc.Next:=nil;
          WriteConsoleF('IdeDisk: /V', []);
          WriteConsoleF(ATANames[Ctr.Driver.Major], []);
          WriteConsoleF('/n, Minor: /V%d/n, Size: /V%d/n Mb, Type: /V%d/n\n',[Minor+I,Entry.Size div 2048,Entry.pType]);
          {$IFDEF DebugIdeDisk} WriteDebug('ATADetectPartition: Controller: %d, Disk: %d --> Ok\n', [Ctr.Driver.Major, Minor+I]); {$ENDIF}
        end;
        Inc(Entry);
      end;
    end;
  end;
end;

procedure ATADetectController;
var
  ControllerNo, DriveNo: LongInt;
  ATA_Buffer: DriverId;
begin
  for ControllerNo := 0 to 1 do
  begin
    {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - ATAWork Controller: %d\n', [ControllerNo]); {$ENDIF}
    if not ATAWork(@ATAControllers[ControllerNo]) then
      Continue;
    for DriveNo := MASTER to SLAVE do
    begin
      {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - ATASelectDisk Controller: %d Disk: %d\n', [ControllerNo, DriveNo]); {$ENDIF}
      ATASelectDisk(@ATAControllers[ControllerNo], DriveNo*5);
      {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - ATASendCommand ATA_IDENTIFY Controller: %d Disk: %d\n', [ControllerNo, DriveNo]); {$ENDIF}
      ATASendCommand(@ATAControllers[ControllerNo], ATA_IDENTIFY);
      {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - ATABusy Controller: %d Disk: %d\n', [ControllerNo, DriveNo]); {$ENDIF}
      while ATABusy(@ATAControllers[ControllerNo]) do
        NOP;
      {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - ATADataReady: Controller: %d Disk: %d\n', [ControllerNo, DriveNo]); {$ENDIF}
      if ATADataReady(@ATAControllers[ControllerNo]) and not ATAError(@ATAControllers[ControllerNo]) then
      begin
        {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - Controller: %d, Disk: %d --> Ok\n', [ControllerNo, DriveNo]); {$ENDIF}
        ATAIn(@ATA_Buffer, ATAControllers[ControllerNo].IOPort);
        ATAControllers[ControllerNo].Minors[DriveNo*5].StartSector:= 0;
        ATAControllers[ControllerNo].Minors[DriveNo*5].Size:= ATA_Buffer.LBA_Capacity;
        ATAControllers[ControllerNo].Minors[DriveNo*5].FSType:= NOT_FILESYSTEM;
        ATAControllers[ControllerNo].Minors[DriveNo*5].FileDesc.BlockDriver:= @ATAControllers[ControllerNo].Driver;
        ATAControllers[ControllerNo].Minors[DriveNo*5].FileDesc.Minor:= DriveNo*5;
        ATAControllers[ControllerNo].Minors[DriveNo*5].FileDesc.BlockSize:= BLKSIZE;
        ATAControllers[ControllerNo].Minors[DriveNo*5].FileDesc.Next:= nil;
        {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - Controller: %d, Disk: %d --> Ok\n', [ControllerNo, DriveNo*5]); {$ENDIF}
        WriteConsoleF('IdeDisk: /V', []);
        WriteConsoleF(ATANames[ATAControllers[ControllerNo].Driver.Major], []);
        WriteConsoleF('/n, Minor: /V%d/n, Size: /V%d/n Mb, Type: /V%d/n\n', [DriveNo*5, ATA_Buffer.LBA_Capacity div 2048, NOT_FILESYSTEM]);
        ATADetectPartition(@ATAControllers[ControllerNo], DriveNo*5);
      end
      {$IFDEF DebugIdeDisk}
      else
        WriteDebug('ATADetectController - Controller: %d, Disk: %d --> Fault\n', [ControllerNo, DriveNo])
      {$ENDIF}
    end;
    // Registering the Controller and the Resources
    {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - Before RegisterBlockDriver Controller: %d\n', [ControllerNo]); {$ENDIF}
    RegisterBlockDriver(@ATAControllers[ControllerNo].Driver);
    {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - After RegisterBlockDriver Controller: %d\n', [ControllerNo]); {$ENDIF}
  end;
  {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - Done.\n', []); {$ENDIF}
end;

var
  ATA0onCPUID: Longint;

procedure ATA0IrqDelivery; forward;

procedure ATADedicate(Driver:PBlockDriver;CPUID: LongInt);
var
  I: LongInt;
begin
  for I := 0 to MAX_ATA_MINORS-1 do
  begin
    if ATAControllers[Driver.Major].Minors[I].FsType = 0 then
      Continue;
    DedicateBlockFile(@ATAControllers[Driver.Major].Minors[I].FileDesc, CPUID);
    {$IFDEF DebugIdeDisk} WriteDebug('IdeDisk: Dedicate Controller %d ,Disk: %q to CPU %d\n', [Int64(ATAControllers[Driver.Major].Minors[I].FileDesc.Minor), Driver.Major, CPUID]); {$ENDIF}
    IrqOn(ATAControllers[Driver.Major].IRQ);
    if CPUID <> 0 then
    begin
      {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - After Irq_On Controller: %d\n', [Driver.Major]); {$ENDIF}
      // TODO: to change in the case of ATA1
      ATA0onCPUID := CPUID;
      CaptureInt(ATAControllers[Driver.Major].IRQ+32, @ATA0IrqDelivery);
      // 76 is the interruption vector for the ipi
      CaptureInt(76, ATAControllers[Driver.Major].IrqHandler);
     {$IFDEF DebugIdeDisk} WriteDebug('ATADetectController - After CaptureInt Controller: %d\n', [Driver.Major]); {$ENDIF}
    end
    else
    begin
      CaptureInt(ATAControllers[Driver.Major].IRQ+32, ATAControllers[Driver.Major].IrqHandler);
    end;
  end;
end;

procedure ATAHandler(Controller: LongInt);
begin
  ATAControllers[Controller].Driver.WaitOn.State := tsReady;
  {$IFDEF DebugIdeDisk} WriteDebug('IdeDisk: ATA0 Irq Captured, Thread Wake Up: #%h, Ctr: %d\n', [PtrUInt(ATAControllers[Controller].Driver.WaitOn), Controller]); {$ENDIF}
  eoi;
end;

procedure ATA0IrqDelivery; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
asm
  // save registers
  push rbp
  push rax
  push rbx
  push rcx
  push rdx
  push rdi
  push rsi
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  // protect the stack
  mov r15 , rsp
  mov rbp , r15
  sub r15 , 32
  mov  rsp , r15
  mov ecx, ATA0onCPUID
  mov edx, 76
  call send_apic_int
  call eoi
  mov rsp , rbp
  // restore the registers
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rsi
  pop rdi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  pop rbp
  db $48
  db $cf
end;

procedure ATA0IrqHandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
asm
  {$IFDEF DCC} .noframe {$ENDIF}
  // save registers
  push rbp
  push rax
  push rbx
  push rcx
  push rdx
  push rdi
  push rsi
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  // protect the stack
  mov r15 , rsp
  mov rbp , r15
  sub r15 , 32
  mov  rsp , r15
  xor edi , edi
  Call ATAHandler
  mov rsp , rbp
  // restore the registers
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rsi
  pop rdi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  pop rbp
  db $48
  db $cf
end;

procedure ATA1IrqHandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
asm
  {$IFDEF DCC} .noframe {$ENDIF}
  // save registers
  push rbp
  push rax
  push rbx
  push rcx
  push rdx
  push rdi
  push rsi
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  // protect the stack
  mov r15 , rsp
  mov rbp , r15
  sub r15 , 32
  mov  rsp , r15
  mov edi , 1
  Call ATAHandler
  mov rsp , rbp
  // restore the registers
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rsi
  pop rdi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  pop rbp
  db $48
  db $cf
end;

function ATAReadBlock(FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
var
  ReadCount: LongInt;
  Ctr: PIDEController;
begin
  GetDevice(FileDesc.BlockDriver);
  Ctr := @ATAControllers[FileDesc.BlockDriver.Major];
  Block := Block + Ctr.Minors[FileDesc.Minor].StartSector;
  ReadCount:= 0;
  Ctr.Driver.WaitOn.state := tsSuspended;
  ATAPrepare(Ctr,FileDesc.Minor,Block,Count);
  ATASendCommand(Ctr,ATA_READ);
  {$IFDEF DebugIdeDisk} WriteDebug('ATAReadBlock: prepared and commands sent, Block: %d, Count: %d, Buffer: %h\n', [Block, Count, PtrUInt(Buffer)]); {$ENDIF}
  repeat
    SysThreadSwitch;
    if not ATADataReady(Ctr) or ATAError(Ctr) then
      Break;
    Inc(ReadCount);
    if ReadCount <> Count then
      Ctr.Driver.WaitOn.state := tsSuspended;
    ATAIn(Buffer, Ctr.IOPort);
    Buffer := Pointer(PtrUInt(Buffer) + 512);
  until ReadCount = Count;
  Result := ReadCount;
  FreeDevice(FileDesc.BlockDriver);
  {$IFDEF DebugIdeDisk} WriteDebug('ATAReadBlock:, Handle: %h, Begin Sector: %d, End Sector: %d\n', [PtrUint(FileDesc), Block, Block + ReadCount]); {$ENDIF}
end;

function ATAWriteBlock(FileDesc: PFileBlock; Block,Count: LongInt; Buffer: Pointer): LongInt;
var
  ncount: LongInt;
  Ctr: PIDEController;
begin
  GetDevice(FileDesc.BlockDriver);
  Ctr:= @ATAControllers[FileDesc.BlockDriver.Major];
  Inc(Block, Ctr.Minors[FileDesc.Minor].StartSector);
  ncount := 0;
  Ctr.Driver.WaitOn.state := tsSuspended;
  ATAPrepare(Ctr,FileDesc.Minor,Block,Count);
  ATASendCommand(Ctr,ATA_WRITE);
  {$IFDEF DebugIdeDisk} WriteDebug('ATAWriteBlock: prepared and commands sent, Block: %d, Count: %d, Buffer: %h\n', [Block, Count, PtrUInt(Buffer)]); {$ENDIF}
  repeat
    DisableInt;
    FileDesc.BlockDriver.WaitOn.state := tsSuspended;
    ATAOut(Buffer, Ctr.IOPort);
    RestoreInt;
    SysThreadSwitch;
    if ATAError(Ctr) then
    begin
      {$IFDEF DebugIdeDisk} WriteDebug('IdeDisk: ATAWriteBlock, error writting Block %d\n', [Block+ncount]); {$ENDIF}
      Break;
    end;
    Buffer:= Pointer(PtrUInt(Buffer)+512);
    Inc(ncount);
  until ncount = Count;
  Result := ncount;
  FreeDevice(FileDesc.BlockDriver);
  {$IFDEF DebugIdeDisk} WriteDebug('IdeDisk: ATAWriteBlock, Handle: %d, Begin Sector: %d, End Sector: %d\n', [PtrUInt(FileDesc), Block, Block+Ncount]); {$ENDIF}
end;

procedure IDEInit;
begin
  WriteConsoleF('Looking for ATA-IDE Disk ...\n',[]);
  ATAControllers[0].IOPort := $1f0;
  ATAControllers[0].IRQ := 14;
  ATAControllers[0].IrqHandler := @ATA0IrqHandler;
  ATAControllers[0].Driver.WaitOn := nil;
  ATAControllers[0].Driver.Busy := False;
  ATAControllers[0].Driver.Name := ATANAMES[0];
  ATAControllers[0].Driver.Major := 0;
  ATAControllers[0].Driver.CPUID := -1;
  ATAControllers[0].Driver.Dedicate := @ATADedicate;
  ATAControllers[0].Driver.ReadBlock := @ATAReadBlock;
  ATAControllers[0].Driver.WriteBlock := @ATAWriteBlock;
  ATAControllers[0].Driver.Next := nil;
  ATAControllers[1].IOPort:= $170;
  ATAControllers[1].IRQ := 15;
  ATAControllers[1].IrqHandler := @ATA1IrqHandler;
  ATAControllers[1].Driver.WaitOn := nil;
  ATAControllers[1].Driver.Busy := False;
  ATAControllers[1].Driver.Name := ATANAMES[1];
  ATAControllers[1].Driver.Major := 1;
  ATAControllers[1].Driver.CPUID := -1;
  ATAControllers[1].Driver.Dedicate := @ATADedicate;
  ATAControllers[1].Driver.ReadBlock := @ATAReadBlock;
  ATAControllers[1].Driver.WriteBlock := @ATAWriteBlock;
  ATAControllers[1].Driver.Next := nil;
  ATADetectController;
end;

procedure IdeDiskInit;
var
  I, J: LongInt;
begin
  for I := 0 to MAX_ATA_CONTROLLER-1 do
  begin
    ATAControllers[I].IOPort := 0;
    for J := 0 to MAX_ATA_MINORS-1 do
      ATAControllers[I].Minors[J].Fstype := 0;
  end;
  IDEInit;
end;

initialization
  IdeDiskInit;

end.
