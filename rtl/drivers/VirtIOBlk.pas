//
// VirtIOBlk.pas
//
// This unit contains the driver for virtio block devices.
//
// Copyright (c) 2003-2019 Matias Vara <matiasevara@gmail.com>
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

unit VirtIOBlk;

interface

{$I ..\Toro.inc}

{$IFDEF EnableDebug}
       //{$DEFINE DebugVirtioBlk}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  FileSystem,
  Pci,
  Arch, Console, Network, Process, Memory;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

type
  PVirtIOBlockDevice= ^TVirtIOBlockDevice;
  PBlockDisk = ^TBlockDisk;

  PByte = ^TByte;
  TByte = array[0..0] of byte;

  VirtIOUsedItem = record
    index: Dword;
    length: Dword;
  end;

  PVirtIOUsed = ^TVirtIOUsed;
  TVirtIOUsed = record
    flags: word;
    index: word;
    rings: array[0..0] of VirtIOUsedItem;
  end;

  PVirtIOAvailable = ^TVirtIOAvailable;
  TVirtIOAvailable = record
    flags: Word;
    index: Word;
    rings: Array[0..0] of Word;
  end;

  PQueueBuffer = ^TQueueBuffer;
  TQueueBuffer = record
    address: QWord;
    length: DWord;
    flags: Word;
    next: Word;
  end;

  PVirtQueue = ^TVirtQueue;
  TVirtQueue = record
    queue_size: word;
    buffers: PQueueBuffer;
    available: PVirtIOAvailable;
    used: PVirtIOUsed;
    last_used_index: word;
    last_available_index: word;
    buffer: PByte;
    chunk_size: dword;
    next_buffer: word;
    lock: QWord;
  end;

  TBlockDisk = record
    StartSector : LongInt;
    Size: LongInt;
    FsType: LongInt;
    FileDesc: TFileBlock;
  end;

  TVirtIOBlockDevice = record
    IRQ: LongInt;
    Regs: Pointer;
    BlockCount: QWord;
    VirtQueue: TVirtQueue;
    Driver: TBlockDriver;
    Minors: array[0..3] of TBlockDisk;
  end;

  PBufferInfo = ^TBufferInfo;
  TBufferInfo = record
    buffer: ^Byte;
    size: QWord;
    flags: Byte;
    copy: Boolean;
  end;

  PBlockRequestHeader = ^BlockRequestHeader;
  BlockRequestHeader = record
    tp: DWord;
    reserved: DWord;
    Sector: QWord;
  end;

  PPartitionEntry = ^TPartitionEntry;
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


const
  VIRTIO_ACKNOWLEDGE = 1;
  VIRTIO_DRIVER = 2;
  VIRTIO_CTRL_VQ = 17;
  VIRTIO_RING_F_INDIRECT_DESC = 28;
  VIRTIO_MRG_RXBUF = 15;
  VIRTIO_CSUM = 0;
  VIRTIO_FEATURES_OK = 8;
  VIRTIO_DRIVER_OK = 4;
  VIRTIO_BLK_F_RO = 5;
  VIRTIO_BLK_F_BLK_SIZE = 6;
  VIRTIO_BLK_F_TOPOLOGY =10;

  VIRTIO_DESC_FLAG_WRITE_ONLY = 2;
  VIRTIO_DESC_FLAG_NEXT = 1;
  VIRTIO_NET_HDR_F_NEEDS_CSUM = 1;

  VIRTIO_BLK_T_IN = 0;
  VIRTIO_BLK_T_OUT = 1;

var
  BlkVirtIO: TVirtIOBlockDevice;

procedure VirtIOSendBuffer(Blk: PVirtIOBlockDevice; bi:PBufferInfo; count: QWord); forward;
procedure VirtIOProcessBlkQueue(BlkVirtIO: PVirtIOBlockDevice); forward;

procedure VirtIOBlkDetectPartition(Blk: PVirtIOBlockDevice);
var
  Buff: array[0..511] of Byte;
  Entry: PPartitionEntry;
  bi: array[0..2] of TBufferInfo;
  h: BlockRequestHeader;
  status, r: Byte;
  i: LongInt;
begin
  h.tp := VIRTIO_BLK_T_IN;
  h.reserved := 0;
  h.sector := 0;

  bi[0].buffer := @h;
  bi[0].size := sizeof(BlockRequestHeader);
  bi[0].flags := 0;
  bi[0].copy := true;

  bi[1].buffer := @Buff[0];
  bi[1].size := 512;
  bi[1].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
  bi[1].copy := false;

  bi[2].buffer := @status;
  bi[2].size := 1;
  bi[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
  bi[2].copy := true;

  ReadWriteBarrier;

  VirtIOSendBuffer(Blk, @bi[0], 3);

  while true do
  begin
    r := read_portb(PtrUInt(Blk.Regs) + $13);
    if (r and 1 = 1) then
    begin
      eoi;
      VirtIOProcessBlkQueue (Blk);
      if (Buff[511] = $AA) and (Buff[510] = $55) then
      begin
        Entry := @Buff[446];
        for i := 0 to 3 do
        begin
          if entry.pType <> 0 then
          begin
            Blk.Minors[i].startSector := entry.FirstSector;
            Blk.Minors[i].Size := Entry.Size;
            Blk.Minors[i].FsType := Entry.pType;
            Blk.Minors[i].FileDesc.BlockDriver := @Blk.Driver;
            Blk.Minors[i].FileDesc.BlockSize := 512;
            Blk.Minors[i].FileDesc.Minor := i;
            Blk.Minors[i].FileDesc.Next := nil;
            WriteConsoleF('VirtIOBlk: Minor: /V%d/n, Size: /V%d/n Mb, Type: /V%d/n\n',[i, Entry.Size div 2048, Entry.pType]);
          end
          else
            Blk.Minors[i].FsType := 0;
          Inc(Entry);
        end;
      end;
      Break;
    end;
  end;
end;

procedure VirtIOSendBuffer(Blk: PVirtIOBlockDevice; bi:PBufferInfo; count: QWord);
var
  index, buffer_index, next_buffer_index: word;
  vq: PVirtQueue;
  buf: ^Byte;
  b: PBufferInfo;
  i: LongInt;
  tmp: PQueueBuffer;
begin
  vq := @Blk.VirtQueue;
  index := vq.available.index mod vq.queue_size;
  buffer_index := vq.next_buffer;
  vq.available.rings[index] := buffer_index;
  buf := Pointer(PtrUInt(vq.buffer) + vq.chunk_size*buffer_index);
  for i := 0 to (count-1) do
  begin
    next_buffer_index:= (buffer_index +1) mod vq.queue_size;
    b := Pointer(PtrUInt(bi) + i * sizeof(TBufferInfo));
    tmp := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));
    tmp.flags := b.flags;
    tmp.next := next_buffer_index;
    tmp.length := b.size;
    if (i <> (count-1)) then
        tmp.flags := tmp.flags or VIRTIO_DESC_FLAG_NEXT;
    // FIXME: use copy=false to use zero-copy approach
    if b.copy then
    begin
       tmp.address:= PtrUInt (buf); // check this
       if (bi.buffer <> nil) then
           Move(b.buffer^, buf^, b.size);
       Inc(buf, b.size);
    end else
       tmp.address:= PtrUInt(b.buffer);
    buffer_index := next_buffer_index;
  end;
  ReadWriteBarrier;
  vq.next_buffer := buffer_index;
  Inc(vq.available.index);
  // notifications are not needed
  if (vq.used.flags and 1 <> 1) then
      write_portw(0, PtrUInt(Blk.Regs) + $10);
end;

procedure VirtIOProcessBlkQueue(BlkVirtIO: PVirtIOBlockDevice);
var
  vq: PVirtQueue;
begin
  vq := @BlkVirtIO.VirtQueue;
  if vq.last_used_index = vq.used.index then
    Exit;
  if BlkVirtIO.Driver.WaitOn <> nil then
    BlkVirtIO.Driver.WaitOn.State := tsReady;
  // index := vq.last_used_index;
  // while (index <> vq.used.index) do
  // begin
  //   inc(index);
  // end;
  // ReadWriteBarrier;
  vq.last_used_index := vq.used.index;
  ReadWriteBarrier;
end;

procedure VirtIOBlkHandler;
var
  r: byte;
begin
  r := read_portb(PtrUInt(BlkVirtIO.Regs) + $13);
  if (r and 1 = 1) then
  begin
     // for the moment only one thread can use the disk at time
     VirtIOProcessBlkQueue (@BlkVirtIO);
  end;
  eoi;
end;

procedure VirtIOBlkIrqHandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
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
  mov r15 , rsp
  mov rbp , r15
  sub r15 , 32
  mov  rsp , r15
  xor rcx , rcx
  Call VirtIOBlkHandler
  mov rsp , rbp
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

procedure virtIODedicateBlock(Driver:PBlockDriver; CPUID: LongInt);
var
  i: LongInt;
begin
  // ignore the major
  for i := 0 to 3 do
  begin
    if BlkVirtIO.Minors[i].fsType <> 0 then
    begin
      DedicateBlockFile(@BlkVirtIO.Minors[i].FileDesc, CPUID);
    end;
  end;
  IrqOn(BlkVirtIO.Irq);
  {$IFDEF DebugVirtioBlk}WriteDebug('virtIODedicateBlock: Dedicating virtioblk device on CPU %d\n',[CPUID]);{$ENDIF}
end;

function virtIOReadBlock(FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
var
  bi: array[0..2] of TBufferInfo;
  h: BlockRequestHeader;
  status: Byte;
begin
  Result := 0;
  GetDevice(FileDesc.BlockDriver);
  Block := Block + BlkVirtIO.Minors[FileDesc.Minor].StartSector;
  {$IFDEF DebugVirtioBlk}WriteDebug('virtIOReadBlock: Reading block: %d count: %d\n',[Block, Count]);{$ENDIF}
  While Count <> 0 do
  begin
    DisableInt;
    BlkVirtIO.Driver.WaitOn.state := tsSuspended;
    h.tp := VIRTIO_BLK_T_IN;
    h.reserved := 0;
    h.sector := Block;
    bi[0].buffer := @h;
    bi[0].size := sizeof(BlockRequestHeader);
    bi[0].flags := 0;
    bi[0].copy := true;
    bi[1].buffer := buffer;
    bi[1].size := 512;
    bi[1].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi[1].copy := false;
    bi[2].buffer := @status;
    bi[2].size := 1;
    bi[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi[2].copy := true;
    VirtIOSendBuffer(@BlkVirtIO, @bi[0], 3);
    RestoreInt;
    SysThreadSwitch;
    Dec(Count);
    Inc(Result);
    Inc(Block);
  end;
  FreeDevice(FileDesc.BlockDriver);
end;

function virtIOWriteBlock(FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
var
  bi: array[0..2] of TBufferInfo;
  h: BlockRequestHeader;
  status: Byte;
begin
  Result := 0;
  GetDevice(FileDesc.BlockDriver);
  Block := Block + BlkVirtIO.Minors[FileDesc.Minor].StartSector;
  {$IFDEF DebugVirtioBlk}WriteDebug('virtIOWriteBlock: Writing block: %d count: %d\n',[Block, Count]);{$ENDIF}
  While Count <> 0 do
  begin
    DisableInt;
    BlkVirtIO.Driver.WaitOn.state := tsSuspended;
    h.tp := VIRTIO_BLK_T_OUT;
    h.reserved := 0;
    h.sector := Block;
    bi[0].buffer := @h;
    bi[0].size := sizeof(BlockRequestHeader);
    bi[0].flags := 0;
    bi[0].copy := true;
    bi[1].buffer := buffer;
    bi[1].size := 512;
    bi[1].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi[1].copy := false;
    bi[2].buffer := @status;
    bi[2].size := 1;
    bi[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi[2].copy := true;
    VirtIOSendBuffer(@BlkVirtIO, @bi[0], 3);
    RestoreInt;
    SysThreadSwitch;
    Dec(Count);
    Inc(Result);
    Inc(Block);
  end;
  FreeDevice(FileDesc.BlockDriver);
end;

procedure FindVirtIOBlkonPci;
var
  PciCard: PBusDevInfo;
  tmp: DWORD;
  features: DWORD;
  QueueSize: Word;
  sizeOfBuffers: DWORD;
  sizeofQueueAvailable: DWORD;
  sizeofQueueUsed: DWORD;
  queuePageCount: DWORD;
  buff: PChar;
  buffPage: DWORD;
  bi: TBufferInfo;
  queue: PVirtQueue;
begin
  PciCard := PCIDevices;
  DisableInt;
  while PciCard <> nil do
  begin
    if (PciCard.mainclass = $01) and (PciCard.subclass = $00) then
    begin
      if (PciCard.vendor = $1AF4) and (PciCard.device >= $1000) and (PciCard.device <= $103f) then
      begin
        BlkVirtIO.Irq := PciCard.Irq;
        BlkVirtIO.Regs:= Pointer(PtrUInt(PCIcard.io[0]));
        PciSetMaster(PciCard);

        // get block count
        read_portd(@tmp, PtrUInt(BlkVirtIO.Regs) + $18);
        BlkVirtIO.BlockCount := tmp shl 32;
        read_portd(@tmp, PtrUInt(BlkVirtIO.Regs) + $14);
        BlkVirtIO.BlockCount := BlkVirtIO.BlockCount or tmp;

        WriteConsoleF('VirtIOBlk: /Vfound/n, irq: /V%d/n, ioport: /V%h/n, size: /V%d/n\n',[BlkVirtIO.IRQ, PtrUInt(BlkVirtIO.Regs), BlkVirtIO.BlockCount]);

        // reset device
        write_portb(0, PtrUInt(BlkVirtIO.Regs) + $12);

        // tell driver that we found it
        write_portb(VIRTIO_ACKNOWLEDGE, PtrUInt(BlkVirtIO.Regs) + $12);
        write_portb(VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER, PtrUInt(BlkVirtIO.Regs) + $12);

        // negotiation phase
        read_portd(@features, PtrUInt(BlkVirtIO.Regs));
        features := features and not((1 shl VIRTIO_BLK_F_RO) or (1 shl VIRTIO_BLK_F_BLK_SIZE) or (1 shl VIRTIO_BLK_F_TOPOLOGY));
        write_portd(@features, PtrUInt(BlkVirtIO.Regs) + $4);

        // check if driver accepted features
        write_portb(VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK, PtrUInt(BlkVirtIO.Regs) + $12);
        if ((read_portb(PtrUInt(BlkVirtIO.Regs) + $12) and VIRTIO_FEATURES_OK) = 0) then
        begin
          WriteConsoleF('VirtIOBlk: driver did not accept features\n',[]);
          Exit;
        end
        else
          WriteConsoleF('VirtIOBlk: driver accepted features\n',[]);

        // initialize virtqueue
        FillByte(BlkVirtIO.VirtQueue, sizeof(TVirtQueue), 0);
        write_portw(0,  PtrUInt(BlkVirtIO.Regs) + $0E);
        QueueSize := read_portw(PtrUInt(BlkVirtIO.Regs) + $0C);

        BlkVirtIO.VirtQueue.queue_size:= QueueSize;
        sizeOfBuffers := (sizeof(TQueueBuffer) * QueueSize);
        sizeofQueueAvailable := (2*sizeof(WORD)+2) + (QueueSize*sizeof(WORD));
        sizeofQueueUsed := (2*sizeof(WORD)+2)+(QueueSize*sizeof(VirtIOUsedItem));

        // buff must be 4k aligned
        buff := ToroGetMem(sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096 * 2);

        Panic (buff=nil, 'VirtIOBlk: no memory for VirtIO buffers\n', []);
        FillByte(buff^, sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096 * 2, 0);
        buff := buff + (4096 - PtrUInt(buff) mod 4096);
        buffPage := PtrUInt(buff) div 4096;

        // 16 bytes aligned
        BlkVirtIO.VirtQueue.buffers := PQueueBuffer(buff);

        // 2 bytes aligned
        BlkVirtIO.VirtQueue.available := @buff[sizeOfBuffers];

        // 4 bytes aligned
        BlkVirtIO.VirtQueue.used := PVirtIOUsed(@buff[((sizeOfBuffers + sizeofQueueAvailable+$0FFF) and not $FFF)]);

        BlkVirtIO.VirtQueue.next_buffer:= 0;
        BlkVirtIO.VirtQueue.lock := 0;
        write_portd(@buffPage, PtrUInt(BlkVirtIO.Regs) + $08);

        write_portb(VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK or VIRTIO_DRIVER_OK, PtrUInt(BlkVirtIO.Regs) + $12);

        queue := @BlkVirtIO.VirtQueue;
        queue.Buffer := ToroGetMem(queue.queue_size * (sizeof(BlockRequestHeader)+1) + 4096);
        Panic (queue.Buffer=nil, 'VirtIOBlk: no memory for Queue buffer\n', []);
        queue.Buffer := Pointer(PtrUint(queue.Buffer) + (4096 - PtrUInt(queue.Buffer) mod 4096));
        queue.chunk_size := sizeof(BlockRequestHeader) + 1;

        write_portw(0, PtrUInt(BlkVirtIO.Regs) + $10);

        BlkVirtIO.Driver.name := 'virtioblk';
        BlkVirtIO.Driver.Busy := false;
        BlkVirtIO.Driver.WaitOn := nil;
        BlkVirtIO.Driver.major := 0;
        BlkVirtIO.Driver.ReadBlock := @virtIOReadBlock;
        BlkVirtIO.Driver.WriteBlock := @virtIOWriteBlock;
        BlkVirtIO.Driver.Dedicate := @virtIODedicateBlock;
        BlkVirtIO.Driver.CPUID := -1;
        RegisterBlockDriver(@BlkVirtIO.Driver);

        CaptureInt(32+BlkVirtIO.irq, @VirtIOBlkIrqHandler);

        // enable interruption
        BlkVirtIO.VirtQueue.used.flags := 0;
        VirtIOBlkDetectPartition (@BlkVirtIO);
        WriteConsoleF('VirtIOBlk: driver registered\n',[]);
      end;
    end;
    PciCard := PciCard.Next;
  end;
  RestoreInt;
end;

initialization
  FindVirtIOBlkonPci;

end.
