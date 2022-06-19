//
// Inter-core communication example by using VirtIO
//
// This example shows the use of VirtIO to communicate cores.
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

program InterCoreCom;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

// only include the needed units
uses
 Kernel,
 Process,
 Memory,
 Debug,
 Arch,
 Filesystem,
 {$IFDEF UseGDBstub}VirtIO,{$ENDIF}
 Network,
 {$IFDEF UseGDBstub}VirtIOConsole,
 Gdbstub,
 {$ENDIF}
 VirtIO,
 Console;

{$asmmode intel}
var
  vq: TVirtQueue;
  tmp: TThreadId;
  mmiolay: ^DWORD;
  queuemax: ^DWORD;

procedure VirtIOInterHandler;
var
  index, buffer_index: WORD;
  Len: DWORD;
  bi: TBufferInfo;
  buf: PQueueBuffer;
begin
  // empty queue?
  if (vq.last_used_index = vq.used.index) then
    Exit;
  while (vq.last_used_index <> vq.used.index) do
  begin
   index := VirtIOGetBuffer(@vq);
   buffer_index := vq.used.rings[index].index;

   buf := vq.buffers;
   Inc(buf, buffer_index);

   Len := vq.used.rings[index].length;

   WriteConsoleF('Core[1] -> Core[0]: Buffer Len %d, Content: %p\n', [Len, buf.address]);

   // TODO: el buffer tiene q ser copiado al usuario
   // return the buffer
   bi.size := Len;
   bi.buffer := Pointer(buf.address);
   bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
   bi.copy := false;

   VirtIOAddBuffer(PtrUInt(mmiolay), 0, @vq, @bi, 1);
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

function Thread(param: Pointer): PtrInt;
var
  vq: TVirtQueue;
  pvq: PVirtQueue;
  index, buffer_index : Word;
  tmp: PQueueBuffer;
  p: PChar;
  i: LongInt;
begin
  // TODO: use mmio region as param

  FillByte(vq, sizeof(vq), 0);
  pvq := PVirtQueue(param);

  // TODO: init this by using mmio
  vq.buffers := pvq.buffers;
  vq.available := pvq.available;
  vq.queue_size := pvq.queue_size;
  vq.used := pvq.used;

  i := 0;
  while true do
  //for i:= 0 to 200 do
  begin
  // la unica condicion de salida es si son iguales, si son iguales
  // no hay ningun desc en avail
  if vq.available.index > vq.last_available_index then
  begin
    Delay(100);

    // VirtIOGetAvailBuffer(vq, buffer)
    // a priori no sabes si hay nuevos desc en avail
    // si el front no carga avail podemos qdarnos sin
    // descriptores y no lo vamos a saber
    // necesitamos un metodo para saber q hay desriptores
    // en el avail ring
    // o un timeout si no hay descriptores para
    // esperar hasta que haya
    index := vq.last_available_index mod vq.queue_size;
    buffer_index := vq.available.rings[index];

    tmp := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));

    Inc(vq.last_available_index);

    p := Pointer(tmp.address);

    p[0] := 't';
    p[1] := 'o';
    p[2] := 'r';
    p[3] := 'o';
    p[4] := Char(Byte('0')+i mod 10);
    p[5] := #0;

    Inc(i);

    // VirtIOAddConsumedBuffer(vq, buffer_index)
    index := vq.used.index mod vq.queue_size;
    vq.used.rings[index].index := buffer_index;
    vq.used.rings[index].length := tmp.length;
    Inc(vq.used.index);

    // TODO: memory barrier
    send_apic_int(0, INTER_CORE_IRQ);

  end;
  end;

  While True do;
end;

begin
  // Configuration atomicity value is the last element
  mmiolay := ToroGetMem($0fc * sizeof(DWORD));
  FillByte(mmiolay^, $fc * sizeof(DWORD), 0);
  queuemax := Pointer(PtrUInt(mmiolay) + MMIO_QUEUENUMMAX);
  queuemax^ := 50;

  // this is a rx queue with max 5 desc with 128 buffers
  if VirtIOInitQueue(PtrUInt(mmiolay), 0, @vq, 50, 128) then
  begin
     WriteConsoleF('VirtIO: RX queue has been initiated\n', []);
  end;

  CaptureInt(INTER_CORE_IRQ, @VirtIOInterIrqHandler);
  tmp := BeginThread(nil, 4096, Thread, @vq, 1, tmp);
  ThreadSwitch;

  while true do;
end.
