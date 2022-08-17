//
// VirtIOBus.pas
//
// This unit contains the VirtIOBus frontend and backend.
// This driver allows to communicate cores through VirtIO.
//
// Copyright (c) 2003-2022 Matias Vara <matiasevara@gmail.com>
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

unit VirtIOBus;

interface

{$I ..\Toro.inc}

{$IFDEF EnableDebug}
       //{$DEFINE DebugVirtioFS}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, VirtIO, Console, Network, Process, Memory;

const
  VIRTIO_CPU_MAX_PKT_BUF_SIZE = 1024;
  QUEUE_LEN = 10;
  RX_QUEUE = 0;

type
  TVirtIOCPU = record
    QueueRx: array[0..MAX_CPU-1] of TVirtQueue;
    QueueTx: array[0..MAX_CPU-1] of TVirtQueue;
    BufferLen: DWORD;
    NrDesc: DWORD;
  end;

var
  VirtIOCPUs: array[0..MAX_CPU-1] of TVirtIOCPU;
  mmioconf: Pointer;

procedure SendTo(Core: DWORD; Buffer: Pointer; Len: DWORD);
procedure RecvFrom(Core: DWORD; Buffer: Pointer);

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

// This handler executes in each core when producer adds a desc in the used ring
procedure VirtIOInterHandler;
var
  index, buffer_index: WORD;
  Len, id, cpu: DWORD;
  bi: TBufferInfo;
  buf: PQueueBuffer;
begin
  id := GetCoreId;
  // check what rx vq needs attention
  for cpu := 0 to CPU_COUNT-1 do
  begin
    // check all rx queues of the current core
    if cpu = id then
      Continue;
    // continue if queue is empty
    if (VirtIOCPUs[id].QueueRx[cpu].last_used_index = VirtIOCPUs[id].QueueRx[cpu].used.index) then
      Continue;
    while (VirtIOCPUs[id].QueueRx[cpu].last_used_index <> VirtIOCPUs[id].QueueRx[cpu].used.index) do
    begin
      index := VirtIOGetBuffer(@VirtIOCPUs[id].QueueRx[cpu]);
      buffer_index := VirtIOCPUs[id].QueueRx[cpu].used.rings[index].index;
      buf := VirtIOCPUs[id].QueueRx[cpu].buffers;
      Inc(buf, buffer_index);
      Len := VirtIOCPUs[id].QueueRx[cpu].used.rings[index].length;
      WriteConsoleF('%d Core[%d] -> Core[%d]: Buffer Len %d, content: %p\n', [read_rdtsc, cpu, id, Len, buf.address]);
      bi.size := Len;
      bi.buffer := Pointer(buf.address);
      bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
      bi.copy := false;
      VirtIOAddBuffer(PtrUInt(mmioconf), @VirtIOCPUs[id].QueueRx[cpu], @bi, 1);
    end;
  end;
  eoi_apic;
end;

procedure VirtIOInterIrqHandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
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
  xor rcx , rcx
  Call VirtIOInterHandler
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

procedure NotifyFrontEnd(Core: DWORD);
begin
  send_apic_int(Core, INTER_CORE_IRQ);
end;

procedure SendTo(Core: DWORD; Buffer: Pointer; Len: DWORD);
var
  tmp: PQueueBuffer;
  buffer_index: WORD;
begin
  tmp := VirtIOGetAvailBuffer(@VirtIOCPUs[GetCoreId].QueueTx[core], buffer_index);
  Move(Pchar(Buffer)^, Pchar(tmp.address)^, Len);
  VirtIOAddConsumedBuffer(@VirtIOCPUs[GetCoreId].QueueTx[core], buffer_index, tmp.length);
  // NotifyFrontEnd(Core);
end;

procedure RecvFrom(Core: DWORD; Buffer: Pointer);
var
  index, buffer_index: WORD;
  id, Len: DWORD;
  bi: TBufferInfo;
  buf: PQueueBuffer;
begin
  id := GetCoreId;

  while (VirtIOCPUs[id].QueueRx[core].last_used_index = VirtIOCPUs[id].QueueRx[core].used.index) do ThreadSwitch;

  index := VirtIOGetBuffer(@VirtIOCPUs[id].QueueRx[core]);

  buffer_index := VirtIOCPUs[id].QueueRx[core].used.rings[index].index;
  buf := VirtIOCPUs[id].QueueRx[core].buffers;
  Inc(buf, buffer_index);
  Len := VirtIOCPUs[id].QueueRx[core].used.rings[index].length;

  Move(Pchar(buf.address)^, Pchar(Buffer)^, Len);

  bi.size := Len;
  bi.buffer := Pointer(buf.address);
  bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
  bi.copy := false;

  VirtIOAddBuffer(PtrUInt(mmioconf), @VirtIOCPUs[id].QueueRx[core], @bi, 1);
end;

procedure InitVirtIOBus;
var
  queuemax: ^DWORD;
  cpu, rxi, txi: DWORD;
begin
  mmioconf := ToroGetMem($0fc * sizeof(DWORD));
  FillByte(mmioconf^, $fc * sizeof(DWORD), 0);
  queuemax := Pointer(PtrUInt(mmioconf) + MMIO_QUEUENUMMAX);
  queuemax^ := QUEUE_LEN;

  // Initialize RX queues
  for cpu := 0 to CPU_COUNT-1 do
  begin
    for rxi := 0 to CPU_COUNT-1 do
    begin
      if rxi = cpu then
        Continue;
      if VirtIOInitQueue(PtrUInt(mmioconf), RX_QUEUE, @VirtIOCPUs[cpu].QueueRx[rxi], QUEUE_LEN, VIRTIO_CPU_MAX_PKT_BUF_SIZE) then
      begin
        WriteConsoleF('VirtIOBus: Core[%d]->Core[%d] queue has been initiated\n', [rxi, cpu]);
      end;
    end;
  end;

  // Initialize TX queues
  for cpu := 0 to CPU_COUNT-1 do
  begin
    for txi := 0 to CPU_COUNT-1 do
    begin
      if txi = cpu then
        Continue;
      FillByte(VirtIOCPUs[cpu].QueueTx[txi], sizeof(TVirtQueue), 0);
      VirtIOCPUs[cpu].QueueTx[txi].buffers := VirtIOCPUs[txi].QueueRx[cpu].buffers;
      VirtIOCPUs[cpu].QueueTx[txi].available := VirtIOCPUs[txi].QueueRx[cpu].available;
      VirtIOCPUs[cpu].QueueTx[txi].queue_size := VirtIOCPUs[txi].QueueRx[cpu].queue_size;
      VirtIOCPUs[cpu].QueueTx[txi].used := VirtIOCPUs[txi].QueueRx[cpu].used;
    end;
  end;

  // Capture inter-core irq in all cores
  CaptureInt(INTER_CORE_IRQ, @VirtIOInterIrqHandler);
end;

initialization
  InitVirtIOBus;
end.
