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
    buffer: ^Byte;
    size: QWord;
    flags: Byte;
  end;

  TVirtIOFsConfig = packed record
    tag: array[0..35] of Char;
    numQueues: DWORD;
  end;

  TVirtIOPciCommonCfg = packed record
    device_feature_select: DWORD;
    device_feature: DWORD;
    driver_feature_select: DWORD;
    driver_feature: DWORD;
    msix_config: WORD;
    num_queues: WORD;
    device_status: Byte;
    config_generation: Byte;
    queue_select: WORD;
    queue_size: WORD;
    queue_msix_vector: WORD;
    queue_enable: WORD;
    queue_notify_off: WORD;
    queue_desc: QWORD;
    queue_avail: QWORD;
    queue_used: QWORD;
  end;

  TVirtIOPciCap = packed record
    cap_vndr: Byte;
    cap_next: Byte;
    cap_len: Byte;
    cfg_type: Byte;
    bar: Byte;
    padding: array [0..2] of Byte;
    offset: DWORD;
    length: DWORD;
  end;

  FuseInHeader = packed record
    len: DWORD;
    opcode: DWORD;
    unique: QWord;
    nodeid: QWord;
    uid: DWORD;
    gid: DWORD;
    pid: DWORD;
    padding: DWORD;
  end;

  FuseOutHeader = packed record
    len: DWORD;
    error: DWORD;
    unique: QWord;
  end;

  FuseInitIn = packed record
    major: DWORD;
    minor: DWORD;
    max_readahead: DWORD;
    flags: DWORD;
  end;

  FuseInitOut = packed record
    major: DWORD;
    minor: DWORD;
    max_readahead: DWORD;
    flags: DWORD;
    max_background: WORD;
    congestion_threshold: WORD;
    max_write: DWORD;
    time_gran: DWORD;
    max_pages: WORD;
    padding: WORD;
    unused: array[0..7] of DWORD;
  end;

  FuseGetAttrIn = packed record
    getattr_flags: DWORD;
    dummy: DWORD;
    fh: QWORD;
  end;

  FuseAttr = packed record
    ino: QWORD;
    size: QWORD;
    blocks: QWORD;
    atime: QWORD;
    mtime: QWORD;
    ctime: QWORD;
    atimensec: DWORD;
    mtimensec: DWORD;
    ctimensec: DWORD;
    mode: DWORD;
    nlink: DWORD;
    uid: DWORD;
    gid: DWORD;
    rdev: DWORD;
    blksize: DWORD;
    padding: DWORD;
  end;

  FuseGetAttrOut = packed record
    attr_valid: QWORD;
    attr_valid_nsec: DWORD;
    dummy: DWORD;
    attr: FuseAttr;
  end;

  FuseEntryOut = packed record
    nodeid: QWORD;
    generation: QWORD;
    entry_valid: QWORD;
    attr_valid: QWORD;
    entry_valid_nsec: DWORD;
    attr_valid_nsec: DWORD;
    attr: FuseAttr;
  end;

  FuseOpenIn = packed record
    flags: DWORD;
    unused: DWORD;
  end;

  FuseOpenOut = packed record
    fh: QWORD;
    open_flags: DWORD;
    padding: DWORD;
  end;

  FuseReadIn = packed record
    fh: QWORD;
    offset: QWORD;
    size: DWORD;
    read_flags: DWORD;
    lock_owner: QWORD;
    flags: DWORD;
    padding: DWORD;
  end;

  FuseReleaseIn = packed record
    fh: QWORD;
    flags: DWORD;
    release_flags: DWORD;
    lock_owner: QWORD;
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

var
  FSVirtIO: TVirtIOFSDevice;

function VirtIOGetDeviceFeatures(Dev: PVirtIOPciCommonCfg): DWORD;
begin
  Result := Dev.device_feature;
end;

// Reset device and negotiate features
function VirtIONegociateFeatures(Dev: PVirtIOPciCommonCfg; Features: DWORD): Boolean;
var
  devfeat: DWORD;
begin
  Result := False;
  Dev.device_status := 0;
  Dev.device_status := VIRTIO_ACKNOWLEDGE;
  Dev.device_status := VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER;
  devfeat := Dev.device_feature;
  devfeat := devfeat and Features;
  // TODO: To check if this is the right field
  Dev.device_feature_select := devfeat;
  Dev.device_status := VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK;
  if ((Dev.device_status and VIRTIO_FEATURES_OK) = 0) then
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
  Dev.queue_select := QueueId;
  Queue.queue_size := Dev.queue_size;
  sizeOfBuffers := (sizeof(TQueueBuffer) * Queue.queue_size);
  sizeofQueueAvailable := (2*sizeof(WORD)+2) + (Queue.queue_size*sizeof(WORD));
  sizeofQueueUsed := (2*sizeof(WORD)+2)+(Queue.queue_size*sizeof(VirtIOUsedItem));
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
  Queue.next_buffer:= 0;
  Queue.lock := 0;
  Dev.queue_desc := QWORD(Queue.buffers);
  Dev.queue_avail := QWORD(Queue.available);
  Dev.queue_used := QWORD(Queue.used);
  Dev.queue_enable := 1;
  Dev.device_status := VIRTIO_ACKNOWLEDGE or VIRTIO_DRIVER or VIRTIO_FEATURES_OK or VIRTIO_DRIVER_OK;
  if ((Dev.device_status and DEVICE_NEEDS_RESET) = DEVICE_NEEDS_RESET) then
    Exit;
  if HeaderLen <> 0 then
  begin
    Queue.Buffer := ToroGetMem(queue.queue_size * (HeaderLen) + 4096);
    Queue.Buffer := Pointer(PtrUint(queue.Buffer) + (4096 - PtrUInt(queue.Buffer) mod 4096));
    Queue.chunk_size := HeaderLen;
  end;
  Result := True;
end;

procedure VirtIOSendBuffer(vq: PVirtQueue; bi:PBufferInfo; count: QWord; QueueIdx: WORD);
var
  index, buffer_index, next_buffer_index: word;
  b: PBufferInfo;
  i: LongInt;
  tmp: PQueueBuffer;
begin
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
    tmp.address:= PtrUInt(b.buffer);
    buffer_index := next_buffer_index;
  end;
  ReadWriteBarrier;
  vq.next_buffer := buffer_index;
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
  th: PThread;
begin
  Result := 0;

  inhd.opcode := FUSE_RELEASE;
  inhd.len := sizeof(inhd) + sizeof(releasein);
  th := GetCurrentThread;
  th.state := tsSuspended;
  inhd.unique := PtrUInt(th);
  inhd.nodeid := FileDesc.INode.ino;
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

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 3, 0);
  SysThreadSwitch;

  if outhd.error <> 0 then
    Exit;

  Result := 1;
end;

function VirtioFSOpenFile(FileDesc: PFileRegular): LongInt;
var
  outhd: FuseOutHeader;
  inhd: FuseInHeader;
  openin: FuseOpenIn;
  openout: FuseOpenOut;
  bi: array[0..3] of TBufferInfo;
  th: PThread;
begin
  Result := 0;

  inhd.opcode := FUSE_OPEN;
  inhd.len := sizeof(inhd) + sizeof(openin);
  inhd.nodeid := FileDesc.Inode.ino;
  th := GetCurrentThread;
  th.state := tsSuspended;
  inhd.unique := PtrUInt(th);
  // TODO: to check flags here for the moment is RO
  openin.flags := 0;

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

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 4, 0);
  SysThreadSwitch;

  if outhd.error <> 0 then
    Exit;

  FileDesc.Opaque := openout.fh;
  Result := 1;
end;

function VirtioFSReadFile(FileDesc: PFileRegular; Count: Longint; Buffer: Pointer): longint;
var
  bi: array[0..3] of TBufferInfo;
  readin: FuseReadIn;
  inhd: FuseInHeader;
  outhd: FuseOutHeader;
  th: PThread;
begin
  Result := 0;
  if FileDesc.FilePos + Count > FileDesc.Inode.Size then
  begin
    Count := FileDesc.Inode.Size - FileDesc.FilePos;
  end;
  inhd.opcode := FUSE_READ;
  inhd.len := sizeof(inhd) + sizeof(readin);
  th := GetCurrentThread;
  th.state := tsSuspended;
  inhd.unique := PtrUInt(th);
  inhd.nodeid := FileDesc.Inode.ino;
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

  VirtIOSendBuffer(@FsVirtio.RqQueue, @bi[0], 4, 0);
  SysThreadSwitch;

  if outhd.error <> 0 then
   Exit;
  Result := Count;
end;

function VirtioFSLookUpInode(Ino: PInode; Name: PXChar): PInode;
var
  len: LongInt;
  lookupout: FuseEntryOut;
  bi: array[0..3] of TBufferInfo;
  inhd: FuseInHeader;
  outhd: FuseOutHeader;
  th: PThread;
begin
  Result := nil;

  Len := strlen(name) + 1;
  inhd.opcode := FUSE_LOOKUP;
  th := GetCurrentThread;
  th.state := tsSuspended;
  inhd.unique := PtrUInt(th);
  inhd.len := sizeof(inhd) + Len ;
  inhd.nodeid := Ino.ino;

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
  SysThreadSwitch;

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
  th: PThread;
begin

  inhd.opcode := FUSE_GETATTR;
  inhd.len := sizeof(inhd) + sizeof(getattrin);
  inhd.nodeid := Ino.ino;
  th := GetCurrentThread;
  th.state := tsSuspended;
  inhd.unique := PtrUInt(th);

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
  SysThreadSwitch;

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
  th: PThread;
begin
  Result := nil;

  inhd.opcode := FUSE_INIT;
  inhd.len := sizeof(inhd) + sizeof(initinhd);
  th := GetCurrentThread;
  th.state := tsSuspended;
  inhd.unique := PtrUInt(th);
  initinhd.major := FUSE_MAJOR_VERSION;
  initinhd.minor := FUSE_MINOR_VERSION;

  // TODO: to check this flags
  initinhd.flags := 0;
  initinhd.max_readahead := TORO_MAX_READAHEAD_SIZE;

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
  SysThreadSwitch;

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
  th: PThread;
begin
  if vq.last_used_index = vq.used.index then
    Exit;

  // wake up the thread in unique
  // which is always the first buffer
  index := vq.last_used_index;
  norm_index := index mod vq.queue_size;
  buffer_index := vq.used.rings[norm_index].index;
  tmp := Pointer(PtrUInt(vq.buffers) + buffer_index * sizeof(TQueueBuffer));
  FuseIn := Pointer(tmp.address);
  th := Pointer(fusein.unique);
  Panic(th.state = tsReady, 'VirtioFS: Waking up a thread in ready state\n', []);
  th.state := tsReady;

  vq.last_used_index := vq.used.index;
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
          WriteConsoleF('VirtIOFS: Queue 0, size: %d, initiated, irq: %d\n', [FsVirtio.RqQueue.queue_size, FsVirtio.IRQ]);
        end else
        begin
          WriteConsoleF('VirtIOFS: Queue 0, failed\n', []);
          Exit;
        end;

        // Set up notification queue
        FsVirtio.QueueNotify := Pointer(PtrUInt(FsVirtio.QueueNotify) + FsVirtio.CommonConfig.queue_notify_off * FsVirtio.NotifyOffMultiplier);
        // enable the irq
        CaptureInt(32+FsVirtio.IRQ, @VirtIOFSIrqHandler);
        IrqOn(FsVirtio.IRQ);
        PciSetMaster(PciDev);
        FsVirtio.RqQueue.used.flags := 0;
        FsVirtio.Driver.name := 'virtiofs';
        FsVirtio.Driver.ReadSuper := @VirtioFSReadSuper;
        FsVirtio.Driver.ReadInode := @VirtioFSReadInode;
        FsVirtio.Driver.WriteInode := @VirtioFSWriteInode;
        FsVirtio.Driver.LookUpInode := @VirtioFSLookUpInode;
        FsVirtio.Driver.ReadFile := @VirtioFSReadFile;
        FsVirtio.Driver.OpenFile := VirtioFSOpenFile;
        FsVirtio.Driver.CloseFile := VirtioFSCloseFile;
        RegisterFilesystem(@FsVirtio.Driver);
        Move(FsVirtio.FsConfig.tag, FsVirtio.BlkDriver.name, StrLen(FsVirtio.FsConfig.tag)+1);
        FsVirtio.BlkDriver.Busy := false;
        FsVirtio.BlkDriver.WaitOn := nil;
        FsVirtio.BlkDriver.major := 0;
        FsVirtIO.BlkDriver.Dedicate := @virtIOFSDedicate;
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
