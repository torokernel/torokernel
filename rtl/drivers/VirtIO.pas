//
// VirtIO.pas
//
// This unit contains code to handle VirtIO modern devices.
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

unit VirtIO;

interface

{$I ..\Toro.inc}

{$IFDEF EnableDebug}
       //{$DEFINE DebugVirtio}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Strings, Console, Network, Process, Memory;

type
  PVirtIOMMIODevice = ^TVirtIOMMIODevice;
  PVirtQueue = ^TVirtQueue;

  TVirtIOMMIODevice = record
    Base: QWord;
    Irq: byte;
    Vqs: PVirtQueue;
  end;

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

  TVirtQueue = record
    index: WORD;
    queue_size: WORD;
    buffers: PQueueBuffer;
    available: PVirtIOAvailable;
    used: PVirtIOUsed;
    last_desc_index: word;
    last_used_index: word;
    last_available_index: word;
    free_nr_desc: word;
    buffer: PByte;
    chunk_size: dword;
    lock: QWord;
    VqHandler: Procedure(Vq: PVirtQueue);
    Device: Pointer;
    Next: PVirtQueue
  end;

  TVirtIODriver = function (device: PVirtIOMMIODevice): Boolean;

const
  MAX_MMIO_DEVICES = 4;

  MMIO_MODERN = 2;
  MMIO_VERSION = 4;
  MMIO_SIGNATURE = $74726976;
  MMIO_DEVICEID = $8;
  MMIO_QUEUENOTIFY = $50;
  MMIO_CONFIG = $100;
  MMIO_FEATURES = $10;
  MMIO_STATUS = $70;
  MMIO_GUESTFEATURES = $20;
  MMIO_SELGUESTFEATURES = $24;
  MMIO_QUEUESEL = $30;
  MMIO_QUEUENUMMAX = $34;
  MMIO_QUEUENUM = $38;
  MMIO_QUEUEREADY = $44;
  MMIO_GUESTPAGESIZE = $28;
  MMIO_QUEUEPFN = $40;
  MMIO_QUEUEALIGN = $3C;
  MMIO_INTSTATUS = $60;
  MMIO_INTACK = $64;
  MMIO_READY = $44;
  MMIO_DESCLOW = $80;
  MMIO_DESCHIGH = $84;
  MMIO_AVAILLOW = $90;
  MMIO_AVAILHIGH = $94;
  MMIO_USEDLOW = $a0;
  MMIO_USEDHIGH = $a4;

  VIRTIO_ACKNOWLEDGE = 1;
  VIRTIO_DRIVER = 2;
  VIRTIO_CTRL_VQ = 17;
  VIRTIO_MRG_RXBUF = 15;
  VIRTIO_CSUM = 0;
  VIRTIO_FEATURES_OK = 8;
  VIRTIO_DRIVER_OK = 4;
  VIRTIO_DESC_FLAG_WRITE_ONLY = 2;
  VIRTIO_DESC_FLAG_NEXT = 1;
  VIRTIO_F_VERSION_1 = 32;

procedure SetDeviceStatus(Base: QWORD; Value: DWORD);
procedure SetDeviceGuestPageSize(Base: QWORD; Value: DWORD);
function GetIntStatus(Base: QWORD): DWORD;
procedure SetIntACK(Base: QWORD; Value: DWORD);
function GetDeviceFeatures(Base: QWORD): DWORD;
procedure SetDriverFeatures(Base: QWORD; Value: DWORD);
procedure SelDriverFeatures(Base: DWORD; Value: DWORD);
function VirtIOInitQueue(Base: QWORD; QueueId: Word; Queue: PVirtQueue; QueueLen: Word; HeaderLen: DWORD): Boolean;
procedure VirtIOAddBuffer(Base: QWORD; Queue: PVirtQueue; bi:PBufferInfo; count: QWord);
procedure InitVirtIODriver(ID: DWORD; InitDriver: TVirtIODriver);
function HexStrtoQWord(start, last: PChar): QWord;
function VirtIOGetBuffer(Queue: PVirtQueue): Word;
function VirtIOGetAvailBuffer(Queue: PVirtQueue; var buffer_index: WORD): PQueueBuffer;
procedure VirtIOAddConsumedBuffer(Queue: PVirtQueue; buffer_index: WORD; Len: DWORD);

var
  VirtIOMMIODevices: array[0..MAX_MMIO_DEVICES-1] of TVirtIOMMIODevice;
  VirtIOMMIODevicesCount: LongInt = 0;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

function HexStrtoQWord(start, last: PChar): QWord;
var
  bt: Byte;
  i: PChar;
  Base: QWord;
begin
  i := start;
  Base := 0;
  while (i <> last) do
  begin
    bt := Byte(i^);
    Inc(i);
    if (bt >= Byte('0')) and (bt <= Byte('9')) then
      bt := bt - Byte('0')
    else if (bt >= Byte('a')) and (bt <= Byte('f')) then
      bt := bt - Byte('a') + 10
    else if (bt >= Byte('A')) and (bt <= Byte('F')) then
      bt := bt - Byte('A') + 10;
    Base := (Base shl 4) or (bt and $F);
  end;
  Result := Base;
end;

function StrtoByte(p1: PChar): Byte;
var
  ret: Byte;
begin
  ret := 0;
  while p1^ <> Char(0) do
  begin
    ret := ret * 10 + Byte(p1^) - Byte('0');
    Inc(p1);
  end;
  Result := ret;
end;

procedure SetDeviceStatus(Base: QWORD; Value: DWORD);
var
  status: ^DWORD;
begin
  status := Pointer(Base + MMIO_STATUS);
  status^ := Value;
end;

procedure SetDeviceGuestPageSize(Base: QWORD; Value: DWORD);
var
  GuestPageSize: ^DWORD;
begin
  GuestPageSize := Pointer(Base + MMIO_GUESTPAGESIZE);
  GuestPageSize^ := Value;
end;

function GetIntStatus(Base: QWORD): DWORD;
var
  IntStatus: ^DWORD;
begin
  IntStatus := Pointer(Base + MMIO_INTSTATUS);
  Result := IntStatus^;
end;

procedure SetIntACK(Base: QWORD; Value: DWORD);
var
  IntACK: ^DWORD;
begin
  IntACK := Pointer(Base + MMIO_INTACK);
  IntAck^ := Value;
end;

function GetDeviceFeatures(Base: QWORD): DWORD;
var
  value: ^DWORD;
begin
  value := Pointer(Base + MMIO_FEATURES);
  Result := value^;
end;

procedure SelDriverFeatures(Base: DWORD; Value: DWORD);
var
  SelFeature: ^DWORD;
begin
  SelFeature := Pointer(Base + MMIO_SELGUESTFEATURES);
  SelFeature^ := Value;
end;

procedure SetDriverFeatures(Base: QWORD; Value: DWORD);
var
  GuestFeatures: ^DWORD;
begin
  GuestFeatures := Pointer(Base + MMIO_GUESTFEATURES);
  GuestFeatures^ := Value;
end;

// Get a buffer desc from the used ring
function VirtIOGetBuffer(Queue: PVirtQueue): Word;
begin
  // TODO: add vq.last_used_index <> vq.used.index
  Panic (Queue.free_nr_desc = Queue.queue_size, 'VirtIO: Getting too many desc', []);
  Result := Queue.last_used_index mod Queue.queue_size;
  Inc(Queue.free_nr_desc);
  Inc(Queue.last_used_index);
end;

// Get a buffer desc from the avail ring
function VirtIOGetAvailBuffer(Queue: PVirtQueue; var buffer_index: WORD): PQueueBuffer;
var
  index: WORD;
begin
  Result := nil;
  if Queue.last_available_index = Queue.available.index then
    Exit;
  index := Queue.last_available_index mod Queue.queue_size;
  buffer_index := Queue.available.rings[index];
  Result := Pointer(PtrUInt(Queue.buffers) + buffer_index * sizeof(TQueueBuffer));
  Inc(Queue.last_available_index);
end;

// Add a buffer desc to the used ring
// This procedure requires to notify the consumer of this vq
procedure VirtIOAddConsumedBuffer(Queue: PVirtQueue; buffer_index: WORD; Len: DWORD);
var
  index: WORD;
begin
  index := Queue.used.index mod Queue.queue_size;
  Queue.used.rings[index].index := buffer_index;
  Queue.used.rings[index].length := Len;
  Inc(Queue.used.index);
end;

// Add a buffer desc to the avail ring
procedure VirtIOAddBuffer(Base: QWORD; Queue: PVirtQueue; bi:PBufferInfo; count: QWord);
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
  buffer_index := vq.last_desc_index;

  Panic(vq.free_nr_desc = 0, 'VirtIO: We ran out of desc', []);
  Dec(vq.free_nr_desc);

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

  vq.last_desc_index := buffer_index;
  Inc(vq.available.index);

  // notification are not needed
  // TODO: remove the use of base
  if (vq.used.flags and 1 <> 1) then
  begin
    QueueNotify := Pointer(Base + MMIO_QUEUENOTIFY);
    QueueNotify^ := vq.index;
  end;
end;

function VirtIOInitQueue(Base: QWORD; QueueId: Word; Queue: PVirtQueue; QueueLen: Word; HeaderLen: DWORD): Boolean;
var
  j: LongInt;
  QueueSize, sizeOfBuffers: DWORD;
  sizeofQueueAvailable, sizeofQueueUsed: DWORD;
  buff: PChar;
  bi: TBufferInfo;
  QueueSel: ^DWORD;
  QueueNumMax, QueueNum, AddrLow: ^DWORD;
  EnableQueue: ^DWORD;
begin
  Result := False;

  FillByte(Queue^, sizeof(TVirtQueue), 0);

  QueueSel := Pointer(Base + MMIO_QUEUESEL);
  QueueSel^ := QueueId;
  Queue.index := QueueId;

  QueueNumMax := Pointer(Base + MMIO_QUEUENUMMAX);
  QueueSize := QueueNumMax^;
  if QueueLen < QueueSize then
    QueueSize := QueueLen;
  if QueueSize = 0 then
    Exit;

  Queue.queue_size := QueueSize;
  Queue.free_nr_desc := QueueSize;

  // set queue size
  QueueNum := Pointer (Base + MMIO_QUEUENUM);
  QueueNum^ := QueueSize;

  sizeOfBuffers := 16 + sizeof(TQueueBuffer) * QueueSize;
  sizeofQueueAvailable := 2 + (QueueSize*sizeof(WORD));
  sizeofQueueUsed := 4 + (QueueSize*sizeof(VirtIOUsedItem));

  buff := ToroGetMem(sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed);
  If buff = nil then
    Exit;
  FillByte(buff^, sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed, 0);

  // 16 bytes aligned
  Queue.buffers := PQueueBuffer((PtrUint(buff) + 15) and not($f));

  // 2 bytes aligned
  Queue.available := PVirtIOAvailable((PtrUInt(buff) + sizeOfBuffers + 1) and (not 1));

  // 4 bytes aligned
  Queue.used := PVirtIOUsed((PtrUInt(buff) + sizeOfBuffers + sizeofQueueAvailable + 3) and (not 3));
  Queue.last_desc_index := 0;
  Queue.lock := 0;

  AddrLow := Pointer(Base + MMIO_DESCLOW);
  AddrLow^ := DWORD(PtrUint(Queue.buffers) and $ffffffff);
  AddrLow := Pointer(Base + MMIO_DESCHIGH);
  AddrLow^ := 0;

  AddrLow := Pointer(Base + MMIO_AVAILLOW);
  AddrLow^ := DWORD(PtrUInt(Queue.available) and $ffffffff);
  AddrLow := Pointer(Base + MMIO_AVAILHIGH);
  AddrLow^ := 0;

  AddrLow := Pointer(Base + MMIO_USEDLOW);
  AddrLow^ := DWORD(PtrUInt(Queue.used) and $ffffffff);
  AddrLow := Pointer(Base + MMIO_USEDHIGH);
  AddrLow^ := 0;

  EnableQueue := Pointer(Base + MMIO_QUEUEREADY);
  EnableQueue^ := 1;

  if HeaderLen <> 0 then
  begin
    Queue.Buffer := ToroGetMem(Queue.queue_size * HeaderLen);
    if Queue.Buffer = nil then
      Exit;
    Queue.chunk_size := HeaderLen;

    bi.size := HeaderLen;
    bi.buffer := nil;
    bi.flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
    bi.copy := True;
    for j := 0 to Queue.queue_size - 1 do
    begin
      VirtIOAddBuffer(Base, Queue, @bi, 1);
    end;
  end;

  Queue.Next := nil;

  Result := True;
end;

procedure VirtIOIRQHandler; forward;

// parse the kernel command-line to get the device tree
procedure FindVirtIOMMIODevices;
var
  j: LongInt;
  Base: QWord;
  Irq: Byte;
begin
  for j:= 0 to KernelParamCount-1 do
  begin
    if StrPos(GetKernelParam(j), 'virtio_mmio') <> Nil then
    begin
      Base := HexStrtoQWord(StrScan(GetKernelParam(j), '@') + 3 , StrScan(GetKernelParam(j), ':'));
      Irq := StrtoByte(StrScan(GetKernelParam(j), ':') + 1);
      CaptureInt(BASE_IRQ + Irq, @VirtIOIrqHandler);
      VirtIOMMIODevices[VirtIOMMIODevicesCount].Base := Base;
      VirtIOMMIODevices[VirtIOMMIODevicesCount].Irq := Irq;
      VirtIOMMIODevices[VirtIOMMIODevicesCount].Vqs := nil;
      Inc(VirtIOMMIODevicesCount);
      WriteConsoleF('VirtIO: found device at %h:%d\n', [Base, Irq]);
    end;
  end;
end;

procedure VirtIOProcessQueue(vq: PVirtQueue);
begin
  // empty queue?
  if (vq.last_used_index = vq.used.index) then
    Exit;
  while (vq.last_used_index <> vq.used.index) do
  begin
    // invoke callback handler
    vq.VqHandler(vq);
  end;
end;

procedure VirtIOHandler;
var
  r, j: DWORD;
  vqs: PVirtQueue;
begin
  for j := 0 to VirtIOMMIODevicesCount -1 do
  begin
    r := GetIntStatus(VirtIOMMIODevices[j].Base);
    if r and 1 = 1 then
    begin
      vqs := VirtIOMMIODevices[j].Vqs;
      while vqs <> nil do
      begin
	    if @vqs.VqHandler <> nil then
          VirtIOProcessQueue(vqs);
        vqs := vqs.Next;
      end;
      SetIntACK(VirtIOMMIODevices[j].Base, r);
    end;
  end;
  eoi_apic;
end;

procedure VirtIOIrqHandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
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
  Call VirtIOHandler
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
  iretq
end;

procedure InitVirtIODriver(ID: DWORD; InitDriver: TVirtIODriver);
var
  magic, device, version: ^DWORD;
  j: LongInt;
begin
  for j := 0 to (VirtIOMMIODevicesCount -1) do
  begin
    magic := Pointer(VirtIOMMIODevices[j].Base);
    version := Pointer(VirtIOMMIODevices[j].Base + MMIO_VERSION);
    if (magic^ = MMIO_SIGNATURE) and (version^ = MMIO_MODERN) then
    begin
      device := Pointer(VirtIOMMIODevices[j].Base + MMIO_DEVICEID);
      if device^ = ID then
      begin
        SetDeviceStatus(VirtIOMMIODevices[j].Base, 0);
        SetDeviceStatus(VirtIOMMIODevices[j].Base, VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER);
        if InitDriver(@VirtIOMMIODevices[j]) then
          SetDeviceStatus(VirtIOMMIODevices[j].Base, VIRTIO_ACKNOWLEDGE or VIRTIO_FEATURES_OK or VIRTIO_DRIVER or VIRTIO_DRIVER_OK);
      end;
    end;
  end;
end;

initialization
  FindVirtIOMMIODevices;
end.
