//
// VirtIOVSocket.pas
//
// This unit contains the code of the VirtIOVsocket driver.
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

unit VirtIOVSocket;

interface

{$I ..\Toro.inc}

{$IFDEF EnableDebug}
       //{$DEFINE DebugVirtioFS}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Pci,
  Arch, Console, Network, Process, Memory;

type

  PByte = ^TByte;
  TByte = array[0..0] of byte;

  PBufferInfo = ^TBufferInfo;
  TBufferInfo = record
    buffer: ^Byte;
    size: QWord;
    flags: Byte;
    copy: Boolean;
  end;

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

  TVirtIOVSocketDevice = record
    IRQ: LongInt;
    Regs: DWORD;
    VirtQueues: array[0..2] of TVirtQueue;
    GuestId: QWORD;
    Driverinterface: TNetworkInterface;
  end;

  TVirtIOVSockEvent = record
    ID: DWORD;
  end;

  TVirtIOVSockHdr = packed record
    src_cid: QWORD;
    dst_cid: QWORD;
    src_port: DWORD;
    dst_port: DWORD;
    len: DWORD;
    tp: WORD;
    op: WORD;
    flags: DWORD;
    buf_alloc: DWORD;
    fwd_cnt: DWORD;
  end;

  VirtIOVSockPacket = packed record
    hdr: TVirtIOVSockHdr;
    data: array[0..0] of Byte;
  end;

const
  VIRTIO_ID_VSOCKET = $1012;
  VIRTIO_ACKNOWLEDGE = 1;
  VIRTIO_DRIVER = 2;
  VIRTIO_CTRL_VQ = 17;
  VIRTIO_RING_F_INDIRECT_DESC = 28;
  VIRTIO_MRG_RXBUF = 15;
  VIRTIO_CSUM = 0;
  VIRTIO_DRIVER_OK = 4;
  FRAME_SIZE = 1526;
  VIRTIO_DESC_FLAG_WRITE_ONLY = 2;
  VIRTIO_DESC_FLAG_NEXT = 1;
  VIRTIO_VSOCK_MAX_PKT_BUF_SIZE = 1024 * 64;
  RX_QUEUE = 0;
  TX_QUEUE = 1;
  EVENT_QUEUE = 2;

var
  VirtIOVSocketDev: TVirtIOVSocketDevice;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

procedure VirtIOSendBufferLegacy(Base: DWORD; queue_index: word; Queue: PVirtQueue; bi:PBufferInfo; count: QWord);
var
  index, buffer_index, next_buffer_index: word;
  vq: PVirtQueue;
  buf: ^Byte;
  b: PBufferInfo;
  i: LongInt;
  tmp: PQueueBuffer;
begin
  vq := Queue;

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
  vq.available.index:= vq.available.index + 1;

  // notification are not needed
  // TODO: remove the use of base
  if (vq.used.flags and 1 <> 1) then
      write_portw(queue_index, Base + $10);
end;

function VirtIOInitQueueLegacy(Base: DWORD; QueueId: Word; Queue: PVirtQueue; HeaderLen: DWORD): Boolean;
var
  j: LongInt;
  QueueSize: Word;
  sizeOfBuffers: DWORD;
  sizeofQueueAvailable: DWORD;
  sizeofQueueUsed: DWORD;
  buff: PChar;
  buffPage: DWORD;
  bi: TBufferInfo;
begin
  Result := False;
  FillByte(Queue^, sizeof(TVirtQueue), 0);
  write_portw(QueueId, Base + $0E);
  QueueSize := read_portw(Base + $0C);
  if QueueSize = 0 then
    Exit;
  Queue.queue_size := QueueSize;
  sizeOfBuffers := (sizeof(TQueueBuffer) * QueueSize);
  sizeofQueueAvailable := (2*sizeof(WORD)+2) + (QueueSize*sizeof(WORD));
  sizeofQueueUsed := (2*sizeof(WORD)+2)+(QueueSize*sizeof(VirtIOUsedItem));

  // buff must be 4k aligned
  buff := ToroGetMem(sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096*2);
  If buff = nil then
    Exit;
  FillByte(buff^, sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096*2, 0);
  buff := buff + (4096 - PtrUInt(buff) mod 4096);
  buffPage := PtrUInt(buff) div 4096;

  // 16 bytes aligned
  Queue.buffers := PQueueBuffer(buff);

  // 2 bytes aligned
  Queue.available := @buff[sizeOfBuffers];

  // 4 bytes aligned
  Queue.used := PVirtIOUsed(@buff[((sizeOfBuffers + sizeofQueueAvailable + $0FFF) and not($0FFF))]);
  Queue.next_buffer := 0;
  Queue.lock := 0;

  write_portd(@buffPage, Base + $08);
  Queue.available.flags := 0;

  if HeaderLen <> 0 then
  begin
    Queue.Buffer := ToroGetMem(Queue.queue_size * (HeaderLen) + 4096);
    if Queue.Buffer = nil then
      Exit;
    Queue.Buffer := Pointer(PtrUint(queue.Buffer) + (4096 - PtrUInt(Queue.Buffer) mod 4096));
    Queue.chunk_size := HeaderLen;
    Queue.available.index := 0;
    Queue.used.index := 0;
    ReadWriteBarrier;
    write_portw(QueueId, Base + $10);
    Queue.used.flags := 0;

    bi.size := HeaderLen;
    bi.buffer := nil;
    bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi.copy := True;
    for j := 0 to Queue.queue_size - 1 do
    begin
      VirtIOSendBufferLegacy(Base, QueueId, Queue, @bi, 1);
    end;
  end;
  Result := True;
end;

procedure VirtIOProcessTxQueue(vq: PVirtQueue);
var
  index, norm_index, buffer_index: Word;
  tmp: PQueueBuffer;
begin
  if (vq.last_used_index = vq.used.index) then
    Exit;
  index := vq.last_used_index;

  while (index <> vq.used.index) do
  begin
    norm_index := index mod vq.queue_size;
    buffer_index := vq.used.rings[norm_index].index;
    tmp := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));
    // mark buffer as free
    tmp.length:= 0;
    inc(index);
  end;

  ReadWriteBarrier;

  vq.last_used_index:= index;
end;

type
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;

procedure VirtIOProcessRxQueue(rx: PVirtQueue);
var
  Packet: PPacket;
  index, buffer_index, Len, I: dword;
  Data, P: PByteArray;
  buf: PQueueBuffer;
  bi: TBufferInfo;
begin
  // empty queue?
  if (rx.last_used_index = rx.used.index) then
    Exit;

  while (rx.last_used_index <> rx.used.index) do
  begin
    index := rx.last_used_index mod rx.queue_size;
    buffer_index := rx.used.rings[index].index;

    buf := rx.buffers;
    Inc(buf, buffer_index);

    P := Pointer(buf.address);
    Len := rx.used.rings[index].length;

    Packet := ToroGetMem(Len+SizeOf(TPacket));

    if (Packet <> nil) then
    begin
      Packet.data:= Pointer(PtrUInt(Packet) + SizeOf(TPacket));
      Packet.size:= Len;
      Packet.Delete:= False;
      Packet.Ready:= False;
      Packet.Next:= nil;
      Data := Packet.data;
      for I := 0 to Len-1 do
        Data^[I] := P^[I];
      EnqueueIncomingPacket(Packet);
    end;

    Inc(rx.last_used_index);

    // return the buffer
    // TODO: to define a function that does this
    bi.size := VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr);
    bi.buffer := Pointer(buf.address);
    bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi.copy := false;

    // TODO: remove the use of VirtIOVSocketDev
    VirtIOSendBufferLegacy(VirtIOVSocketDev.Regs, RX_QUEUE, rx, @bi, 1);
    ReadWriteBarrier;
  end;
end;

procedure VirtIOVSocketHandler;
var
  r: byte;
begin
  r := read_portb(VirtIOVSocketDev.Regs + $13);
  if (r and 1 = 1) then
  begin
    VirtIOProcessRxQueue (@VirtIOVSocketDev.VirtQueues[RX_QUEUE]);
    VirtIOProcessTxQueue (@VirtIOVSocketDev.VirtQueues[TX_QUEUE]);
  end;
  eoi;
end;

// TODO: Use net to get the IRQ
procedure virtIOVSocketStart(net: PNetworkInterface);
begin
  IrqOn(VirtIOVSocketDev.IRQ);
end;

procedure virtIOVSocketSend(Net: PNetworkInterface; Packet: PPacket);
var
  bi: TBufferInfo;
begin
  DisableInt;

  bi.buffer := Packet.Data;
  bi.size := Packet.Size;
  bi.flags := 0;
  bi.copy := true;

  Net.OutgoingPackets:= Packet;
  // TODO: Remove the use of VirtIOVSocketDev
  VirtIOSendBufferLegacy(VirtIOVSocketDev.Regs, TX_QUEUE, @VirtIOVSocketDev.VirtQueues[TX_QUEUE], @bi, 1);
  DequeueOutgoingPacket;
  RestoreInt;
end;

procedure VirtIOVSocketIrqHandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
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
  Call VirtIOVSocketHandler
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

procedure FindVirtIOSocketonPci;
var
  PciDev: PBusDevInfo;
  j: LongInt;
  tx: PVirtQueue;
  Net: PNetworkInterface;
begin
  PciDev := PCIDevices;
  DisableInt;
  while PciDev <> nil do
  begin
    // this is a legacy device
    if (PciDev.vendor = $1AF4) and (PciDev.device = VIRTIO_ID_VSOCKET) then
    begin
      VirtIOVSocketDev.IRQ := PciDev.irq;
      VirtIOVSocketDev.Regs:= PtrUInt(PciDev.io[0]);
      PciSetMaster(PciDev);
      WriteConsoleF('VirtIOVSocket: /Vfound/n, irq: /V%d/n, ioport: /V%h/n\n',[VirtIOVSocketDev.IRQ, PtrUInt(VirtIOVSocketDev.Regs)]);

      // reset device
      write_portb(0, VirtIOVSocketDev.Regs + $12);

      // tell driver that we found it
      write_portb(VIRTIO_ACKNOWLEDGE, VirtIOVSocketDev.Regs + $12);
      write_portb(VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER, VirtIOVSocketDev.Regs + $12);

      VirtIOVSocketDev.GuestID := 0;

      for j := 0 to sizeof(VirtIOVSocketDev.GuestID)-1 do
      begin
        VirtIOVSocketDev.GuestID := VirtIOVSocketDev.GuestID or (read_portb(VirtIOVSocketDev.Regs + $14 + j) shr (j * sizeof(Byte)));
      end;

      WriteConsoleF('VirtIOVSocket: Guest ID: /V%d/n\n', [VirtIOVSocketDev.GuestID]);

      // RX and EVENT queue must fulled with buffers
      if VirtIOInitQueueLegacy(VirtIOVSocketDev.Regs, RX_QUEUE, @VirtIOVSocketDev.VirtQueues[RX_QUEUE], VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr)) then
        WriteConsoleF('VirtIOVSocket: RX_QUEUE was initiated\n', [])
      else
        WriteConsoleF('VirtIOVSocket: RX_QUEUE was not initiated\n', []);

      if VirtIOInitQueueLegacy(VirtIOVSocketDev.Regs, EVENT_QUEUE, @VirtIOVSocketDev.VirtQueues[EVENT_QUEUE], sizeof(TVirtIOVSockEvent)) then
        WriteConsoleF('VirtIOVSocket: EVENT_QUEUE was initiated\n', [])
      else
        WriteConsoleF('VirtIOVSocket: EVENT_QUEUE was not initiated\n', []);

       if VirtIOInitQueueLegacy(VirtIOVSocketDev.Regs, TX_QUEUE, @VirtIOVSocketDev.VirtQueues[TX_QUEUE], 0) then
        WriteConsoleF('VirtIOVSocket: TX_QUEUE was initiated\n', [])
      else
        WriteConsoleF('VirtIOVSocket: TX_QUEUE was not initiated\n', []);

      // set up buffers for transmission
      // TODO: use the buffers from user
      tx := @VirtIOVSocketDev.VirtQueues[TX_QUEUE];
      tx.buffer := ToroGetMem((VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr)) * tx.queue_size + 4096);
      tx.buffer := Pointer(PtrUInt(tx.buffer) + (4096 - PtrUInt(tx.buffer) mod 4096));
      tx.chunk_size:= VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr);
      tx.available.index := 0;
      tx.available.flags := 0;
      tx.used.flags := 0;
      ReadWriteBarrier;
      write_portw(TX_QUEUE, VirtIOVSocketDev.Regs + $10);

      write_portb(VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_DRIVER_OK, VirtIOVSocketDev.Regs + $12);
      CaptureInt(32+VirtIOVSocketDev.IRQ, @VirtIOVSocketIrqHandler);
      Net := @VirtIOVSocketDev.Driverinterface;
      Net.Name:= 'virtiovsocket';
      Net.start:= @virtIOVSocketStart;
      Net.send:= @virtIOVSocketSend;
      Net.TimeStamp := 0;
      Net.Minor := VirtIOVSocketDev.GuestID;
      RegisterNetworkInterface(Net);
      WriteConsoleF('VirtIOVSocket: driver registered\n',[]);
    end;
    PciDev := PciDev.next;
  end;
  RestoreInt;
end;

initialization
  FindVirtIOSocketonPci;
end.
