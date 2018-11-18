//
// VirtIONet.pas
//
// This unit contains the driver for virtio network card.
//
// Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
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

unit VirtIONet;

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
  PVirtIONetwork= ^TVirtIONetwork;

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

  TVirtIONetwork = record
    Driverinterface: TNetworkInterface;
    IRQ: LongInt;
    Regs: Pointer;
    VirtQueues: array[0..15] of TVirtQueue;
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
  FRAME_SIZE = 1526;
  VIRTIO_DESC_FLAG_WRITE_ONLY = 2;
  VIRTIO_DESC_FLAG_NEXT = 1;
  VIRTIO_NET_HDR_F_NEEDS_CSUM = 1;
  TX_QUEUE = 1;
  RX_QUEUE = 0;

var
  NicVirtIO: TVirtIONetwork;


procedure virtIOStart(net: PNetworkInterface);
begin
  // enable irq
  IrqOn(NicVirtIO.IRQ);
end;

procedure virtIOStop(net: PNetworkInterface);
begin
  // disable irq
  IrqOff(NicVirtIO.IRQ);
end;

procedure virtIOReset(net: PNetworkInterface);
begin
  // reset device
  write_portb(0, PtrUInt(NicVirtIO.Regs) + $12);
end;


// Process transmission buffers
procedure VirtIOProcessTx(Nic: PVirtIONetwork);
var
  vq: PVirtQueue;
  index, norm_index, buffer_index: Word;
  tmp: PQueueBuffer;
begin
  vq := @Nic.VirtQueues[1];

  {$IFDEF DebugVirtio}WriteDebug('VirtIOProcessTx: queue: %d, last_used: %d, used_idx: %d\n',[1, vq.last_used_index, vq.used.index]);{$ENDIF}

  ReadWriteBarrier;

  if (vq.last_used_index = vq.used.index) then
  begin
     Exit;
  end;

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

procedure VirtIOSendBuffer(Nic: PVirtIONetwork; queue_index: word; bi:PBufferInfo; count: QWord);
var
  index, buffer_index, next_buffer_index: word;
  vq: PVirtQueue;
  buf: ^Byte;
  b: PBufferInfo;
  i: LongInt;
  tmp: PQueueBuffer;
begin
  vq := @Nic.VirtQueues[queue_index];

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
      write_portw(queue_index, PtrUInt(Nic.Regs) + $10);

  {$IFDEF DebugVirtio}WriteDebug('VirtIOSendBuffer: queue: %d, vq.available.index: %d, vq.used.index: %d\n',[queue_index, vq.available.index, vq.used.index]);{$ENDIF}
end;


type
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;

procedure VirtIOProcessRx(Net: PVirtIONetwork);
var
  Packet: PPacket;
  rx: PVirtQueue;
  index, buffer_index, Len, I: dword;
  Data, P: PByteArray;
  buf: PQueueBuffer;
  bi: TBufferInfo;
begin
  rx := @Net.VirtQueues[0];

  ReadWriteBarrier;

  // empty queue?
  if (rx.last_used_index = rx.used.index) then
    Exit;

  while (rx.last_used_index <> rx.used.index) do
  begin
    index := rx.last_used_index mod rx.queue_size;
    buffer_index := rx.used.rings[index].index;

    buf := rx.buffers;
    Inc(buf, buffer_index);

    P := Pointer(buf.address+sizeof(TNetHeader));
    Len := rx.used.rings[index].length-sizeof(TNetHeader);

    Packet := ToroGetMem(Len+SizeOf(TPacket));

    {$IFDEF DebugVirtio}WriteDebug('VirtIOProcessRx: buf.length: %d, buf.flags: %d, add: %d, buffer_index: %d\n', [buf.length,buf.flags, buf.address, buffer_index]);{$ENDIF}

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
    bi.size := FRAME_SIZE;
    bi.buffer := Pointer(buf.address);
    bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi.copy:= false;

    VirtIOSendBuffer(Net, RX_QUEUE, @bi, 1);

    ReadWriteBarrier;
  end;
end;

procedure VirtIOHandler;
var
  r: byte;
begin
  r := read_portb(PtrUInt(NicVirtIO.Regs) + $13);
  if (r and 1 = 1) then
  begin
     VirtIOProcessRx (@NicVirtIO);
     VirtIOProcessTx (@NicVirtIO);
  end;
  {$IFDEF DebugVirtio}WriteDebug('VirtIOHandler: used.flags:%d, ava.flags:%d, r:%d\n',[NicVirtIO.VirtQueues[1].used.flags, NicVirtIO.VirtQueues[1].available.flags, r]);{$ENDIF}
  eoi;
end;


procedure virtIOSend(Net: PNetworkInterface; Packet: PPacket);
var
  bi: array[0..2] of TBufferInfo;
  n: TNetHeader;
begin
  if (Packet.Size > 1792) then
  begin
     {$IFDEF DebugVirtio}WriteDebug('virtIOSend: packet too long\n',[]);{$ENDIF}
     Exit;
  end;

  DisableInt;

  n.flags := 0;
  n.gso_type := 0;
  n.checksum_offset := 0;
  n.checksum_start := 0;

  bi[0].buffer := @n;
  bi[0].size := sizeof(TNetHeader);
  bi[0].flags := 0;
  bi[0].copy := true;

  bi[1].buffer := Packet.Data;
  bi[1].size := Packet.Size;
  bi[1].flags := 0;
  bi[1].copy := true;

  {$IFDEF DebugVirtio}WriteDebug('virtIOSend: sending packet size: %d\n',[Packet.Size]);{$ENDIF}

  // The outgoingPacket queue is not used
  // it does not verify if a packet has been sent
  Net.OutgoingPackets:= Packet;

  VirtIOSendBuffer(@NicVirtIO, TX_QUEUE, @bi[0], 2);
  DequeueOutgoingPacket;
  RestoreInt;
end;

procedure VirtIONetIrqHandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
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
  Call VirtIOHandler
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

procedure FindVirtIOonPci;
var
  PciCard: PBusDevInfo;
  features: dword;
  tmp: Byte;
  j: LongInt;
  QueueSize: Word;
  sizeOfBuffers: DWORD;
  sizeofQueueAvailable: DWORD;
  sizeofQueueUsed: DWORD;
  queuePageCount: DWORD;
  buff: PChar;
  buffPage: DWORD;
  Net: PNetworkInterface;
  rx: PVirtQueue;
  tx: PVirtQueue;
  bi: TBufferInfo;
  tmp2: Pointer;
begin
  PciCard := PCIDevices;
  DisableInt;
  while PciCard <> nil do
  begin
    if (PciCard.mainclass = $02) and (PciCard.subclass = $00) then
    begin
      if (PciCard.vendor = $1AF4) and (PciCard.device >= $1000) and (PciCard.device <= $103f) then
      begin
        NicVirtIO.IRQ := PciCard.irq;
        NicVirtIO.Regs:= Pointer(PtrUInt(PCIcard.io[0]));

        PciSetMaster(PciCard);
        WriteConsoleF('VirtIONet: /Vfound/n, irq: /V%d/n, ioport: /V%h/n\n',[NicVirtIO.IRQ, PtrUInt(NicVirtIO.Regs)]);

        // reset device
        write_portb(0, PtrUInt(NicVirtIO.Regs) + $12);

        // tell driver that we found it
        write_portb(VIRTIO_ACKNOWLEDGE, PtrUInt(NicVirtIO.Regs) + $12);
        write_portb(VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER, PtrUInt(NicVirtIO.Regs) + $12);

        // negotiation phase
        read_portd(@features, PtrUInt(NicVirtIO.Regs));

        // disable features
        features := features and not ( (1 shl VIRTIO_RING_F_INDIRECT_DESC) or (1 shl VIRTIO_MAC) or (1 shl VIRTIO_CTRL_VQ)or (1 shl VIRTIO_CSUM) or (1 shl VIRTIO_GUEST_TSO4) or (1 shl VIRTIO_GUEST_TSO6) or (1 shl VIRTIO_GUEST_UFO) or (1 shl VIRTIO_EVENT_IDX) or (1 shl VIRTIO_MRG_RXBUF));

        write_portd(@features, PtrUInt(NicVirtIO.Regs) + $4);

        {$IFDEF DebugVirtio}WriteDebug('VirtIONet: set features: %d\n',[features]);{$ENDIF}

        write_portb(VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK, PtrUInt(NicVirtIO.Regs) + $12);
        tmp := read_portb(PtrUInt(NicVirtIO.Regs) + $12);

        // check if driver accepted features
        if (tmp and VIRTIO_FEATURES_OK = 0) then
        begin
          WriteConsoleF('VirtIONet: driver did not accept features\n',[]);
          Exit;
        end
        else
          WriteConsoleF('VirtIONet: driver accepted features\n',[]);

        // setup virt queues
        for j:= 0 to 15 do
        begin
          FillByte(NicVirtIO.VirtQueues[j], sizeof(TVirtQueue),0);
          write_portw(j,  PtrUInt(NicVirtIO.Regs) + $0E);
          QueueSize := read_portw(PtrUInt(NicVirtIO.Regs) + $0C);
          if QueueSize = 0 then Continue;
          NicVirtIO.VirtQueues[j].queue_size:= QueueSize;
          sizeOfBuffers := (sizeof(TQueueBuffer) * QueueSize);
          sizeofQueueAvailable := (2*sizeof(WORD)+2) + (QueueSize*sizeof(WORD));
          sizeofQueueUsed := (2*sizeof(WORD)+2)+(QueueSize*sizeof(VirtIOUsedItem));

          // buff must be 4k aligned
          buff := ToroGetMem(sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096);
          Panic (buff=nil, 'VirtIONet: no memory for VirtIO buffer\n');
          FillByte(buff^, sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096, 0);
          buff := buff + (4096 - PtrUInt(buff) mod 4096);
          buffPage := PtrUInt(buff) div 4096;

          // 16 bytes aligned
          NicVirtIO.VirtQueues[j].buffers := PQueueBuffer(buff);

          // 2 bytes aligned
          NicVirtIO.VirtQueues[j].available := @buff[sizeOfBuffers];

          // 4 bytes aligned
          NicVirtIO.VirtQueues[j].used := PVirtIOUsed(@buff[((sizeOfBuffers + sizeofQueueAvailable+$0FFF) and not($0FFF))]) ;
          NicVirtIO.VirtQueues[j].next_buffer:= 0;
          NicVirtIO.VirtQueues[j].lock:= 0;
          write_portd(@buffPage, PtrUInt(NicVirtIO.Regs) + $08);
          NicVirtIO.VirtQueues[j].available.flags := 0;
          {$IFDEF DebugVirtio}WriteDebug('VirtIONet: queue: %d, size: %d\n',[j, QueueSize]);{$ENDIF}
        end;

        write_portb(VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK or VIRTIO_DRIVER_OK, PtrUInt(NicVirtIO.Regs) + $12);

        rx := @NicVirtIO.VirtQueues[0];
        tx := @NicVirtIO.VirtQueues[1];

        If (rx = nil) or (tx = nil) then
        begin
          WriteConsoleF('VirtIONet: tx or rx queue not found, aborting\n',[]);
          Continue;
        end;

        rx.Buffer := ToroGetMem(rx.queue_size * FRAME_SIZE + 4096);
        Panic (rx.Buffer=nil, 'VirtIONet: no memory for Rx buffer\n');
        rx.Buffer := Pointer(PtrUint(rx.Buffer) + (4096 - PtrUInt(rx.Buffer) mod 4096));
        rx.chunk_size := FRAME_SIZE;
        rx.available.index := 0;
        rx.used.index := 0;

        ReadWriteBarrier;

        write_portw(0, PtrUInt(NicVirtIO.Regs) + $10);

        // enable interruptions
        rx.used.flags :=0;

        // add all buffers in queue so we can receive data
        bi.size:= FRAME_SIZE;
        bi.buffer:= nil;
        bi.flags:= VIRTIO_DESC_FLAG_WRITE_ONLY;
        bi.copy:= True;

        for j := 0 to rx.queue_size - 1 do
        begin
          VirtIOSendBuffer(@NicVirtIO, 0, @bi, 1);
        end;

        // setup send buffers
        tx.buffer := ToroGetMem(FRAME_SIZE * tx.queue_size + 4096);
        Panic (tx.buffer=nil, 'VirtIONet: no memory for Tx buffer\n');
        tx.buffer := Pointer(PtrUInt(tx.buffer) + (4096 - PtrUInt(tx.buffer) mod 4096));
        tx.chunk_size:= FRAME_SIZE;
        tx.available.index:= 0;

        // enable interruption
        tx.available.flags := 0;

        // init to zero
        tx.used.flags := 0;

        ReadWriteBarrier;
        write_portw(1, PtrUInt(NicVirtIO.Regs) + $10);

        // get mac address
        for j := 0 to 5 do
        begin
          NicVirtIO.Driverinterface.HardAddress[j] := read_portb(PtrUInt(NicVirtIO.Regs) + $14 + j);
        end;

        WriteConsoleF('VirtIONet: mac /V%d:%d:%d:%d:%d:%d/n\n', [NicVirtIO.Driverinterface.HardAddress[0], NicVirtIO.Driverinterface.HardAddress[1],NicVirtIO.Driverinterface.HardAddress[2], NicVirtIO.Driverinterface.HardAddress[3], NicVirtIO.Driverinterface.HardAddress[4], NicVirtIO.Driverinterface.HardAddress[5]]);

        // capture the interrupt
        CaptureInt(32+NicVirtIO.IRQ, @VirtIONetIrqHandler);

        // registre network driver
        Net := @NicVirtIO.Driverinterface;
        Net.Name:= 'virtionet';
        Net.MaxPacketSize:= FRAME_SIZE;
        Net.start:= @virtIOStart;
        Net.send:= @virtIOSend;
        Net.stop:= @virtIOStop;
        Net.Reset:= @virtIOReset;
        Net.TimeStamp := 0;
        RegisterNetworkInterface(Net);
        WriteConsoleF('VirtIONet: driver registered\n',[]);
      end;
    end;
    PciCard := PciCard.Next;
  end;
  RestoreInt;
end;

initialization
  FindVirtIOonPci;

end.
