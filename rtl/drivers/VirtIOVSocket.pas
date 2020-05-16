//
// VirtIOVSocket.pas
//
// This unit contains the code of the VirtIOVsocket driver.
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

unit VirtIOVSocket;

interface

{$I ..\Toro.inc}

{$IFDEF EnableDebug}
       //{$DEFINE DebugVirtioFS}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Console, Network, Process, Memory;

type

  PByte = ^TByte;
  TByte = array[0..0] of byte;
  PVirtIOVSocketDevice = ^TVirtIOVSocketDevice;

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
    queue_size: WORD;
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
    Base: QWORD;
    VirtQueues: array[0..2] of TVirtQueue;
    GuestId: QWORD;
    Driverinterface: TNetworkInterface;
  end;

const
  VIRTIO_ID_VSOCKET = 19;
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

  PAGE_SIZE = 4096;

  MMIO_SIGNATURE = $74726976;
  MMIO_DEVICEID = $8;
  MMIO_STATUS = $70;
  MMIO_GUESTID = $100;
  MMIO_QUEUESEL = $30;
  MMIO_QUEUENUMMAX = $34;
  MMIO_QUEUENUM = $38;
  MMIO_QUEUENOTIFY = $50;
  MMIO_QUEUEREADY = $44;
  MMIO_LEGACY = 1;
  MMIO_VERSION = 4;
  MMIO_GUESTPAGESIZE = $28;
  MMIO_QUEUEPFN = $40;
  MMIO_QUEUEALIGN = $3C;
  MMIO_INTSTATUS = $60;
  MMIO_INTACK = $64;

  // TODO: get this from command-line
  BASE_MICROVM_MMIO = $c0000e00;
  IRQ_MICROVM_MMIO = 12;

var
  VirtIOVSocketDev: TVirtIOVSocketDevice;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

procedure SetDeviceStatus(Base: QWORD; Value: DWORD);
var
  status: ^DWORD;
begin
  status := Pointer(Base + MMIO_STATUS);
  status^ := Value;
  ReadWriteBarrier;
end;

procedure SetDeviceGuestPageSize(Base: QWORD; Value: DWORD);
var
  GuestPageSize: ^DWORD;
begin
  GuestPageSize := Pointer(VirtIOVSocketDev.Base + MMIO_GUESTPAGESIZE);
  GuestPageSize^ := Value;
end;

function GetIntStatus(Base: QWORD): DWORD;
var
  IntStatus: ^DWORD;
begin
  IntStatus := Pointer(VirtIOVSocketDev.Base + MMIO_INTSTATUS);
  Result := IntStatus^;
end;

procedure SetIntACK(Base: QWORD; Value: DWORD);
var
  IntACK: ^DWORD;
begin
  IntACK := Pointer(VirtIOVSocketDev.Base + MMIO_INTACK);
  IntAck^ := Value;
end;

procedure VirtIOSendBuffer(Base: QWORD; queue_index: word; Queue: PVirtQueue; bi:PBufferInfo; count: QWord);
var
  index, buffer_index, next_buffer_index: word;
  vq: PVirtQueue;
  buf: ^Byte;
  b: PBufferInfo;
  i: LongInt;
  tmp: PQueueBuffer;
  QueueNotify: ^DWORD;
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

    // TODO: use copy=false to use zero-copy approach
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
  begin
    QueueNotify := Pointer(Base + MMIO_QUEUENOTIFY);
    QueueNotify^ := queue_index;
  end;
end;

function VirtIOInitQueue(Base: QWORD; QueueId: Word; Queue: PVirtQueue; HeaderLen: DWORD): Boolean;
var
  j: LongInt;
  QueueSize, sizeOfBuffers: DWORD;
  sizeofQueueAvailable, sizeofQueueUsed: DWORD;
  buff: PChar;
  bi: TBufferInfo;
  QueueSel, QueueAlign: ^DWORD;
  QueueNumMax, QueueNum: ^DWORD;
  QueuePFN, QueueNotify: ^DWORD;
begin
  Result := False;
  FillByte(Queue^, sizeof(TVirtQueue), 0);

  QueueSel := Pointer(Base + MMIO_QUEUESEL);
  QueueSel^ := QueueId;
  ReadWriteBarrier;

  QueueNumMax := Pointer(Base + MMIO_QUEUENUMMAX);
  QueueSize := QueueNumMax^;
  if QueueSize = 0 then
    Exit;
  Queue.queue_size := QueueSize;

  // set queue size
  QueueNum := Pointer (Base + MMIO_QUEUENUM);
  QueueNum^ := QueueSize;
  ReadWriteBarrier;

  sizeOfBuffers := (sizeof(TQueueBuffer) * QueueSize);
  sizeofQueueAvailable := (2*sizeof(WORD)+2) + (QueueSize*sizeof(WORD));
  sizeofQueueUsed := (2*sizeof(WORD)+2)+(QueueSize*sizeof(VirtIOUsedItem));

  // buff must be 4k aligned
  buff := ToroGetMem(sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + PAGE_SIZE*2);
  If buff = nil then
    Exit;
  FillByte(buff^, sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + PAGE_SIZE*2, 0);
  buff := buff + (PAGE_SIZE - PtrUInt(buff) mod PAGE_SIZE);

  // 16 bytes aligned
  Queue.buffers := PQueueBuffer(buff);

  // 2 bytes aligned
  Queue.available := @buff[sizeOfBuffers];

  // 4 bytes aligned
  Queue.used := PVirtIOUsed(@buff[((sizeOfBuffers + sizeofQueueAvailable + $0FFF) and not($0FFF))]);
  Queue.next_buffer := 0;
  Queue.lock := 0;

  QueueAlign := Pointer(Base + MMIO_QUEUEALIGN);
  QueueAlign^ := PAGE_SIZE;

  QueuePFN := Pointer(Base + MMIO_QUEUEPFN);
  QueuePFN^ := PtrUInt(buff) div PAGE_SIZE;

  // Device queues are fill
  if HeaderLen <> 0 then
  begin
    Queue.Buffer := ToroGetMem(Queue.queue_size * (HeaderLen) + PAGE_SIZE);
    if Queue.Buffer = nil then
      Exit;
    Queue.Buffer := Pointer(PtrUint(queue.Buffer) + (PAGE_SIZE - PtrUInt(Queue.Buffer) mod PAGE_SIZE));
    Queue.chunk_size := HeaderLen;

    bi.size := HeaderLen;
    bi.buffer := nil;
    bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi.copy := True;
    for j := 0 to Queue.queue_size - 1 do
    begin
      VirtIOSendBuffer(Base, QueueId, Queue, @bi, 1);
    end;
  end;

  Result := True;
end;

procedure VirtIOProcessTxQueue(Drv: PVirtIOVSocketDevice);
var
  index, norm_index, buffer_index: Word;
  tmp: PQueueBuffer;
  vq: PVirtQueue;
begin
  vq := @Drv.VirtQueues[TX_QUEUE];
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

procedure VirtIOProcessRxQueue(Drv: PVirtIOVSocketDevice);
var
  Packet: PPacket;
  index, buffer_index, Len, I: dword;
  Data, P: PByteArray;
  buf: PQueueBuffer;
  bi: TBufferInfo;
  rx: PVirtQueue;
begin
  rx := @Drv.VirtQueues[RX_QUEUE];
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
    bi.size := VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr);
    bi.buffer := Pointer(buf.address);
    bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi.copy := false;

    VirtIOSendBuffer(Drv.Base, RX_QUEUE, rx, @bi, 1);
    ReadWriteBarrier;
  end;
end;

procedure VirtIOVSocketHandler;
var
  r: DWORD;
begin
  r := GetIntStatus(VirtIOVSocketDev.Base);
  // TODO: to understand why I am missing interruptions
  // if (r^ and 1 = 1) then
  // begin
    VirtIOProcessRxQueue (@VirtIOVSocketDev);
    VirtIOProcessTxQueue (@VirtIOVSocketDev);
  // end;
  SetIntACK(VirtIOVSocketDev.Base, r);
  eoi_apic;
end;

// TODO: Use net to get the IRQ
procedure VirtIOVSocketStart(net: PNetworkInterface);
begin
  IOApicIrqOn(VirtIOVSocketDev.IRQ);
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

  Net.OutgoingPackets := Packet;
  // TODO: Remove the use of VirtIOVSocketDev
  VirtIOSendBuffer(VirtIOVSocketDev.Base, TX_QUEUE, @VirtIOVSocketDev.VirtQueues[TX_QUEUE], @bi, 1);
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

procedure FindVirtIOSocketonMMIO;
var
  magic, device, version, guestid: ^DWORD;
  tx: PVirtQueue;
  Net: PNetworkInterface;
begin
  magic := Pointer(BASE_MICROVM_MMIO);
  version := Pointer(BASE_MICROVM_MMIO + MMIO_VERSION);

  if (magic^ = MMIO_SIGNATURE) and (version^ = MMIO_LEGACY) then
  begin
    device := Pointer(BASE_MICROVM_MMIO + MMIO_DEVICEID);
    if device^ = VIRTIO_ID_VSOCKET then
    begin
      VirtIOVSocketDev.IRQ := IRQ_MICROVM_MMIO;
      VirtIOVSocketDev.Base := BASE_MICROVM_MMIO;

      // reset
      SetDeviceStatus(VirtIOVSocketDev.Base, 0);

      // tell driver we found it
      SetDeviceStatus(VirtIOVSocketDev.Base, VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER);

      // get cid
      guestid := Pointer(VirtIOVSocketDev.Base + MMIO_GUESTID);
      VirtIOVSocketDev.GuestID := guestid^;
      WriteConsoleF('VirtIOVSocket: CID: %d\n',[VirtIOVSocketDev.GuestID]);

      SetDeviceGuestPageSize(VirtIOVSocketDev.Base, PAGE_SIZE);

      if VirtIOInitQueue(VirtIOVSocketDev.Base, RX_QUEUE, @VirtIOVSocketDev.VirtQueues[RX_QUEUE], VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr)) then
        WriteConsoleF('VirtIOVSocket: RX_QUEUE has been initializated\n', [])
      else
        WriteConsoleF('VirtIOVSocket: RX_QUEUE has not been initializated\n', []);

      if VirtIOInitQueue(VirtIOVSocketDev.Base, EVENT_QUEUE, @VirtIOVSocketDev.VirtQueues[EVENT_QUEUE], sizeof(TVirtIOVSockEvent)) then
        WriteConsoleF('VirtIOVSocket: EVENT_QUEUE has been initializated\n', [])
      else
        WriteConsoleF('VirtIOVSocket: EVENT_QUEUE has not been initializated\n', []);

      if VirtIOInitQueue(VirtIOVSocketDev.Base, TX_QUEUE, @VirtIOVSocketDev.VirtQueues[TX_QUEUE], 0) then
        WriteConsoleF('VirtIOVSocket: TX_QUEUE has been initializated\n', [])
      else
        WriteConsoleF('VirtIOVSocket: TX_QUEUE has not been initializated\n', []);

      // set up buffers for transmission
      tx := @VirtIOVSocketDev.VirtQueues[TX_QUEUE];
      tx.buffer := ToroGetMem((VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr)) * tx.queue_size + PAGE_SIZE);
      tx.buffer := Pointer(PtrUInt(tx.buffer) + (PAGE_SIZE - PtrUInt(tx.buffer) mod PAGE_SIZE));
      tx.chunk_size:= VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr);

      // driver is alive
      SetDeviceStatus(VirtIOVSocketDev.Base, VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_DRIVER_OK);

      CaptureInt(BASE_IRQ + VirtIOVSocketDev.IRQ, @VirtIOVSocketIrqHandler);
      Net := @VirtIOVSocketDev.Driverinterface;
      Net.Name := 'virtiovsocket';
      Net.start := @VirtIOVSocketStart;
      Net.send := @VirtIOVSocketSend;
      Net.TimeStamp := 0;
      Net.SocketType := SCK_VIRTIO;
      Net.Minor := VirtIOVSocketDev.GuestID;
      RegisterNetworkInterface(Net);
      WriteConsoleF('VirtIOVSocket: driver registered\n',[]);
    end;
  end;
end;

initialization
  FindVirtIOSocketonMMIO;
end.
