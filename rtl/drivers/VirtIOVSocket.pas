//
// VirtIOVSocket.pas
//
// This unit contains code for the VirtIOVSocket driver.
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
  Arch, VirtIO, Console, Network, Process, Memory;

type
  PVirtIOVSocketDevice = ^TVirtIOVSocketDevice;

  TVirtIOVSocketDevice = record
    IRQ: LongInt;
    Base: QWORD;
    VirtQueues: array[0..2] of TVirtQueue;
    GuestId: QWORD;
    Driverinterface: TNetworkInterface;
  end;

const
  VIRTIO_ID_VSOCKET = 19;
  FRAME_SIZE = 1526;
  VIRTIO_VSOCK_MAX_PKT_BUF_SIZE = 1024 * 64;
  RX_QUEUE = 0;
  TX_QUEUE = 1;
  EVENT_QUEUE = 2;

  PAGE_SIZE = 4096;
  MMIO_GUESTID = $100;
  QUEUE_LEN = 32;

var
  VirtIOVSocketDev: TVirtIOVSocketDevice;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

procedure VirtIOProcessTxQueue(vq: PVirtQueue);
var
  index, buffer_index: Word;
  tmp: PQueueBuffer;
begin
  UpdateLastIrq;
  index := VirtIOGetBuffer(vq);

  buffer_index := vq.used.rings[index].index;
  tmp := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));

  // mark buffer as free
  tmp.length:= 0;

  ReadWriteBarrier;
end;

type
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;

procedure VirtIOProcessRxQueue(vq: PVirtQueue);
var
  Packet: PPacket;
  index, buffer_index, Len, I: word;
  Data, P: PByteArray;
  buf: PQueueBuffer;
  bi: TBufferInfo;
begin
   UpdateLastIrq;
   index := VirtIOGetBuffer(vq);
   buffer_index := vq.used.rings[index].index;

   buf := vq.buffers;
   Inc(buf, buffer_index);

   P := Pointer(buf.address);
   Len := vq.used.rings[index].length;

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

    // return the buffer
    bi.size := VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr);
    bi.buffer := Pointer(buf.address);
    bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi.copy := false;

    VirtIOAddBuffer(VirtIOVSocketDev.Base, vq, @bi, 1);
    ReadWriteBarrier;
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
  VirtIOAddBuffer(VirtIOVSocketDev.Base, @VirtIOVSocketDev.VirtQueues[TX_QUEUE], @bi, 1);
  DequeueOutgoingPacket;
  RestoreInt;
end;

function InitVirtIOVSocket (Device: PVirtIOMMIODevice): Boolean;
var
  guestid: ^DWORD;
  tx: PVirtQueue;
  Net: PNetworkInterface;
begin
  Result := False;
  VirtIOVSocketDev.IRQ := Device.Irq;
  VirtIOVSocketDev.Base := Device.Base;
  guestid := Pointer(VirtIOVSocketDev.Base + MMIO_GUESTID);
  VirtIOVSocketDev.GuestID := guestid^;
  WriteConsoleF('VirtIOVSocket: cid=%d\n',[VirtIOVSocketDev.GuestID]);

  if not VirtIOInitQueue(VirtIOVSocketDev.Base, RX_QUEUE, @VirtIOVSocketDev.VirtQueues[RX_QUEUE], QUEUE_LEN, VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr)) then
  begin
    WriteConsoleF('VirtIOVSocket: RX_QUEUE has not been initializated\n', []);
    Exit;
  end;

  if not VirtIOInitQueue(VirtIOVSocketDev.Base, EVENT_QUEUE, @VirtIOVSocketDev.VirtQueues[EVENT_QUEUE], QUEUE_LEN, sizeof(TVirtIOVSockEvent)) then
  begin
    WriteConsoleF('VirtIOVSocket: EVENT_QUEUE has not been initializated\n', []);
    Exit;
  end;

  if not VirtIOInitQueue(VirtIOVSocketDev.Base, TX_QUEUE, @VirtIOVSocketDev.VirtQueues[TX_QUEUE], QUEUE_LEN, 0) then
  begin
    WriteConsoleF('VirtIOVSocket: TX_QUEUE has not been initializated\n', []);
    Exit;
  end;

  tx := @VirtIOVSocketDev.VirtQueues[TX_QUEUE];
  tx.buffer := ToroGetMem((VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr)) * tx.queue_size + PAGE_SIZE);
  tx.buffer := Pointer(PtrUInt(tx.buffer) + (PAGE_SIZE - PtrUInt(tx.buffer) mod PAGE_SIZE));
  tx.chunk_size:= VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr);

  Device.Vqs := @VirtIOVSocketDev.VirtQueues[RX_QUEUE];
  VirtIOVSocketDev.VirtQueues[RX_QUEUE].VqHandler := @VirtIOProcessRxQueue;
  VirtIOVSocketDev.VirtQueues[TX_QUEUE].VqHandler := @VirtIOProcessTxQueue;

  VirtIOVSocketDev.VirtQueues[RX_QUEUE].Next := @VirtIOVSocketDev.VirtQueues[TX_QUEUE];
  VirtIOVSocketDev.VirtQueues[TX_QUEUE].Next := nil;

  Net := @VirtIOVSocketDev.Driverinterface;
  Net.Name := 'virtiovsocket';
  Net.start := @VirtIOVSocketStart;
  Net.send := @VirtIOVSocketSend;
  Net.Minor := VirtIOVSocketDev.GuestID;
  RegisterNetworkInterface(Net);
  Result := True;
end;

initialization
 InitVirtIODriver(VIRTIO_ID_VSOCKET, @InitVirtIOVSocket);
end.
