//
// VirtIOFS.pas
//
// This unit contains the code of the VirtIOFS driver.
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

unit VirtIOFS;

interface

{$I ..\Toro.inc}

{$IFDEF EnableDebug}
       //{$DEFINE DebugVirtioFS}
{$ENDIF}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  FileSystem,
  Pci,
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
  PVirtIOPciCommonCfg = ^TVirtIOPciCommonCfg;

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
    QueueSize: word;
    Buffers: PQueueBuffer;
    Available: PVirtIOAvailable;
    Used: PVirtIOUsed;
    LastUsedIndex: word;
    LastAvailableIndex: word;
    Buffer: PByte;
    ChunkSize: dword;
    NextBuffer: word;
    Lock: QWord;
  end;

  TVirtIOFSDevice = record
    IRQ: LongInt;
    tag: PChar;
    NotifyOffMultiplier: DWORD;
    FsConfig: PVirtioFsConfig;
    CommonConfig: PVirtIOPciCommonCfg;
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

  TVirtIOPciCommonCfg = packed record
    DeviceFeature_select: DWORD;
    DeviceFeature: DWORD;
    DriverFeature_select: DWORD;
    DriverFeature: DWORD;
    MsixConfig: WORD;
    NumQueues: WORD;
    DeviceStatus: Byte;
    ConfigGeneration: Byte;
    QueueSelect: WORD;
    QueueSize: WORD;
    QueueMsixVector: WORD;
    QueueEnable: WORD;
    QueueNotifyOff: WORD;
    QueueDesc: QWORD;
    QueueAvail: QWORD;
    QueueUsed: QWORD;
  end;

  TVirtIOPciCap = packed record
    CapVndr: Byte;
    CapNext: Byte;
    CapLen: Byte;
    CfgType: Byte;
    Bar: Byte;
    Padding: array [0..2] of Byte;
    Offset: DWORD;
    Length: DWORD;
  end;

  FuseInHeader = packed record
    Len: DWORD;
    Opcode: DWORD;
    Unique: QWord;
    Nodeid: QWord;
    Uid: DWORD;
    Gid: DWORD;
    Pid: DWORD;
    Padding: DWORD;
  end;

  FuseOutHeader = packed record
    Len: DWORD;
    Error: DWORD;
    Unique: QWord;
  end;

  FuseInitIn = packed record
    Major: DWORD;
    Minor: DWORD;
    MaxReadahead: DWORD;
    Flags: DWORD;
  end;

  FuseInitOut = packed record
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

  FuseGetAttrIn = packed record
    GetattrFlags: DWORD;
    Dummy: DWORD;
    Fh: QWORD;
  end;

  FuseAttr = packed record
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

  FuseGetAttrOut = packed record
    AttrValid: QWORD;
    AttrValid_nsec: DWORD;
    Dummy: DWORD;
    Attr: FuseAttr;
  end;

  FuseEntryOut = packed record
    Nodeid: QWORD;
    Generation: QWORD;
    EntryValid: QWORD;
    AttrValid: QWORD;
    EntryValid_nsec: DWORD;
    AttrValid_nsec: DWORD;
    Attr: FuseAttr;
  end;

  FuseOpenIn = packed record
    Flags: DWORD;
    Unused: DWORD;
  end;

  FuseOpenOut = packed record
    Fh: QWORD;
    OpenFlags: DWORD;
    Padding: DWORD;
  end;

  FuseReadIn = packed record
    Fh: QWORD;
    Offset: QWORD;
    Size: DWORD;
    ReadFlags: DWORD;
    LockOwner: QWORD;
    Flags: DWORD;
    Padding: DWORD;
  end;

  FuseReleaseIn = packed record
    Fh: QWORD;
    Flags: DWORD;
    ReleaseFlags: DWORD;
    LockOwner: QWORD;
  end;

  FuseMknodIn = packed record
    Mode: DWORD;
    Rdev: DWORD;
    Umask: DWORD;
    Padding: DWORD;
  end;

  FuseWriteIn = packed record
    fh: QWORD;
    offset: QWORD;
    size: DWORD;
    write_flags: DWORD;
    lock_owner: QWORD;
    flags: DWORD;
    padding: DWORD;
  end;

  FuseWriteOut = packed record
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
  VIRTIO_ID_FS = $105a;

  VIRTIO_PCI_CAP_DEVICE_CFG = 4;
  VIRTIO_PCI_CAP_ISR_CFG = 3;
  VIRTIO_PCI_CAP_COMMON_CFG = 1;
  VIRTIO_PCI_CAP_NOTIFY_CFG = 2;

  PCI_CAP_ID_VNDR = 9;
  DEVICE_NEEDS_RESET = 64;
  FUSE_ROOT_ID = 1;

  FUSE_MAJOR_VERSION = 7;
  FUSE_MINOR_VERSION = 27;

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

var
  FSVirtIO: TVirtIOFSDevice;

function VirtioFSLookUpInode(Ino: PInode; Name: PXChar): PInode; forward;

function VirtIOGetDeviceFeatures(Dev: PVirtIOPciCommonCfg): DWORD;
begin
  Result := Dev.DeviceFeature;
end;

// Reset device and negotiate features
function VirtIONegociateFeatures(Dev: PVirtIOPciCommonCfg; Features: DWORD): Boolean;
var
  devfeat: DWORD;
begin
  Result := False;
  Dev.DeviceStatus := 0;
  Dev.DeviceStatus := VIRTIO_ACKNOWLEDGE;
  Dev.DeviceStatus := VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER;
  devfeat := Dev.DeviceFeature;
  devfeat := devfeat and Features;
  // TODO: To check if this is the right field
  Dev.DeviceFeature_select := devfeat;
  Dev.DeviceStatus := VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK;
  if ((Dev.DeviceStatus and VIRTIO_FEATURES_OK) = 0) then
    Exit;
  Result := True;
end;

function VirtIOInitQueue(Dev: PVirtIOPciCommonCfg; QueueId: Word; Queue: PVirtQueue; HeaderLen: DWORD): Boolean;
var
  sizeOfBuffers: DWORD;
  sizeofQueueAvailable: DWORD;
  sizeofQueueUsed: DWORD;
  buff: PChar;
begin
  Result := False;
  FillByte(Queue^, sizeof(TVirtQueue), 0);
  Dev.QueueSelect := QueueId;
  Queue.QueueSize := Dev.QueueSize;
  sizeOfBuffers := (sizeof(TQueueBuffer) * Queue.QueueSize);
  sizeofQueueAvailable := (2*sizeof(WORD)+2) + (Queue.QueueSize*sizeof(WORD));
  sizeofQueueUsed := (2*sizeof(WORD)+2)+(Queue.QueueSize*sizeof(VirtIOUsedItem));
  // buff must be 4k aligned
  buff := ToroGetMem(sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096 * 2);
  FillByte(buff^, sizeOfBuffers + sizeofQueueAvailable + sizeofQueueUsed + 4096 * 2, 0);
  buff := buff + (4096 - PtrUInt(buff) mod 4096);
  // 16 bytes aligned
  Queue.buffers := PQueueBuffer(buff);
  // 2 bytes aligned
  Queue.available := @buff[sizeOfBuffers];
  // 4 bytes aligned
  Queue.used := PVirtIOUsed(@buff[((sizeOfBuffers + sizeofQueueAvailable+$0FFF) and not $FFF)]);
  Queue.NextBuffer:= 0;
  Queue.lock := 0;
  Dev.QueueDesc := QWORD(Queue.buffers);
  Dev.QueueAvail := QWORD(Queue.available);
  Dev.QueueUsed := QWORD(Queue.used);
  Dev.QueueEnable := 1;
  Dev.DeviceStatus := VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK or VIRTIO_DRIVER_OK;
  if ((Dev.DeviceStatus and DEVICE_NEEDS_RESET) = DEVICE_NEEDS_RESET) then
    Exit;
  if HeaderLen <> 0 then
  begin
    Queue.Buffer := ToroGetMem(queue.QueueSize * (HeaderLen) + 4096);
    Queue.Buffer := Pointer(PtrUint(queue.Buffer) + (4096 - PtrUInt(queue.Buffer) mod 4096));
    Queue.ChunkSize := HeaderLen;
  end;
  Result := True;
end;

procedure VirtIOSendBuffer(vq: PVirtQueue; bi:PBufferInfo; count: QWord; QueueIdx: WORD);
var
  index, buffer_index, NextBuffer_index: word;
  b: PBufferInfo;
  i: LongInt;
  tmp: PQueueBuffer;
begin
  index := vq.available.index mod vq.QueueSize;
  buffer_index := vq.NextBuffer;
  vq.available.rings[index] := buffer_index;
  for i := 0 to (count-1) do
  begin
    NextBuffer_index:= (buffer_index +1) mod vq.QueueSize;
    b := Pointer(PtrUInt(bi) + i * sizeof(TBufferInfo));
    tmp := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));
    tmp.flags := b.flags;
    tmp.next := NextBuffer_index;
    tmp.length := b.size;
    if (i <> (count-1)) then
        tmp.flags := tmp.flags or VIRTIO_DESC_FLAG_NEXT;
    tmp.address:= PtrUInt(b.buffer);
    buffer_index := NextBuffer_index;
  end;
  ReadWriteBarrier;
  vq.NextBuffer := buffer_index;
  Inc(vq.available.index);
  if (vq.used.flags and 1 <> 1) then
    FsVirtio.QueueNotify^ := QueueIdx;
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
  outhd: FuseOutHeader;
  inhd: FuseInHeader;
  releasein: FuseReleaseIn;
  bi: array[0..2] of TBufferInfo;
  Done: Boolean;
begin
  Result := 0;

  inhd.opcode := FUSE_RELEASE;
  inhd.len := sizeof(inhd) + sizeof(releasein);
  Done := False;
  inhd.unique := PtrUInt(@Done);
  inhd.nodeid := FileDesc.INode.ino;
  inhd.uid := ROOT_UID;
  releasein.fh := FileDesc.Opaque;

  bi[0].buffer := @inhd;
  bi[0].size := sizeof(inhd);
  bi[0].flags := 0;

  bi[1].buffer := @releasein;
  bi[1].size := sizeof(releasein);
  bi[1].flags := 0;

  bi[2].buffer := @outhd;
  bi[2].size := sizeof(outhd);
  bi[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 3, REQUEST_QUEUE);
  while Done = false do
  begin
    SysThreadSwitch;
    ReadWriteBarrier;
  end;

  if outhd.error <> 0 then
    Exit;

  Result := 1;
end;

function VirtioFSOpenFile(FileDesc: PFileRegular; Flags: Longint): LongInt;
var
  outhd: FuseOutHeader;
  inhd: FuseInHeader;
  openin: FuseOpenIn;
  openout: FuseOpenOut;
  bi: array[0..3] of TBufferInfo;
  Done: Boolean;
begin
  Result := 0;

  inhd.opcode := FUSE_OPEN;
  inhd.len := sizeof(inhd) + sizeof(openin);
  inhd.nodeid := FileDesc.Inode.ino;
  Done := False;
  inhd.unique := PtrUInt(@Done);
  inhd.uid := ROOT_UID;

  openin.flags := Flags;

  bi[0].buffer := @inhd;
  bi[0].size := sizeof(inhd);
  bi[0].flags := 0;

  bi[1].buffer := @openin;
  bi[1].size := sizeof(openin);
  bi[1].flags := 0;

  bi[2].buffer := @outhd;
  bi[2].size := sizeof(outhd);
  bi[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  bi[3].buffer := @openout;
  bi[3].size := sizeof(openout);
  bi[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 4, REQUEST_QUEUE);

  while Done = False do
  begin
    SysThreadSwitch;
    ReadWriteBarrier;
  end;

  if outhd.error <> 0 then
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
  mknodIn: FuseMknodIn;
  bi: array[0..3] of TBufferInfo;
  inhd: FuseInHeader;
  outhd: FuseOutHeader;
  Done : Boolean;
begin
  Result := nil;

  Len := strlen(name) + 1;
  inhd.opcode := FUSE_MKNOD;
  Done := False;
  inhd.unique := PtrUInt(@Done);
  inhd.len := sizeof(inhd) + sizeof(mknodIn) + Len ;
  inhd.nodeid := Ino.ino;
  inhd.uid := ROOT_UID;
  outhd.error := 0;

  // TODO: Mode must be a parameter
  mknodIn.mode := S_Ifreg or Irusr or Iwusr or Irgrp or Iroth;
  mknodIn.rdev := 0;
  mknodIn.umask := 0;

  bi[0].buffer := @inhd;
  bi[0].size := sizeof(inhd);
  bi[0].flags := 0;

  bi[1].buffer := @mknodIn;
  bi[1].size := sizeof(mknodIn);
  bi[1].flags := 0;

  bi[2].buffer := Pointer(Name);
  bi[2].size := Len;
  bi[2].flags := 0;

  bi[3].buffer := @outhd;
  bi[3].size := sizeof(outhd);
  bi[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 4, REQUEST_QUEUE);

  while Done = False do
  begin
    SysThreadSwitch;
    ReadWriteBarrier;
  end;

  if outhd.error <> 0 then
    Exit;

  Result := VirtioFSLookUpInode(Ino, Name);
end;

function VirtIOFSWriteFile(FileDesc: PFileRegular; Count: Longint; Buffer: Pointer): longint;
var
  bi: array[0..4] of TBufferInfo;
  writein: FuseWriteIn;
  writeout: FuseWriteOut;
  inhd: FuseInHeader;
  outhd: FuseOutHeader;
  Done: Boolean;
begin
  Result := 0;
  inhd.opcode := FUSE_WRITE;
  inhd.len := sizeof(inhd) + sizeof(writein) + sizeof(Pointer);
  Done := False;
  inhd.unique := PtrUInt(@Done);
  inhd.nodeid := FileDesc.Inode.ino;
  inhd.uid := ROOT_UID;

  writein.fh := FileDesc.Opaque;
  writein.size := Count;
  writein.offset := FileDesc.FilePos;

  bi[0].buffer := @inhd;
  bi[0].size := sizeof(inhd);
  bi[0].flags := 0;

  bi[1].buffer := @writein;
  bi[1].size := sizeof(writein);
  bi[1].flags := 0;

  bi[2].buffer := Pointer(buffer);
  bi[2].size := Count;
  bi[2].flags := 0;

  bi[3].buffer := @outhd;
  bi[3].size := sizeof(outhd);
  bi[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  bi[4].buffer := @writeout;
  bi[4].size := sizeof(writeout);
  bi[4].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 5, REQUEST_QUEUE);

  while Done = false do
  begin
    SysThreadSwitch;
    ReadWriteBarrier;
  end;

  if outhd.error <> 0 then
   Exit;

  Inc(FileDesc.FilePos, Count);

  // update inode size
  if FileDesc.FilePos > FileDesc.Inode.Size then
    FileDesc.Inode.Size := FileDesc.FilePos;

  Result := Count;
end;

function VirtioFSReadFile(FileDesc: PFileRegular; Count: Longint; Buffer: Pointer): longint;
var
  bi: array[0..3] of TBufferInfo;
  readin: FuseReadIn;
  inhd: FuseInHeader;
  outhd: FuseOutHeader;
  Done: Boolean;
begin
  Result := 0;
  if FileDesc.FilePos + Count > FileDesc.Inode.Size then
  begin
    Count := FileDesc.Inode.Size - FileDesc.FilePos;
    If Count = 0 then
      Exit;
  end;
  inhd.opcode := FUSE_READ;
  inhd.len := sizeof(inhd) + sizeof(readin);
  Done := False;
  inhd.unique := PtrUInt(@Done);
  inhd.nodeid := FileDesc.Inode.ino;
  inhd.uid := ROOT_UID;

  readin.fh := FileDesc.Opaque;
  readin.size := Count;
  readin.offset := FileDesc.FilePos;

  bi[0].buffer := @inhd;
  bi[0].size := sizeof(inhd);
  bi[0].flags := 0;

  bi[1].buffer := @readin;
  bi[1].size := sizeof(readin);
  bi[1].flags := 0;

  bi[2].buffer := @outhd;
  bi[2].size := sizeof(outhd);
  bi[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  bi[3].buffer := Pointer(buffer);
  bi[3].size := Count;
  bi[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 4, REQUEST_QUEUE);

  while Done = false do
  begin
    SysThreadSwitch;
    ReadWriteBarrier;
  end;

  if outhd.error <> 0 then
   Exit;

  Inc(FileDesc.FilePos, Count);

  Result := Count;
end;

function VirtioFSLookUpInode(Ino: PInode; Name: PXChar): PInode;
var
  len: LongInt;
  lookupout: FuseEntryOut;
  bi: array[0..3] of TBufferInfo;
  inhd: FuseInHeader;
  outhd: FuseOutHeader;
  Done : Boolean;
begin
  Result := nil;

  Len := strlen(name) + 1;
  inhd.opcode := FUSE_LOOKUP;
  Done := False;
  inhd.unique := PtrUInt(@Done);
  inhd.len := sizeof(inhd) + Len ;
  inhd.nodeid := Ino.ino;
  inhd.uid := ROOT_UID;

  bi[0].buffer := @inhd;
  bi[0].size := sizeof(inhd);
  bi[0].flags := 0;

  bi[1].buffer := Pointer(Name);
  bi[1].size := Len;
  bi[1].flags := 0;

  bi[2].buffer := @outhd;
  bi[2].size := sizeof(outhd);
  bi[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  bi[3].buffer := @lookupout;
  bi[3].size := sizeof(lookupout);
  bi[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 4, REQUEST_QUEUE);

  while Done = False do
  begin
    SysThreadSwitch;
    ReadWriteBarrier;
  end;

  if outhd.error <> 0 then
    Exit;

  Result := GetInode(lookupout.nodeid);
end;

procedure VirtioFSReadInode(Ino: PInode);
var
  bi: array[0..3] of TBufferInfo;
  inhd: FuseInHeader;
  outhd: FuseOutHeader;
  getattrin: FuseGetAttrIn;
  getattrout: FuseGetAttrOut;
  Done: Boolean;
begin
  inhd.opcode := FUSE_GETATTR;
  inhd.len := sizeof(inhd) + sizeof(getattrin);
  inhd.nodeid := Ino.ino;
  inhd.uid := ROOT_UID;
  Done := False;
  inhd.unique := PtrUInt(@Done);

  bi[0].buffer := @inhd;
  bi[0].size := sizeof(inhd);
  bi[0].flags := 0;

  bi[1].buffer := @getattrin;
  bi[1].size := sizeof(getattrin);
  bi[1].flags := 0;

  bi[2].buffer := @outhd;
  bi[2].size := sizeof(outhd);
  bi[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  bi[3].buffer := @getattrout;
  bi[3].size := sizeof(getattrout);
  bi[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 4, REQUEST_QUEUE);

  while Done = False do
  begin
    SysThreadSwitch;
    ReadWriteBarrier;
  end;

  If outhd.error <> 0 then
    Exit;

  Ino.Size := getattrout.attr.size;
  Ino.Dirty := False;

  if getattrout.attr.mode and $4000 = $4000 then
    Ino.Mode := INODE_DIR
  else
    Ino.Mode := INODE_REG;
end;

function VirtioFSReadSuper(Super: PSuperBlock): PSuperBlock;
var
  bi: array[0..3] of TBufferInfo;
  inhd: FuseInHeader;
  outhd: FuseOutHeader;
  initinhd: FuseInitIn;
  initouthd: FuseInitOut;
  Done: Boolean;
begin
  Result := nil;

  inhd.opcode := FUSE_INIT;
  inhd.len := sizeof(inhd) + sizeof(initinhd);
  inhd.uid := ROOT_UID;

  Done := False;
  inhd.unique := PtrUInt(@Done);
  initinhd.major := FUSE_MAJOR_VERSION;
  initinhd.minor := FUSE_MINOR_VERSION;

  // TODO: to check this flags
  initinhd.flags := 0;
  initinhd.MaxReadahead := TORO_MAX_READAHEAD_SIZE;

  bi[0].buffer := @inhd;
  bi[0].size := sizeof(inhd);
  bi[0].flags := 0;

  bi[1].buffer := @initinhd;
  bi[1].size := sizeof(initinhd);
  bi[1].flags := 0;

  bi[2].buffer := @outhd;
  bi[2].size := sizeof(outhd);
  bi[2].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  bi[3].buffer := @initouthd;
  bi[3].size := sizeof(initouthd);
  bi[3].flags := VIRTIO_DESC_FLAG_WRITE_ONLY;

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 4, REQUEST_QUEUE);
  while Done = false do
  begin
    SysThreadSwitch;
    ReadWriteBarrier;
  end;

  if outhd.error <> 0 then
   Exit;

  Super.InodeROOT := GetInode(FUSE_ROOT_ID);
  If Super.InodeROOT = nil then
    Exit;
  Result := Super;
end;

procedure VirtIOProcessQueue(vq: PVirtQueue);
var
  index, norm_index, buffer_index: Word;
  tmp: PQueueBuffer;
  FuseIn: ^FuseInHeader;
  p: ^Boolean;
begin
  if vq.LastUsedIndex = vq.used.index then
    Exit;
  index := vq.LastUsedIndex;
  while index <> vq.used.index do
  begin
    norm_index := index mod vq.QueueSize;
    buffer_index := vq.used.rings[norm_index].index;
    tmp := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));
    FuseIn := Pointer(tmp.address);
    p := Pointer(fusein.unique);
    Panic(p^ = True, 'VirtioFS: Waking up a thread in ready state\n', []);
    p^ := True;
    inc(index);
  end;

  vq.LastUsedIndex := index;
  ReadWriteBarrier;
end;

procedure VirtIOFSHandler;
var
  r: DWORD;
begin
  r := FsVirtio.IsrConfig^;
  if (r and 1 = 1) then
     VirtIOProcessQueue (@FsVirtio.RqQueue);
  eoi;
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

procedure FindVirtIOFSonPci;
var
  PciDev: PBusDevInfo;
  off, multi: DWORD;
  cap_vndr, cap: Byte;
  cfg, Bar, next: Byte;
begin
  PciDev := PCIDevices;
  while PciDev <> nil do
  begin
    if (PciDev.vendor = $1AF4) and (PciDev.device >= $1040) and (PciDev.device <= $107F) then
    begin
     // this is a modern virtio driver
     if PciDev.device = VIRTIO_ID_FS then
      begin
        FsVirtio.IRQ := PciDev.IRQ;
        multi := 0;
        Cap := PciGetNextCapability(PciDev, 0);
        while Cap <> 0 do
        begin
          cap_vndr := PciReadByte(PciDev.bus, PciDev.dev, PciDev.func, Cap);
          cfg := PciReadByte(PciDev.bus, PciDev.dev, PciDev.func, Cap + 3);
          bar := PciReadByte(PciDev.bus, PciDev.dev, PciDev.func, Cap + 4);
          off := PciReadDword(PciDev.bus, PciDev.dev, PciDev.func, (Cap div 4) + 2);
          next := PciGetNextCapability(PciDev, Cap);
          multi := PciReadDword(PciDev.bus, PciDev.dev, PciDev.func, (Cap div 4) + 4);
          Cap := next;
          if cap_vndr <> PCI_CAP_ID_VNDR then
            continue;
          if cfg = VIRTIO_PCI_CAP_NOTIFY_CFG then
          begin
            if IsPCI64Bar(PciDev.IO[bar]) then
              FsVirtio.QueueNotify := Pointer((PciDev.IO[bar] and $FFFFFFF0) + ((PciDev.IO[bar+1] and $FFFFFFFF) * (1 shl 32)) + off)
            else
              FsVirtio.QueueNotify := Pointer((PciDev.IO[bar] and $FFFFFFF0) + off);
            FsVirtio.NotifyOffMultiplier := multi;
          end;
          if cfg = VIRTIO_PCI_CAP_DEVICE_CFG then
          begin
            if IsPCI64Bar(PciDev.IO[bar]) then
              FsVirtio.FsConfig := Pointer((PciDev.IO[bar] and $FFFFFFF0) + ((PciDev.IO[bar+1] and $FFFFFFFF) * (1 shl 32)) + off)
            else
              FsVirtio.FsConfig := Pointer((PciDev.IO[bar] and $FFFFFFF0) + off);
            WriteConsoleF('VirtIOFS: Detected device tagged: %p, queues: %d\n', [PtrUInt(@FsVirtio.FsConfig.tag), FsVirtio.FsConfig.numQueues]);
          end;
          if cfg = VIRTIO_PCI_CAP_COMMON_CFG then
          begin
            if IsPCI64Bar(PciDev.IO[bar]) then
              FsVirtio.CommonConfig := Pointer((PciDev.IO[bar] and $FFFFFFF0) + ((PciDev.IO[bar+1] and $FFFFFFFF) * (1 shl 32)) + off)
            else
              FsVirtio.CommonConfig := Pointer((PciDev.IO[bar] and $FFFFFFF0) + off);
          end;
          if cfg = VIRTIO_PCI_CAP_ISR_CFG then
          begin
            if IsPCI64Bar(PciDev.IO[bar]) then
              FsVirtio.IsrConfig := Pointer((PciDev.IO[bar] and $FFFFFFF0) + ((PciDev.IO[bar+1] and $FFFFFFFF) * (1 shl 32)) + off)
            else
              FsVirtio.IsrConfig := Pointer((PciDev.IO[bar] and $FFFFFFF0) + off);
          end;
        end;

        if VirtIONegociateFeatures (FsVirtio.CommonConfig, VirtIOGetDeviceFeatures (FsVirtio.CommonConfig)) then
        begin
          WriteConsoleF('VirtIOFS: Device accepted features\n',[])
        end else
        begin
          WriteConsoleF('VirtioFS: Device did not accept features\n', []);
          Exit;
        end;

        if VirtIOInitQueue(FsVirtio.CommonConfig, 0, @FsVirtio.RqQueue, 0) then
        begin
          WriteConsoleF('VirtIOFS: Queue 0, size: %d, initiated, irq: %d\n', [FsVirtio.RqQueue.QueueSize, FsVirtio.IRQ]);
        end else
        begin
          WriteConsoleF('VirtIOFS: Queue 0, failed\n', []);
          Exit;
        end;

        // Set up notification queue
        FsVirtio.QueueNotify := Pointer(PtrUInt(FsVirtio.QueueNotify) + FsVirtio.CommonConfig.QueueNotifyOff * FsVirtio.NotifyOffMultiplier);
        // enable the irq
        CaptureInt(32+FsVirtio.IRQ, @VirtIOFSIrqHandler);
        IrqOn(FsVirtio.IRQ);
        PciSetMaster(PciDev);
        FsVirtio.RqQueue.used.flags := 0;
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
    end;
    PciDev := PciDev.Next;
  end;
end;

initialization
  FindVirtIOFSonPci;

end.
