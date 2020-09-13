//
// VirtIOFS.pas
//
// This unit contains the code of the VirtIOFS driver.
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

unit VirtIOFS;

interface

{$I ..\Toro.inc}

{$IFDEF EnableDebug}
       //{$DEFINE DebugVirtioFS}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  FileSystem, VirtIO,
  Arch, Console, Network, Process, Memory;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

type
  PByte = ^TByte;
  TByte = array[0..0] of byte;
  PVirtioFsConfig = ^TVirtioFsConfig;

  VirtIOUsedItem = record
    Index: Dword;
    Length: Dword;
  end;

  PVirtIOUsed = ^TVirtIOUsed;
  TVirtIOUsed = record
    Flags: word;
    Index: word;
    Rings: array[0..0] of VirtIOUsedItem;
  end;

  PVirtIOAvailable = ^TVirtIOAvailable;
  TVirtIOAvailable = record
    Flags: Word;
    Index: Word;
    Rings: Array[0..0] of Word;
  end;

  PQueueBuffer = ^TQueueBuffer;
  TQueueBuffer = record
    Address: QWord;
    Length: DWord;
    Flags: Word;
    Next: Word;
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

  TVirtIOFSDevice = record
    IRQ: LongInt;
    tag: PChar;
    Base: QWord;
    FsConfig: PVirtioFsConfig;
    IsrConfig: ^DWORD;
    QueueNotify: ^WORD;
    HpQueue: TVirtQueue;
    RqQueue: TVirtQueue;
    Driver: TFilesystemDriver;
    BlkDriver: TBlockDriver;
    FileDesc: TFileBlock;
  end;

  PBufferInfo = ^TBufferInfo;
  TBufferInfo = record
    Buffer: ^Byte;
    Size: QWord;
    Flags: Byte;
  end;

  TVirtIOFsConfig = packed record
    tag: array[0..35] of Char;
    numQueues: DWORD;
  end;

  TFuseInHeader = packed record
    Len: DWORD;
    Opcode: DWORD;
    Unique: QWord;
    Nodeid: QWord;
    Uid: DWORD;
    Gid: DWORD;
    Pid: DWORD;
    Padding: DWORD;
  end;

  TFuseOutHeader = packed record
    Len: DWORD;
    Error: DWORD;
    Unique: QWord;
  end;

  TFuseInitIn = packed record
    Major: DWORD;
    Minor: DWORD;
    MaxReadahead: DWORD;
    Flags: DWORD;
  end;

  TFuseInitOut = packed record
    Major: DWORD;
    Minor: DWORD;
    MaxReadahead: DWORD;
    Flags: DWORD;
    MaxBackground: WORD;
    CongestionThreshold: WORD;
    MaxWrite: DWORD;
    TimeGran: DWORD;
    MaxPages: WORD;
    Padding: WORD;
    Unused: array[0..7] of DWORD;
  end;

  TFuseGetAttrIn = packed record
    GetattrFlags: DWORD;
    Dummy: DWORD;
    Fh: QWORD;
  end;

  TFuseAttr = packed record
    Ino: QWORD;
    Size: QWORD;
    Blocks: QWORD;
    Atime: QWORD;
    Mtime: QWORD;
    Ctime: QWORD;
    Atimensec: DWORD;
    Mtimensec: DWORD;
    Ctimensec: DWORD;
    Mode: DWORD;
    Nlink: DWORD;
    Uid: DWORD;
    Gid: DWORD;
    Rdev: DWORD;
    Blksize: DWORD;
    Padding: DWORD;
  end;

  TFuseGetAttrOut = packed record
    AttrValid: QWORD;
    AttrValid_nsec: DWORD;
    Dummy: DWORD;
    Attr: TFuseAttr;
  end;

  TFuseEntryOut = packed record
    Nodeid: QWORD;
    Generation: QWORD;
    EntryValid: QWORD;
    AttrValid: QWORD;
    EntryValid_nsec: DWORD;
    AttrValid_nsec: DWORD;
    Attr: TFuseAttr;
  end;

  TFuseOpenIn = packed record
    Flags: DWORD;
    Unused: DWORD;
  end;

  TFuseOpenOut = packed record
    Fh: QWORD;
    OpenFlags: DWORD;
    Padding: DWORD;
  end;

  TFuseReadIn = packed record
    Fh: QWORD;
    Offset: QWORD;
    Size: DWORD;
    ReadFlags: DWORD;
    LockOwner: QWORD;
    Flags: DWORD;
    Padding: DWORD;
  end;

  TFuseReleaseIn = packed record
    Fh: QWORD;
    Flags: DWORD;
    ReleaseFlags: DWORD;
    LockOwner: QWORD;
  end;

  TFuseMknodIn = packed record
    Mode: DWORD;
    Rdev: DWORD;
    Umask: DWORD;
    Padding: DWORD;
  end;

  TFuseWriteIn = packed record
    fh: QWORD;
    offset: QWORD;
    size: DWORD;
    write_flags: DWORD;
    lock_owner: QWORD;
    flags: DWORD;
    padding: DWORD;
  end;

  TFuseWriteOut = packed record
    size: DWORD;
    padding: DWORD;
  end;

const
  VIRTIO_ACKNOWLEDGE = 1;
  VIRTIO_DRIVER = 2;
  VIRTIO_CTRL_VQ = 17;
  VIRTIO_MRG_RXBUF = 15;
  VIRTIO_CSUM = 0;
  VIRTIO_FEATURES_OK = 8;
  VIRTIO_DRIVER_OK = 4;
  VIRTIO_DESC_FLAG_WRITE_ONLY = 2;
  VIRTIO_DESC_FLAG_NEXT = 1;

  DEVICE_NEEDS_RESET = 64;
  FUSE_ROOT_ID = 1;

  // These values come from
  // FUSE_KERNEL_VERSION and FUSE_KERNEL_MINOR_VERSION
  FUSE_MAJOR_VERSION = 7;
  FUSE_MINOR_VERSION = 31;

  FUSE_INIT = 26;
  FUSE_LOOKUP = 1;
  FUSE_OPEN = 14;
  FUSE_READ = 15;
  FUSE_GETATTR = 3;
  FUSE_RELEASE = 18;
  FUSE_MKNOD = 8;
  FUSE_WRITE = 16;

  REQUEST_QUEUE = 0;

  // INIT request/reply flags
  FUSE_ASYNC_READ = 1 shl 0;
  FUSE_POSIX_LOCKS = 1 shl 1;
  FUSE_FILE_OPS = 1 shl 2;
  FUSE_ATOMIC_O_TRUNC = 1 shl 3;
  FUSE_EXPORT_SUPPORT =	1 shl 4;
  FUSE_BIG_WRITES = 1 shl 5;
  FUSE_DONT_MASK = 1 shl 6;
  FUSE_SPLICE_WRITE = 1 shl 7;
  FUSE_SPLICE_MOVE = 1 shl 8;
  FUSE_SPLICE_READ = 1 shl 9;
  FUSE_FLOCK_LOCKS = 1 shl 10;
  FUSE_HAS_IOCTL_DIR = 1 shl 11;
  FUSE_AUTO_INVAL_DATA = 1 shl 12;
  FUSE_DO_READDIRPLUS = 1 shl 13;
  FUSE_READDIRPLUS_AUTO	= 1 shl 14;
  FUSE_ASYNC_DIO = 1 shl 15;
  FUSE_WRITEBACK_CACHE = 1 shl 16;
  FUSE_NO_OPEN_SUPPORT = 1 shl 17;
  FUSE_PARALLEL_DIROPS = 1 shl 18;
  FUSE_HANDLE_KILLPRIV = 1 shl 19;
  FUSE_POSIX_ACL = 1 shl 20;
  FUSE_ABORT_ERROR = 1 shl 21;
  FUSE_MAX_PAGES = 1 shl 22;
  FUSE_CACHE_SYMLINKS = 1 shl 23;
  FUSE_NO_OPENDIR_SUPPORT = 1 shl 24;

  // TODO: to check the value of this
  TORO_MAX_READAHEAD_SIZE = 1048576;
  TORO_UNIQUE = $2721987;

  ROOT_UID = 0;

  VIRTIO_ID_FS = $1a;
  MMIO_MODERN = 2;
  MMIO_VERSION = 4;
  MMIO_SIGNATURE = $74726976;
  MMIO_DEVICEID = $8;
  MMIO_QUEUENOTIFY = $50;
  MMIO_CONFIG = $100;
  MMIO_FEATURES = $10;
  MMIO_STATUS = $70;
  MMIO_GUESTFEATURES = $20;
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

var
  FSVirtIO: TVirtIOFSDevice;

function VirtioFSLookUpInode(Ino: PInode; Name: PXChar): PInode; forward;
procedure VirtIOSendBuffer(Base: QWORD; queue_index: word; Queue: PVirtQueue; bi:PBufferInfo; count: QWord); forward;
procedure VirtIOProcessQueue(vq: PVirtQueue); forward;

procedure SetDeviceStatus(Base: QWORD; Value: DWORD);
var
  status: ^DWORD;
begin
  status := Pointer(Base + MMIO_STATUS);
  status^ := Value;
  ReadWriteBarrier;
end;

function GetDeviceStatus (Base: QWORD): DWORD;
var
  status: ^DWORD;
begin
  status := Pointer(Base + MMIO_STATUS);
  Result := status^;
end;

function VirtIOGetDeviceFeatures(Base: QWORD): DWORD;
var
  value: ^DWORD;
begin
  value := Pointer(BASE + MMIO_FEATURES);
  Result := value^;
end;

// Reset device and negotiate features
function VirtIONegociateFeatures(Base: QWORD; Features: DWORD): Boolean;
var
  devfeat: DWORD;
  status: ^DWORD;
begin
  Result := False;
  status := Pointer (BASE + MMIO_STATUS);
  status^ := 0;
  status^ := VIRTIO_ACKNOWLEDGE;
  status^ := VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER;
  devfeat := VirtIOGetDeviceFeatures(Base);
  devfeat := devfeat and Features;
  // TODO: To check if this is the right field
  //guestfeatures := Pointer (BASE + MMIO_GUESTFEATURES);
  // TODO: the features to negociate are not clear so just ignore them
  // This should be replaced with something better
  //guestfeatures^ := devfeat;
  status^ := VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK;
  if ((status^ and VIRTIO_FEATURES_OK) = 0) then
    Exit;
  Result := True;
end;

function VirtIOInitQueue(Base: QWORD; QueueId: Word; Queue: PVirtQueue; HeaderLen: DWORD): Boolean;
var
  j: LongInt;
  QueueSize, sizeOfBuffers: DWORD;
  sizeofQueueAvailable, sizeofQueueUsed: DWORD;
  buff: PChar;
  bi: TBufferInfo;
  QueueSel, EnableQueue: ^DWORD;
  QueueNumMax, QueueNum: ^DWORD;
  AddrLow: ^DWORD;
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
    for j := 0 to Queue.queue_size - 1 do
    begin
      VirtIOSendBuffer(Base, QueueId, Queue, @bi, 1);
    end;
  end;

  Result := True;
end;

procedure VirtIOSendBuffer(Base: QWORD; queue_index: word; Queue: PVirtQueue; bi:PBufferInfo; count: QWord);
var
  index, buffer_index, next_buffer_index: word;
  vq: PVirtQueue;
  b: PBufferInfo;
  i: LongInt;
  tmp: PQueueBuffer;
  QueueNotify: ^DWORD;
begin
  vq := Queue;

  index := vq.available.index mod vq.queue_size;
  buffer_index := vq.next_buffer;
  vq.available.rings[index] := buffer_index;

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

    tmp.address := PtrUInt(b.buffer);
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

procedure virtIOFSDedicate(Driver:PBlockDriver; CPUID: LongInt);
begin
  DedicateBlockFile(@FsVirtIO.FileDesc, CPUID);
end;

procedure VirtioFSWriteInode(Ino: PInode);
begin
  WriteConsoleF('VirtioFSWriteInode: This is not implemented yet\n', []);
end;

function VirtioFSCloseFile(FileDesc: PFileRegular): LongInt;
var
  OutHeader: TFuseOutHeader;
  InHeader: TFuseInHeader;
  ReleaseIn: TFuseReleaseIn;
  BufferInfo: array[0..2] of TBufferInfo;
  Done: Boolean;
begin
  Result := 0;

  InHeader.opcode := FUSE_RELEASE;
  InHeader.len := sizeof(InHeader) + sizeof(ReleaseIn);
  Done := False;
  InHeader.unique := PtrUInt(@Done);
  InHeader.nodeid := FileDesc.INode.ino;
  InHeader.uid := ROOT_UID;
  ReleaseIn.fh := FileDesc.Opaque;

  BufferInfo[0].buffer := @InHeader;
  BufferInfo[0].size := sizeof(InHeader);
  BufferInfo[0].flags := 0;

  BufferInfo[1].buffer := @ReleaseIn;
  BufferInfo[1].size := sizeof(ReleaseIn);
  BufferInfo[1].flags := 0;

  BufferInfo[2].buffer := @OutHeader;
  BufferInfo[2].size := sizeof(OutHeader);
  BufferInfo[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(FsVirtio.Base, REQUEST_QUEUE, @FsVirtIO.RqQueue, @BufferInfo[0], 3);
  while not Done do
    ReadWriteBarrier;

  if OutHeader.error <> 0 then
    Exit;

  Result := 1;
end;

function VirtioFSOpenFile(FileDesc: PFileRegular; Flags: Longint): LongInt;
var
  OutHeader: TFuseOutHeader;
  InHeader: TFuseInHeader;
  OpenIn: TFuseOpenIn;
  OpenOut: TFuseOpenOut;
  BufferInfo: array[0..3] of TBufferInfo;
  Done: Boolean;
begin
  Result := 0;

  InHeader.opcode := FUSE_OPEN;
  InHeader.len := sizeof(InHeader) + sizeof(OpenIn);
  InHeader.nodeid := FileDesc.Inode.ino;
  Done := False;
  InHeader.unique := PtrUInt(@Done);
  InHeader.uid := ROOT_UID;

  OpenIn.flags := Flags;

  BufferInfo[0].buffer := @InHeader;
  BufferInfo[0].size := sizeof(InHeader);
  BufferInfo[0].flags := 0;

  BufferInfo[1].buffer := @OpenIn;
  BufferInfo[1].size := sizeof(OpenIn);
  BufferInfo[1].flags := 0;

  BufferInfo[2].buffer := @OutHeader;
  BufferInfo[2].size := sizeof(OutHeader);
  BufferInfo[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  BufferInfo[3].buffer := @OpenOut;
  BufferInfo[3].size := sizeof(OpenOut);
  BufferInfo[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(FsVirtio.Base, REQUEST_QUEUE, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do
    ReadWriteBarrier;

  if OutHeader.error <> 0 then
    Exit;

  FileDesc.Opaque := openout.fh;
  Result := 1;
end;

// TODO: These values should be parameters
const
  Irusr = &400;
  Iwusr = &200;
  Irgrp = &40;
  Iroth = &4;
  S_Ifreg = $8000;

function VirtIOFSCreateInode(Ino: PInode; Name: PXChar): PInode;
var
  Len: LongInt;
  MknodIn: TFuseMknodIn;
  BufferInfo: array[0..3] of TBufferInfo;
  InHeader: TFuseInHeader;
  OutHeader: TFuseOutHeader;
  Done : Boolean;
begin
  Result := nil;

  Len := strlen(name) + 1;
  InHeader.opcode := FUSE_MKNOD;
  Done := False;
  InHeader.unique := PtrUInt(@Done);
  InHeader.len := sizeof(InHeader) + sizeof(MknodIn) + Len ;
  InHeader.nodeid := Ino.ino;
  InHeader.uid := ROOT_UID;
  OutHeader.error := 0;

  // TODO: Mode must be a parameter
  MknodIn.mode := S_Ifreg or Irusr or Iwusr or Irgrp or Iroth;
  MknodIn.rdev := 0;
  MknodIn.umask := 0;

  BufferInfo[0].buffer := @InHeader;
  BufferInfo[0].size := sizeof(InHeader);
  BufferInfo[0].flags := 0;

  BufferInfo[1].buffer := @MknodIn;
  BufferInfo[1].size := sizeof(MknodIn);
  BufferInfo[1].flags := 0;

  BufferInfo[2].buffer := Pointer(Name);
  BufferInfo[2].size := Len;
  BufferInfo[2].flags := 0;

  BufferInfo[3].buffer := @OutHeader;
  BufferInfo[3].size := sizeof(OutHeader);
  BufferInfo[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(FsVirtio.Base, REQUEST_QUEUE, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do
    ReadWriteBarrier;

  if OutHeader.error <> 0 then
    Exit;

  Result := VirtioFSLookUpInode(Ino, Name);
end;

function VirtIOFSWriteFile(FileDesc: PFileRegular; Count: Longint; Buffer: Pointer): longint;
var
  BufferInfo: array[0..4] of TBufferInfo;
  WriteIn: TFuseWriteIn;
  WriteOut: TFuseWriteOut;
  InHeader: TFuseInHeader;
  OutHeader: TFuseOutHeader;
  Done: Boolean;
begin
  Result := 0;
  InHeader.opcode := FUSE_WRITE;
  InHeader.len := sizeof(InHeader) + sizeof(WriteIn) + sizeof(Pointer);
  Done := False;
  InHeader.unique := PtrUInt(@Done);
  InHeader.nodeid := FileDesc.Inode.ino;
  InHeader.uid := ROOT_UID;

  WriteIn.fh := FileDesc.Opaque;
  WriteIn.size := Count;
  WriteIn.offset := FileDesc.FilePos;

  BufferInfo[0].buffer := @InHeader;
  BufferInfo[0].size := sizeof(InHeader);
  BufferInfo[0].flags := 0;

  BufferInfo[1].buffer := @WriteIn;
  BufferInfo[1].size := sizeof(WriteIn);
  BufferInfo[1].flags := 0;

  BufferInfo[2].buffer := Pointer(buffer);
  BufferInfo[2].size := Count;
  BufferInfo[2].flags := 0;

  BufferInfo[3].buffer := @OutHeader;
  BufferInfo[3].size := sizeof(OutHeader);
  BufferInfo[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  BufferInfo[4].buffer := @WriteOut;
  BufferInfo[4].size := sizeof(WriteOut);
  BufferInfo[4].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(FsVirtio.Base, REQUEST_QUEUE, @FsVirtIO.RqQueue, @BufferInfo[0], 5);

  while not Done do
    ReadWriteBarrier;

  if OutHeader.error <> 0 then
   Exit;

  Inc(FileDesc.FilePos, Count);

  // update inode size
  if FileDesc.FilePos > FileDesc.Inode.Size then
    FileDesc.Inode.Size := FileDesc.FilePos;

  Result := Count;
end;

function VirtioFSReadFile(FileDesc: PFileRegular; Count: Longint; Buffer: Pointer): longint;
var
  BufferInfo: array[0..3] of TBufferInfo;
  ReadIn: TFuseReadIn;
  InHeader: TFuseInHeader;
  OutHeader: TFuseOutHeader;
  Done: Boolean;
begin
  Result := 0;
  if FileDesc.FilePos + Count > FileDesc.Inode.Size then
  begin
    Count := FileDesc.Inode.Size - FileDesc.FilePos;
    If Count = 0 then
      Exit;
  end;
  InHeader.opcode := FUSE_READ;
  InHeader.len := sizeof(InHeader) + sizeof(ReadIn);
  Done := False;
  InHeader.unique := PtrUInt(@Done);
  InHeader.nodeid := FileDesc.Inode.ino;
  InHeader.uid := ROOT_UID;

  ReadIn.fh := FileDesc.Opaque;
  ReadIn.size := Count;
  ReadIn.offset := FileDesc.FilePos;

  BufferInfo[0].buffer := @InHeader;
  BufferInfo[0].size := sizeof(InHeader);
  BufferInfo[0].flags := 0;

  BufferInfo[1].buffer := @ReadIn;
  BufferInfo[1].size := sizeof(ReadIn);
  BufferInfo[1].flags := 0;

  BufferInfo[2].buffer := @OutHeader;
  BufferInfo[2].size := sizeof(OutHeader);
  BufferInfo[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  BufferInfo[3].buffer := Pointer(buffer);
  BufferInfo[3].size := Count;
  BufferInfo[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(FsVirtio.Base, REQUEST_QUEUE, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do
    ReadWriteBarrier;

  if OutHeader.error <> 0 then
   Exit;

  Inc(FileDesc.FilePos, Count);

  Result := Count;
end;

function VirtioFSLookUpInode(Ino: PInode; Name: PXChar): PInode;
var
  len: LongInt;
  EntryOut: TFuseEntryOut;
  BufferInfo: array[0..3] of TBufferInfo;
  InHeader: TFuseInHeader;
  OutHeader: TFuseOutHeader;
  Done : Boolean;
begin
  Result := nil;

  Len := strlen(name) + 1;
  InHeader.opcode := FUSE_LOOKUP;
  Done := False;
  InHeader.unique := PtrUInt(@Done);
  InHeader.len := sizeof(InHeader) + Len ;
  InHeader.nodeid := Ino.ino;
  InHeader.uid := ROOT_UID;

  BufferInfo[0].buffer := @InHeader;
  BufferInfo[0].size := sizeof(InHeader);
  BufferInfo[0].flags := 0;

  BufferInfo[1].buffer := Pointer(Name);
  BufferInfo[1].size := Len;
  BufferInfo[1].flags := 0;

  BufferInfo[2].buffer := @OutHeader;
  BufferInfo[2].size := sizeof(OutHeader);
  BufferInfo[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  BufferInfo[3].buffer := @EntryOut;
  BufferInfo[3].size := sizeof(EntryOut);
  BufferInfo[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(FsVirtio.Base, REQUEST_QUEUE, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do
    ReadWriteBarrier;

  if OutHeader.error <> 0 then
    Exit;

  Result := GetInode(EntryOut.nodeid);
end;

procedure VirtioFSReadInode(Ino: PInode);
var
  BufferInfo: array[0..3] of TBufferInfo;
  InHeader: TFuseInHeader;
  OutHeader: TFuseOutHeader;
  GetAttrIn: TFuseGetAttrIn;
  GetAttrOut: TFuseGetAttrOut;
  Done: Boolean;
begin
  InHeader.opcode := FUSE_GETATTR;
  InHeader.len := sizeof(InHeader) + sizeof(GetAttrIn);
  InHeader.nodeid := Ino.ino;
  InHeader.uid := ROOT_UID;
  Done := False;
  InHeader.unique := PtrUInt(@Done);

  BufferInfo[0].buffer := @InHeader;
  BufferInfo[0].size := sizeof(InHeader);
  BufferInfo[0].flags := 0;

  BufferInfo[1].buffer := @GetAttrIn;
  BufferInfo[1].size := sizeof(GetAttrIn);
  BufferInfo[1].flags := 0;

  BufferInfo[2].buffer := @OutHeader;
  BufferInfo[2].size := sizeof(OutHeader);
  BufferInfo[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  BufferInfo[3].buffer := @GetAttrOut;
  BufferInfo[3].size := sizeof(GetAttrOut);
  BufferInfo[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(FsVirtio.Base, REQUEST_QUEUE, @FsVirtIO.RqQueue, @BufferInfo[0], 4);
  
  while not Done do
    ReadWriteBarrier;

  If OutHeader.error <> 0 then
    Exit;

  Ino.Size := GetAttrOut.attr.size;
  Ino.Dirty := False;

  if GetAttrOut.attr.mode and $4000 = $4000 then
    Ino.Mode := INODE_DIR
  else
    Ino.Mode := INODE_REG;
end;

function VirtioFSReadSuper(Super: PSuperBlock): PSuperBlock;
var
  BufferInfo: array[0..3] of TBufferInfo;
  InHeader: TFuseInHeader;
  OutHeader: TFuseOutHeader;
  InitIn: TFuseInitIn;
  InitOut: TFuseInitOut;
  Done: Boolean;
begin
  Result := nil;
  InHeader.opcode := FUSE_INIT;
  InHeader.len := sizeof(InHeader) + sizeof(InitIn);
  InHeader.uid := ROOT_UID;

  Done := False;
  InHeader.unique := PtrUInt(@Done);
  InitIn.major := FUSE_MAJOR_VERSION;
  InitIn.minor := FUSE_MINOR_VERSION;

  // TODO: to check this flags
  InitIn.flags := 0;
  InitIn.MaxReadahead := TORO_MAX_READAHEAD_SIZE;

  BufferInfo[0].buffer := @InHeader;
  BufferInfo[0].size := sizeof(InHeader);
  BufferInfo[0].flags := 0;

  BufferInfo[1].buffer := @InitIn;
  BufferInfo[1].size := sizeof(InitIn);
  BufferInfo[1].flags := 0;

  BufferInfo[2].buffer := @OutHeader;
  BufferInfo[2].size := sizeof(OutHeader);
  BufferInfo[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  BufferInfo[3].buffer := @InitOut;
  BufferInfo[3].size := sizeof(InitOut);
  BufferInfo[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;
  VirtIOSendBuffer(FsVirtio.Base, REQUEST_QUEUE, @FsVirtIO.RqQueue, @BufferInfo[0], 4);
  
  while not Done do
    ReadWriteBarrier;

  if OutHeader.error <> 0 then
   Exit;
  
  Super.InodeROOT := GetInode(FUSE_ROOT_ID);
  
  If Super.InodeROOT = nil then
    Exit;
  
  Result := Super;
end;

procedure VirtIOProcessQueue(vq: PVirtQueue);
var
  index, norm_index, buffer_index: Word;
  QueueBuffer: PQueueBuffer;
  InHeader: ^TFuseInHeader;
  p: ^Boolean;
begin
  if vq.last_used_index = vq.used.index then
    Exit;
  index := vq.last_used_index;
  while index <> vq.used.index do
  begin
    norm_index := index mod vq.queue_size;
    buffer_index := vq.used.rings[norm_index].index;
    QueueBuffer := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));
    InHeader := Pointer(QueueBuffer.address);
    p := Pointer(InHeader.unique);
    Panic(p^ = True, 'VirtioFS: Waking up a thread in ready state\n', []);
    p^ := True;
    inc(index);
  end;

  vq.last_used_index := index;
  ReadWriteBarrier;
end;

procedure SetIntACK(Base: QWORD; Value: DWORD);
var
  IntACK: ^DWORD;
begin
  IntACK := Pointer(Base + MMIO_INTACK);
  IntAck^ := Value;
end;

procedure VirtIOFSHandler;
var
  r: DWORD;
begin
  r := FsVirtio.IsrConfig^;
  SetIntACK(FsVirtio.Base, r);
  VirtIOProcessQueue (@FsVirtio.RqQueue);
  eoi_apic;
end;

procedure VirtIOFSIrqHandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
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
  Call VirtIOFSHandler
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

procedure FindVirtIOFSOnMMIO;
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
      if device^ = VIRTIO_ID_FS then
      begin
        FsVirtio.IRQ := VirtIOMMIODevices[j].Irq; 
        FsVirtio.Base := VirtIOMMIODevices[j].Base;
        FsVirtio.QueueNotify := Pointer(VirtIOMMIODevices[j].Base + MMIO_QUEUENOTIFY);
        FsVirtio.FsConfig := Pointer(VirtIOMMIODevices[j].Base + MMIO_CONFIG);
        WriteConsoleF('VirtIOFS: Detected device tagged: %p, queues: %d\n', [PtrUInt(@FsVirtio.FsConfig.tag), FsVirtio.FsConfig.numQueues]);
        FsVirtio.IsrConfig := Pointer(VirtIOMMIODevices[j].Base + MMIO_INTSTATUS);
        if VirtIONegociateFeatures (VirtIOMMIODevices[j].Base, VirtIOGetDeviceFeatures (VirtIOMMIODevices[j].Base)) then
        begin
          WriteConsoleF('VirtIOFS: Device accepted features\n',[])
        end else
        begin
          WriteConsoleF('VirtioFS: Device did not accept features\n', []);
          Exit;
        end;

        if VirtIOInitQueue(VirtIOMMIODevices[j].Base, REQUEST_QUEUE, @FsVirtio.RqQueue, 0) then
        begin
          WriteConsoleF('VirtIOFS: Queue 0, size: %d, initiated, irq: %d\n', [FsVirtio.RqQueue.queue_size, FsVirtio.IRQ]);
        end else
        begin
          WriteConsoleF('VirtIOFS: Queue 0, failed\n', []);
          Exit;
        end;
      
        SetDeviceStatus(VirtIOMMIODevices[j].Base, VIRTIO_ACKNOWLEDGE or VIRTIO_FEATURES_OK or VIRTIO_DRIVER or VIRTIO_DRIVER_OK);
        CaptureInt(BASE_IRQ + FsVirtio.IRQ, @VirtIOFSIrqHandler);
        IOApicIrqOn(FsVirtio.IRQ);
      
        FsVirtio.Driver.name := 'virtiofs';
        FsVirtio.Driver.ReadSuper := VirtioFSReadSuper;
        FsVirtio.Driver.ReadInode := VirtioFSReadInode;
        FsVirtio.Driver.WriteInode := VirtioFSWriteInode;
        FsVirtio.Driver.CreateInode := VirtIOFSCreateInode;
        FsVirtio.Driver.LookUpInode := VirtioFSLookUpInode;
        FsVirtio.Driver.ReadFile := VirtioFSReadFile;
        FsVirtio.Driver.WriteFile := VirtIOFSWriteFile;
        FsVirtio.Driver.OpenFile := VirtioFSOpenFile;
        FsVirtio.Driver.CloseFile := VirtioFSCloseFile;
        RegisterFilesystem(@FsVirtio.Driver);
        Move(FsVirtio.FsConfig.tag, FsVirtio.BlkDriver.name, StrLen(FsVirtio.FsConfig.tag)+1);
        FsVirtio.BlkDriver.Busy := false;
        FsVirtio.BlkDriver.WaitOn := nil;
        FsVirtio.BlkDriver.major := 0;
        FsVirtIO.BlkDriver.Dedicate := VirtIOFSDedicate;
        FsVirtIO.BlkDriver.CPUID := -1;
        FsVirtIO.FileDesc.Minor := 0;
        FsVirtIO.FileDesc.Next := nil;
        FsVirtIO.FileDesc.BlockDriver := @FsVirtIO.BlkDriver;
        RegisterBlockDriver(@FsVirtio.BlkDriver);
      end;
    end else 
    begin
      WriteConsoleF('VirtIOFS: magic number or version wrong, base address may be wrong\n', []);
    end;
  end;
end;

initialization
  FindVirtIOFSOnMMIO;
end.
