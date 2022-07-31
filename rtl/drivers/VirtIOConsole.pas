//
// VirtIOConsole.pas
//
// This unit contains the driver for virtio-console.
// The driver is implemented without interruptions.
// The read and write are protected by using a Read/Write Lock.
//
// Copyright (c) 2003-2021 Matias Vara <matiasevara@gmail.com>
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

unit VirtIOConsole;

interface

{$I ..\Toro.inc}

{$IFDEF EnableDebug}
       //{$DEFINE DebugVirtioConsole}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, VirtIO, Console, Network, Process, Memory;

const
  RX_QUEUE = 0;
  TX_QUEUE = 1;
  VIRTIO_CONSOLE_MAX_PKT_BUF_SIZE = 100;
  VIRTIO_ID_CONSOLE = 3;
  QUEUE_LEN = 32;

type
    PVirtIOConsoleDevice = ^TVirtIOConsoleDevice;

    TVirtIOConsoleDevice = record
      IRQ: LongInt;
      Base: QWORD;
      VirtQueues: array[0..1] of TVirtQueue;
    end;

procedure virtIOConsoleSend(Packet: PPacket);
function virtIOConsoleRead(buff: PChar; len: LongInt): LongInt;

var
  VirtIOConsoleDev: TVirtIOConsoleDevice;
  Packets: PPacket = nil;
  LastPacket: PPacket = nil;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

var
  WriteLockConsole: UInt64 = 3;
  ReadLockConsole: UInt64 = 3;

type
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;

procedure virtIOConsoleSend(Packet: PPacket);
var
  bi: TBufferInfo;
  index, norm_index, buffer_index: Word;
  vq: PVirtQueue;
  tmp: PQueueBuffer;
begin
  SpinLock (3, 4, WriteLockConsole);
  vq := @VirtIOConsoleDev.VirtQueues[TX_QUEUE];
  bi.buffer := Packet.Data;
  bi.size := Packet.Size;
  bi.flags := 0;
  bi.copy := true;
  Inc(vq.last_used_index);
  VirtIOAddBuffer(VirtIOConsoleDev.Base, vq, @bi, 1);

  while (vq.last_used_index <> vq.used.index) do;

  index := vq.last_used_index;
  norm_index := index mod vq.queue_size;
  buffer_index := vq.used.rings[norm_index].index;
  tmp := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));
  // mark buffer as free
  tmp.length:= 0;
  Inc(vq.free_nr_desc);
  WriteLockConsole := 3;
end;

var
  offset: DWORD = 0;
  CurrentPacket : PPacket = nil;

function virtIOConsoleRead(buff: PChar; len: LongInt): LongInt;
var
  vq: PVirtQueue;
  M: Pchar;
  Packet: PPacket;
  index, buffer_index, PacketSize, I, count: dword;
  Data, P: PByteArray;
  buf: PQueueBuffer;
  bi: TBufferInfo;
begin
  Result := len;
  SpinLock (3, 4, ReadLockConsole);
  while len > 0 do
  begin
    if (CurrentPacket = nil) or (offset > CurrentPacket.size -1) then
    begin
      vq := @VirtIOConsoleDev.VirtQueues[RX_QUEUE];
      while (vq.last_used_index = vq.used.index) do;
      index := vq.last_used_index mod vq.queue_size;
      buffer_index := vq.used.rings[index].index;

      buf := vq.buffers;
      Inc(buf, buffer_index);
      Inc(vq.free_nr_desc);

      P := Pointer(buf.address);
      PacketSize := vq.used.rings[index].length;
      if CurrentPacket <> nil then
        ToroFreeMem(CurrentPacket);
      Packet := ToroGetMem(PacketSize+SizeOf(TPacket));

      if (Packet <> nil) then
      begin
        Packet.data:= Pointer(PtrUInt(Packet) + SizeOf(TPacket));
        Packet.size:= PacketSize;
        Packet.Delete:= False;
        Packet.Ready:= False;
        Packet.Next:= nil;
        Data := Packet.data;
        for I := 0 to PacketSize-1 do
          Data^[I] := P^[I];
      end;

      // return the buffer
      bi.size := VIRTIO_CONSOLE_MAX_PKT_BUF_SIZE;
      bi.buffer := Pointer(buf.address);
      bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
      bi.copy := false;

      VirtIOAddBuffer(VirtIOConsoleDev.Base, vq, @bi, 1);
      Inc(vq.last_used_index);
      CurrentPacket := Packet;
      offset := 0;
    end;
    if Len > CurrentPacket.size - offset then
      count := CurrentPacket.size - offset
    else
      count := Len;
    M := CurrentPacket.data + offset;
    for I := 0 to count-1 do
    begin
      buff^ := M^;
      Inc(buff);
      Inc(M);
    end;
    Inc(offset, count);
    Dec(Len, count);
  end;
  ReadLockConsole := 3;
end;

function InitVirtIOConsole (Device: PVirtIOMMIODevice): Boolean;
var
  tx: PVirtQueue;
begin
  Result := False;
  VirtIOConsoleDev.IRQ := Device.Irq;
  VirtIOConsoleDev.Base := Device.Base;

  if not VirtIOInitQueue(VirtIOConsoleDev.Base, RX_QUEUE, @VirtIOConsoleDev.VirtQueues[RX_QUEUE], QUEUE_LEN, VIRTIO_CONSOLE_MAX_PKT_BUF_SIZE) then
  begin
    WriteConsoleF('VirtIOConsole: RX_QUEUE has not been initializated\n', []);
    Exit;
  end;

  if not VirtIOInitQueue(VirtIOConsoleDev.Base, TX_QUEUE, @VirtIOConsoleDev.VirtQueues[TX_QUEUE], QUEUE_LEN, 0) then
  begin
    WriteConsoleF('VirtIOConsole: TX_QUEUE has not been initializated\n', []);
    Exit;
  end;

  // disable interruptions
  VirtIOConsoleDev.VirtQueues[RX_QUEUE].available.flags := 1;
  VirtIOConsoleDev.VirtQueues[TX_QUEUE].available.flags := 1;

  tx := @VirtIOConsoleDev.VirtQueues[TX_QUEUE];
  tx.buffer := ToroGetMem(VIRTIO_CONSOLE_MAX_PKT_BUF_SIZE * tx.queue_size + PAGE_SIZE);
  tx.buffer := Pointer(PtrUInt(tx.buffer) + (PAGE_SIZE - PtrUInt(tx.buffer) mod PAGE_SIZE));
  tx.chunk_size := VIRTIO_CONSOLE_MAX_PKT_BUF_SIZE;

  Device.Vqs := @VirtIOConsoleDev.VirtQueues[RX_QUEUE];
  VirtIOConsoleDev.VirtQueues[RX_QUEUE].VqHandler := nil;
  VirtIOConsoleDev.VirtQueues[TX_QUEUE].VqHandler := nil;
  VirtIOConsoleDev.VirtQueues[RX_QUEUE].Next := @VirtIOConsoleDev.VirtQueues[TX_QUEUE];
  VirtIOConsoleDev.VirtQueues[TX_QUEUE].Next := nil;

  WriteConsoleF('VirtIOConsole: Initiated\n', []);

  Result := True;
end;


initialization
  InitVirtIODriver(VIRTIO_ID_CONSOLE, @InitVirtIOConsole);
end.
