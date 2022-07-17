//
// VirtIOFS.pas
//
// This unit contains code for VirtIOFS driver.
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
  PVirtioFsConfig = ^TVirtioFsConfig;

  TVirtIOFSDevice = record
    IRQ: LongInt;
    tag: PChar;
    Base: QWord;
    FsConfig: PVirtioFsConfig;
    QueueNotify: ^WORD;
    HpQueue: TVirtQueue;
    RqQueue: TVirtQueue;
    Driver: TFilesystemDriver;
    BlkDriver: TBlockDriver;
    FileDesc: TFileBlock;
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
  QUEUE_LEN = 32;
  ROOT_UID = 0;

  VIRTIO_ID_FS = $1a;

var
  FSVirtIO: TVirtIOFSDevice;

function VirtioFSLookUpInode(Ino: PInode; Name: PXChar): PInode; forward;
procedure VirtIOProcessQueue(vq: PVirtQueue); forward;

procedure virtIOFSDedicate(Driver:PBlockDriver; CPUID: LongInt);
begin
  DedicateBlockFile(@FsVirtIO.FileDesc, CPUID);
end;

procedure VirtioFSWriteInode(Ino: PInode);
begin
  WriteConsoleF('VirtioFSWriteInode: This is not implemented yet\n', []);
end;

procedure SetBufferInfo(Buffer: PBufferInfo; Header: Pointer; size: QWORD; flags: Byte);
begin
  Buffer.buffer := Header;
  Buffer.size := size;
  Buffer.flags := flags;
  Buffer.copy := false;
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

  SetBufferInfo(@BufferInfo[0], @InHeader, sizeof(InHeader), 0);
  SetBufferInfo(@BufferInfo[1], @ReleaseIn, sizeof(ReleaseIn), 0);
  SetBufferInfo(@BufferInfo[2], @OutHeader, sizeof(OutHeader), VIRTIO_DESC_FLAG_WRITE_ONLY);

  VirtIOAddBuffer(FsVirtio.Base, @FsVirtIO.RqQueue, @BufferInfo[0], 3);
  while not Done do;

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

  SetBufferInfo(@BufferInfo[0], @InHeader, sizeof(InHeader), 0);
  SetBufferInfo(@BufferInfo[1], @OpenIn, sizeof(OpenIn), 0);
  SetBufferInfo(@BufferInfo[2], @OutHeader, sizeof(OutHeader), VIRTIO_DESC_FLAG_WRITE_ONLY);
  SetBufferInfo(@BufferInfo[3], @OpenOut, sizeof(OpenOut), VIRTIO_DESC_FLAG_WRITE_ONLY);

  VirtIOAddBuffer(FsVirtio.Base, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do;

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

  SetBufferInfo(@BufferInfo[0], @InHeader, sizeof(InHeader), 0);
  SetBufferInfo(@BufferInfo[1], @MknodIn, sizeof(MknodIn), 0);
  SetBufferInfo(@BufferInfo[2], Pointer(Name), Len, 0);
  SetBufferInfo(@BufferInfo[3], @OutHeader, sizeof(OutHeader), VIRTIO_DESC_FLAG_WRITE_ONLY);

  VirtIOAddBuffer(FsVirtio.Base, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do;

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

  SetBufferInfo(@BufferInfo[0], @InHeader, sizeof(InHeader), 0);
  SetBufferInfo(@BufferInfo[1], @WriteIn, sizeof(WriteIn), 0);
  SetBufferInfo(@BufferInfo[2], Pointer(buffer), Count, 0);
  SetBufferInfo(@BufferInfo[3], @OutHeader, sizeof(OutHeader), VIRTIO_DESC_FLAG_WRITE_ONLY);
  SetBufferInfo(@BufferInfo[4], @WriteOut, sizeof(WriteOut), VIRTIO_DESC_FLAG_WRITE_ONLY);

  VirtIOAddBuffer(FsVirtio.Base, @FsVirtIO.RqQueue, @BufferInfo[0], 5);

  while not Done do;

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

  SetBufferInfo(@BufferInfo[0], @InHeader, sizeof(InHeader), 0);
  SetBufferInfo(@BufferInfo[1], @ReadIn, sizeof(ReadIn), 0);
  SetBufferInfo(@BufferInfo[2], @OutHeader, sizeof(OutHeader), VIRTIO_DESC_FLAG_WRITE_ONLY);
  SetBufferInfo(@BufferInfo[3], Pointer(buffer), Count, VIRTIO_DESC_FLAG_WRITE_ONLY);

  VirtIOAddBuffer(FsVirtio.Base, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do;

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

  SetBufferInfo(@BufferInfo[0], @InHeader, sizeof(InHeader), 0);
  SetBufferInfo(@BufferInfo[1], Pointer(Name), Len, 0);
  SetBufferInfo(@BufferInfo[2], @OutHeader, sizeof(OutHeader), VIRTIO_DESC_FLAG_WRITE_ONLY);
  SetBufferInfo(@BufferInfo[3], @EntryOut, sizeof(EntryOut), VIRTIO_DESC_FLAG_WRITE_ONLY);

  VirtIOAddBuffer(FsVirtio.Base, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do;

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

  SetBufferInfo(@BufferInfo[0], @InHeader, sizeof(InHeader), 0);
  SetBufferInfo(@BufferInfo[1], @GetAttrIn, sizeof(GetAttrIn), 0);
  SetBufferInfo(@BufferInfo[2], @OutHeader, sizeof(OutHeader), VIRTIO_DESC_FLAG_WRITE_ONLY);
  SetBufferInfo(@BufferInfo[3], @GetAttrOut, sizeof(GetAttrOut), VIRTIO_DESC_FLAG_WRITE_ONLY);

  VirtIOAddBuffer(FsVirtio.Base, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do;

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

  SetBufferInfo(@BufferInfo[0], @InHeader, sizeof(InHeader), 0);
  SetBufferInfo(@BufferInfo[1], @InitIn, sizeof(InitIn), 0);
  SetBufferInfo(@BufferInfo[2], @OutHeader, sizeof(OutHeader), VIRTIO_DESC_FLAG_WRITE_ONLY);
  SetBufferInfo(@BufferInfo[3], @InitOut, sizeof(InitOut), VIRTIO_DESC_FLAG_WRITE_ONLY);

  VirtIOAddBuffer(FsVirtio.Base, @FsVirtIO.RqQueue, @BufferInfo[0], 4);

  while not Done do;

  if OutHeader.error <> 0 then
   Exit;

  Super.InodeROOT := GetInode(FUSE_ROOT_ID);

  If Super.InodeROOT = nil then
    Exit;

  Result := Super;
end;

// Callback to handle interruptions on vqs
procedure VirtIOProcessQueue(vq: PVirtQueue);
var
  index, buffer_index: Word;
  QueueBuffer: PQueueBuffer;
  InHeader: ^TFuseInHeader;
  p: ^Boolean;
begin
  index := VirtIOGetBuffer(vq);
  buffer_index := vq.used.rings[index].index;
  QueueBuffer := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));
  InHeader := Pointer(QueueBuffer.address);
  p := Pointer(InHeader.unique);
  Panic(p^ = True, 'VirtioFS: Waking up a thread in ready state\n', []);
  p^ := True;
end;

function InitVirtIOFS(Device: PVirtIOMMIODevice): Boolean;
begin
  Result := False;
  FsVirtio.IRQ := Device.Irq;
  FsVirtio.Base := Device.Base;
  FsVirtio.QueueNotify := Pointer(Device.Base + MMIO_QUEUENOTIFY);
  FsVirtio.FsConfig := Pointer(Device.Base + MMIO_CONFIG);
  WriteConsoleF('VirtIOFS: tag: %p, nr queues: %d\n', [PtrUInt(@FsVirtio.FsConfig.tag), FsVirtio.FsConfig.numQueues]);
  // set VIRTIO_F_VERSION_1 in the second half of feature QWORD
  SelDriverFeatures(Device.Base, 1);
  SetDriverFeatures(Device.Base, (1 shl VIRTIO_F_VERSION_1) shr 32);
  SetDeviceStatus(Device.Base, VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK);
  if not VirtIOInitQueue(Device.Base, REQUEST_QUEUE, @FsVirtio.RqQueue, QUEUE_LEN, 0) then
  begin
    WriteConsoleF('VirtIOFS: queue 0, failed\n', []);
    Exit;
  end;

  // register queue callback handler
  FsVirtio.RqQueue.VqHandler := @VirtIOProcessQueue;
  Device.Vqs := @FsVirtio.RqQueue;

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
  Result := True;
end;

initialization
  InitVirtIODriver(VIRTIO_ID_FS, @InitVirtIOFS);
end.
