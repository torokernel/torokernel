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

  NR_VSOCKDEV = 1;
  PAGE_SIZE = 4096;
  MMIO_GUESTID = $100;
  QUEUE_LEN = 32;

var
  VirtIOVSocketDev: array[0..NR_VSOCKDEV-1] of TVirtIOVSocketDevice;
  VSockCount: LongInt;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

procedure VirtIOProcessTxQueue(vq: PVirtQueue);
var
  index, buffer_index: Word;
  tmp: PQueueBuffer;
  Packet: PPacket;
begin
  UpdateLastIrq;
  index := VirtIOGetBuffer(vq);
  buffer_index := vq.used.rings[index].index;
  tmp := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));
  // inform kernel that Packet has been sent
  Packet := Pointer(tmp.address - sizeof(TPacket));
  DequeueOutgoingPacket(Packet);
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
  Dev: PVirtIOVSocketDevice;
begin
   UpdateLastIrq;
   index := VirtIOGetBuffer(vq);
   buffer_index := vq.used.rings[index].index;

   Dev := vq.Device;

   buf := vq.buffers;
   Inc(buf, buffer_index);

   P := Pointer(buf.address);
   Len := vq.used.rings[index].length;

   Packet := AllocatePacket(Len);

   if Packet <> nil then
   begin
     Data := Packet.Data;
     for I := 0 to Len-1 do
       Data^[I] := P^[I];
     EnqueueIncomingPacket(Packet);
   end;

    // return the buffer
    bi.size := VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr);
    bi.buffer := Pointer(buf.address);
    bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi.copy := false;

    VirtIOAddBuffer(Dev.Base, vq, @bi, 1);
end;

procedure VirtIOVSocketStart(Net: PNetworkInterface);
var
  Dev: PVirtIOVSocketDevice;
begin
  Dev := Net.Device;
  IOApicIrqOn(Dev.IRQ);
end;

procedure virtIOVSocketSend(Net: PNetworkInterface; Packet: PPacket);
var
  bi: TBufferInfo;
  Dev: PVirtIOVSocketDevice;
begin
  DisableInt;
  Dev := Net.Device;
  bi.buffer := Packet.Data;
  bi.size := Packet.Size;
  bi.flags := 0;
  // use Packet.Data in descriptor
  bi.copy := false;
  VirtIOAddBuffer(Dev.Base, @Dev.VirtQueues[TX_QUEUE], @bi, 1);
  RestoreInt;
end;

function InitVirtIOVSocket (Device: PVirtIOMMIODevice): Boolean;
var
  guestid: ^DWORD;
  tx: PVirtQueue;
  Net: PNetworkInterface;
  Dev: PVirtIOVSocketDevice;
begin
  Result := False;
  if VSockCount = NR_VSOCKDEV then
    Exit;

  Dev := @VirtIOVSocketDev[VSockCount];

  Dev.IRQ := Device.Irq;
  Dev.Base := Device.Base;
  guestid := Pointer(Dev.Base + MMIO_GUESTID);
  Dev.GuestID := guestid^;
  WriteConsoleF('VirtIOVSocket: cid=%d\n',[Dev.GuestID]);

  if not VirtIOInitQueue(Dev.Base, RX_QUEUE, @Dev.VirtQueues[RX_QUEUE], QUEUE_LEN, VIRTIO_VSOCK_MAX_PKT_BUF_SIZE + sizeof(TVirtIOVSockHdr)) then
  begin
    WriteConsoleF('VirtIOVSocket: RX_QUEUE has not been initializated\n', []);
    Exit;
  end;

  if not VirtIOInitQueue(Dev.Base, EVENT_QUEUE, @Dev.VirtQueues[EVENT_QUEUE], QUEUE_LEN, sizeof(TVirtIOVSockEvent)) then
  begin
    WriteConsoleF('VirtIOVSocket: EVENT_QUEUE has not been initializated\n', []);
    Exit;
  end;

  if not VirtIOInitQueue(Dev.Base, TX_QUEUE, @Dev.VirtQueues[TX_QUEUE], QUEUE_LEN, 0) then
  begin
    WriteConsoleF('VirtIOVSocket: TX_QUEUE has not been initializated\n', []);
    Exit;
  end;

  Device.Vqs := @Dev.VirtQueues[RX_QUEUE];
  Dev.VirtQueues[RX_QUEUE].VqHandler := @VirtIOProcessRxQueue;
  Dev.VirtQueues[RX_QUEUE].Device := Dev;

  Dev.VirtQueues[TX_QUEUE].VqHandler := @VirtIOProcessTxQueue;
  Dev.VirtQueues[TX_QUEUE].Device := Dev;

  Dev.VirtQueues[RX_QUEUE].Next := @Dev.VirtQueues[TX_QUEUE];
  Dev.VirtQueues[TX_QUEUE].Next := nil;

  Net := @Dev.Driverinterface;

  Net.Device := Dev;
  Net.Name := 'virtiovsocket';
  Net.start := @VirtIOVSocketStart;
  Net.send := @VirtIOVSocketSend;
  Net.Minor := Dev.GuestID;
  RegisterNetworkInterface(Net);
  Inc(VSockCount);
  Result := True;
end;

initialization
 VSockCount := 0;
 InitVirtIODriver(VIRTIO_ID_VSOCKET, @InitVirtIOVSocket);
end.
