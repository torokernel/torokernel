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
        //{$DEFINE DebugVirtio}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  FileSystem,
  Pci,
  Arch, Console, Network, Process, Memory;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}

type
  PVirtIOBlockDevice= ^TVirtIOBlockDevice;

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
    FileDesc: TFileBlock;
    IRQ: LongInt;
    Regs: Pointer;
    BlockCount: QWord;
    VirtQueues: TVirtQueue;
    Driver: TBlockDriver;
    // TODO: numero maximo de particiones
    Minors: array[0..4-1] of TBlockDisk;
  end;

  PBufferInfo = ^TBufferInfo;
  TBufferInfo = record
    buffer: ^Byte;
    size: QWord;
    flags: Byte;
    copy: Boolean;
  end;

  TNetHeader = record
    flags: byte;
    gso_type: byte;
    header_length: word;
    gso_size: word;
    checksum_start: word;
    checksum_offset: word;
  end;


const
  VIRTIO_ACKNOWLEDGE = 1;
  VIRTIO_DRIVER = 2;
  VIRTIO_CTRL_VQ = 17;
  VIRTIO_GUEST_TSO4 = 7;
  VIRTIO_GUEST_TSO6 = 8;
  VIRTIO_GUEST_UFO = 10;
  VIRTIO_EVENT_IDX = 29;
  VIRTIO_RING_F_INDIRECT_DESC = 28;
  VIRTIO_MRG_RXBUF = 15;
  VIRTIO_CSUM = 0;
  VIRTIO_MAC = 5;
  VIRTIO_FEATURES_OK = 8;
  VIRTIO_DRIVER_OK = 4;
  VIRTIO_BLK_F_RO = 5;
  VIRTIO_BLK_F_BLK_SIZE = 6;
  VIRTIO_BLK_F_TOPOLOGY =10;

  FRAME_SIZE = 1526;
  VIRTIO_DESC_FLAG_WRITE_ONLY = 2;
  VIRTIO_DESC_FLAG_NEXT = 1;
  VIRTIO_NET_HDR_F_NEEDS_CSUM = 1;
  TX_QUEUE = 1;
  RX_QUEUE = 0;

var
  BlkVirtIO: TVirtIOBlockDevice;


procedure VirtIOSendBuffer(Blk: PVirtIOBlockDevice; bi:PBufferInfo; count: QWord);
var
  index, buffer_index, next_buffer_index: word;
  vq: PVirtQueue;
  buf: ^Byte;
  b: PBufferInfo;
  i: LongInt;
  tmp: PQueueBuffer;
begin
  vq := @Blk.VirtQueues;

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
    {$IFDEF DebugVirtio}WriteDebug('VirtIOSendBuffer: queue: %d, vq.available.index: %d, vq.used.index: %d, vq.used.len: %d id: %d\n',[queue_index, vq.available.index, vq.used.index, vq.used.rings[(vq.used.index-1) mod vq.queue_size].length, vq.used.rings[(vq.used.index-1) mod vq.queue_size].index]);{$ENDIF}
  end;

  ReadWriteBarrier;
  vq.next_buffer := buffer_index;
  vq.available.index:= vq.available.index + 1;

  // notification are not needed
  if (vq.used.flags and 1 <> 1) then
      write_portw(0, PtrUInt(Blk.Regs) + $10);

  {$IFDEF DebugVirtio}WriteDebug('VirtIOSendBuffer: queue: %d, vq.available.index: %d, vq.used.index: %d\n',[queue_index, vq.available.index, vq.used.index]);{$ENDIF}
end;

procedure VirtIOBlkHandler;
var
  r: byte;
begin
  r := read_portb(PtrUInt(BlkVirtIO.Regs) + $13);
  if (r and 1 = 1) then
  begin
     // Process queue
     //VirtIOProcessRx (@NicVirtIO);
  end;
  {$IFDEF DebugVirtio}WriteDebug('VirtIOHandler: used.flags:%d, ava.flags:%d, r:%d\n',[NicVirtIO.VirtQueues[1].used.flags, NicVirtIO.VirtQueues[1].available.flags, r]);{$ENDIF}
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

procedure virtIODedicateBlock(Driver:PBlockDriver;CPUID: LongInt);
var
  I: LongInt;
begin
end;

function virtIOReadBlock(FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
begin
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
  j: LongInt;
begin
  PciCard := PCIDevices;
  DisableInt;
  while PciCard <> nil do
  begin
    // not sure why it works with $01
    if (PciCard.mainclass = $01) and (PciCard.subclass = $00) then
    begin
      if (PciCard.vendor = $1AF4) and (PciCard.device >= $1000) and (PciCard.device <= $103f) then
      begin
        BlkVirtIO.IRQ := PciCard.irq;
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
        FillByte(BlkVirtIO.VirtQueues, sizeof(TVirtQueue),0);
        write_portw(0,  PtrUInt(BlkVirtIO.Regs) + $0E);
        QueueSize := read_portw(PtrUInt(BlkVirtIO.Regs) + $0C);

        BlkVirtIO.VirtQueues.queue_size:= QueueSize;
        sizeOfBuffers := (sizeof(TQueueBuffer) * QueueSize);
        sizeofQueueAvailable := (2*sizeof(WORD)+2) + (QueueSize*sizeof(WORD));
        sizeofQueueUsed := (2*sizeof(WORD)+2)+(QueueSize*sizeof(VirtIOUsedItem));

        // buff must be 4k aligned
        buff := ToroGetMem(sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096);
        Panic (buff=nil, 'VirtIOBlk: no memory for VirtIO buffers\n');
        FillByte(buff^, sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096, 0);
        buff := buff + (4096 - PtrUInt(buff) mod 4096);
        buffPage := PtrUInt(buff) div 4096;

        // 16 bytes aligned
        BlkVirtIO.VirtQueues.buffers := PQueueBuffer(buff);

        // 2 bytes aligned
        BlkVirtIO.VirtQueues.available := @buff[sizeOfBuffers];

        // 4 bytes aligned
        BlkVirtIO.VirtQueues.used := PVirtIOUsed(@buff[((sizeOfBuffers + sizeofQueueAvailable+$0FFF) and not($0FFF))]) ;
        BlkVirtIO.VirtQueues.next_buffer:= 0;
        BlkVirtIO.VirtQueues.lock := 0;
        write_portd(@buffPage, PtrUInt(BlkVirtIO.Regs) + $08);
        BlkVirtIO.VirtQueues.available.flags := 0;
        {$IFDEF DebugVirtio}WriteDebug('VirtIOBlk: queue: %d, size: %d\n',[j, QueueSize]);{$ENDIF}

        write_portb(VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK or VIRTIO_DRIVER_OK, PtrUInt(BlkVirtIO.Regs) + $12);

        // setup queue
        queue := @BlkVirtIO.VirtQueues;
        queue.Buffer := ToroGetMem(queue.queue_size * FRAME_SIZE + 4096);
        Panic (queue.Buffer=nil, 'VirtIOBlk: no memory for Queue buffer\n');
        queue.Buffer := Pointer(PtrUint(queue.Buffer) + (4096 - PtrUInt(queue.Buffer) mod 4096));
        queue.chunk_size := FRAME_SIZE;
        queue.available.index := 0;
        queue.used.index := 0;

        ReadWriteBarrier;

        write_portw(0, PtrUInt(BlkVirtIO.Regs) + $10);

        // enable interruptions
        queue.used.flags :=0;

        // add all buffers to the queue
        bi.size:= FRAME_SIZE;
        bi.buffer:= nil;
        bi.flags:= VIRTIO_DESC_FLAG_WRITE_ONLY;
        bi.copy:= True;

        for j := 0 to queue.queue_size - 1 do
        begin
          VirtIOSendBuffer(@BlkVirtIO, @bi, 1);
        end;

        CaptureInt(32+BlkVirtIO.IRQ, @VirtIOBlkIrqHandler);
        // TODO: cada dispositivo soporta hasta 4 particiones primarias
        // la particion numero 0 es todo el disco
        // la 1, 2 ,3 y 4 son las sucesivas particiones
        // TODO: inicializar cada particion
        BlkVirtIO.Driver.name := 'virtioblk';
        BlkVirtIO.Driver.Busy := false;
        BlkVirtIO.Driver.WaitOn := nil;
        BlkVirtIO.Driver.major := 0;
        BlkVirtIO.Driver.ReadBlock := @virtIOReadBlock;
        BlkVirtIO.Driver.Dedicate := @virtIODedicateBlock;
        RegisterBlockDriver(@BlkVirtIO.Driver);
        // TODO: Add support for more devices
        Exit;
      end;
    end;
    PciCard := PciCard.Next;
  end;
  RestoreInt;
end;

initialization
  FindVirtIOBlkonPci;

end.
