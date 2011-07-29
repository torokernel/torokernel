//
// Filesystem.pas
// 
// Manipulation of Devices and Filesystem .
// Every Resource is DEDICATE , The programmer must indicate Which CPU can access to the device.
//
// Changes :
// 
// 17/02/2006 First Version by Matias E. Vara.
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
// All Rights Reserved
//
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
unit Filesystem;

interface

{$I Toro.inc}

uses 
  Arch, Process, Console, Memory, Debug;

const
  // Size of Buffers
  MAX_BUFFERS_IN_CACHE = 5000;
  MAX_INODES_IN_CACHE= 300;

  // Inode mode
  INODE_DIR = 1;
  INODE_REG = 2;

  // Whence Values
  SeekSet = 0;
  SeekCur = 1;
  SeekEof = 2;
 
type
  PBlockDriver = ^TBlockDriver;
  PStorage = ^TStorage;
  PFileBlock = ^TFileBlock;
  PBufferHead = ^TBufferHead;
  PFileRegular = ^TFileRegular;
  PSuperBlock = ^TSuperBlock;
  PFileSystemDriver = ^TFileSystemDriver;
  PInode = ^TInode;

  // Driver of Blocks
  TBlockDriver = record
    busy: boolean; // protection for access from Local CPU.
    WaitOn: PThread; // Thread using the Driver.
    Name: string; // Driver identificators is used by the Kernel
    // Internal Identificator can be used by Driver  , is not used by the Kernel
    Major: LongInt;
    // Handlers
    Dedicate: procedure (Controller:PBlockDriver;CPUID: LongInt);
    WriteBlock: function (FileDesc: PFileBlock;Block,Count: LongInt;Buffer: pointer): LongInt;
    ReadBlock: function (FileDesc: PFileBlock;Block,Count: LongInt;Buffer: pointer): LongInt;
    // CPU where is dedicate the driver.
    CPUID: LongInt;
    Next: PBlockDriver;
 end;

 // Buffer-Cache layer
 TBufferCacheSlot = record
  BuffersInCache: Int64;
  BlockCache: PBufferHead;
  FreeBlocksCache: PBufferHead;
 end;
 
 // File Block Descriptor 
 TFileBlock = record
  BlockDriver:PBlockDriver;
  BlockSize: LongInt;
  // Buffer-Cache structures
  BufferCache: TBufferCacheSlot;
  Minor: LongInt;
  next: PFileBlock;
 end;  
 
 // Entry in the Cache of Block
 TBufferHead = record
  block: LongInt ;
  size:  LongInt;
  count: int64;
  dirty: boolean;
  data: pointer;
  next: PBufferHead;
  prev: PBufferHead;
 end; 
 
 // Regular File Descriptor
 TFileRegular = record
  filepos: LongInt;
  Inode: Pinode;
 end;

 // VFS Inode
 TInode = record
  ino: LongInt;
  dirty: boolean;
  count: LongInt;
  size: LongInt;
  sb: PSuperBlock;
  mode: LongInt;
  atime: LongInt;
  ctime: LongInt;
  mtime: LongInt;
  dtime: LongInt;
  InoInfo: pointer;
  next: PInode;
  prev: PInode;
 end;
 
 // Inode-Cache structure
 TInodeCacheSlot= record
  InodesInCache: Int64;
  InodeBuffer: PInode;
  FreeInodesCache: PInode;
 end;
 
 // VFS SuperBlock structure
 TSuperBlock = record
  BlockDevice: PFileBlock;
  InodeROOT: PInode;
  dirty: boolean;
  flags: LongInt;
  BlockSize: LongInt;
  SbInfo: pointer;
  FileSystemDriver: PFilesystemDriver;
  // Dedicate Inode-Cache
  InodeCache: TInodeCacheSlot;
 end;
 
  // VFS Filesystem driver structure
  TFileSystemDriver = record
    Name: string; // FileSystem Name like ext2,fat,etc
    // Regular Files operations
    ReadFile: function (FileDesc: PFileRegular;count: LongInt;Buffer: pointer): LongInt;
    WriteFile: function (FileDesc: PFileRegular;count: LongInt;Buffer: pointer): LongInt;
    // Inode operations
    ReadInode: procedure (Ino: PInode);
    WriteInode: procedure (Ino: Pinode);
    CreateInode: function (Ino: PInode;name: string): PInode;
    RemoveInode: function (Ino:PInode;name: string): LongInt;
    LookupInode: function (Ino: PInode;name: string): PInode;
    // SuperBlock operations
    ReadSuper: function (Spb: PSuperBlock): PSuperBlock;
    Next: PFileSystemDriver;
  end;
 
  // Dedicate access to devices
  // every cpu has this structure
  TStorage = record
    BlockFiles : PFileBlock; // Block File Descriptors
    RegularFiles: PFileBlock; // Regular File Decriptors
    FileSystemMounted: PSuperBlock; // ??? Not sure about it ???
  end;

  // Devices information in PCI BUS
  PBusDevInfo = ^TBusDevInfo;
  TBusDevInfo = record
    bus: LongInt;
    dev: LongInt;
    func: LongInt;
    irq: LongInt;
    io: array[0..5] of LongInt;
    vendor: LongInt;
    device: LongInt;
    mainclass: LongInt;
    subclass: LongInt;
    next: PBusDevInfo;
 end;
 
// Programmer's Interface
procedure FilesystemInit;
procedure GetDevice(Dev:PBlockDriver);
procedure FreeDevice(Dev:PBlockDriver);
procedure RegisterBlockDriver(Driver:PBlockDriver);
procedure RegisterFilesystem (Driver: PFileSystemDriver);
procedure DedicateBlockDriver(const Name: string; CPUID: LongInt);
procedure DedicateBlockFile(FBlock: PFileBlock;CPUID: LongInt);
procedure SysMount(const FileSystemName, BlockName: string; Minor: LongInt);
function SysOpenFile(Path:pchar): THandle;
function SysStatFile(Path: PChar; Buffer: PInode): LongInt;
function SysSeekFile(FileDesc: THandle; Offset, Whence: LongInt): LongInt;
function SysReadFile(FileDesc: THandle; Count: LongInt;Buffer:pointer): LongInt;
function SysWriteFile(FileDesc: THandle; Count: LongInt; Buffer:pointer): LongInt;
function SysWriteBlock(Fl: THandle; Block, Count: LongInt; Buffer: pointer): LongInt;
procedure SysCloseFile(FileDesc: THandle);
function SysReadBlock(Fl: THandle;Block,Count: LongInt; Buffer: Pointer): LongInt;
function SysOpenBlock (const Name: string; Minor: LongInt): THandle;
function GetBlock(PFl: PFileBlock; Block, Size: LongInt): PBufferHead;
procedure PutBlock(PFl: PFileBlock; Bh: PBufferHead);
function GetInode(Inode: LongInt): PInode;
procedure PutInode(Inode: PInode);

var
  PCIDevices: PBusDevInfo; // List of Devices in PCI Bus .
  FilesystemDrivers: PFileSystemDriver; // Filesystem Drivers installed
 
implementation

var
  Storages: array [0..MAX_CPU-1] of TStorage; // Dedicated Storage
  BlockDevices: PBlockDriver; // Block Drivers installed

//------------------------------------------------------------------------------
// PCI kernel's driver implementation
//------------------------------------------------------------------------------
// TODO : Remove PCI detection in Filesystem's Unit.

const
 ADDPCISTART = $e0000;
 MAX_PCIBUS = 4;
 MAX_PCIDEV = 32;
 MAX_PCIFUNC = 8;
 PCI_CONF_PORT_INDEX = $CF8;
 PCI_CONF_PORT_DATA  = $CFC;
 PCI_CONFIG_INTR        = 15;
 PCI_CONFIG_VENDOR      = 0;
 PCI_CONFIG_CLASS_REV   = 2;
 PCI_CONFIG_BASE_ADDR_0 = 4;
 PCI_BAR                = $10;

type
 PBios32 = ^Tbios32;
 Tbios32 = record
  magic : LongInt;
  phys_entry : LongInt;
  revision : byte;
  length : byte;
  crc : char;
  reserved : array [1..5] of byte;
 end;

// Detect all devices in PCI Buses.
procedure PciDetect;
var
 dev,func,bus,vendor,device: LongInt;
 pdev: PBusDevInfo;
 tmp,btmp,i: dword;
begin
// this is not the best way to look the PCI devices.
for bus:= 0 to (MAX_PCIBUS-1) do
begin
 for dev:= 0 to (MAX_PCIDEV-1) do
 begin
  for func:= 0 to (MAX_PCIFUNC-1) do
  begin
   tmp := PciReadDword(bus,dev,func,PCI_CONFIG_VENDOR);
   vendor := tmp and $FFFF;
   device := tmp div 65536;
   // some bug
   if func=0 then
    btmp:=device
   else if device = btmp then
    break;
   // the device exist
   if (vendor <> $ffff) and (vendor <> 0) then
   begin
    pdev := ToroGetMem(sizeof(TBusDevInfo));
    if (pdev=nil) then
     exit;
	pdev.device:=device;
	pdev.vendor:=vendor;
	tmp := PciReadDword(bus,dev,func,PCI_CONFIG_CLASS_REV);
	pdev.mainclass := tmp div 16777216;
	pdev.subclass := (tmp div 65536) and $ff;
	for i:= 0 to 5 do
	begin
	 tmp:=PciReadDword(bus,dev,func,PCI_CONFIG_BASE_ADDR_0+i);
         if (tmp and 1) = 1 then
          // IO port
	  pdev.io[i] := tmp and $FFFFFFFC
         else
          // Memory Address
          pdev.io[i] := longint(tmp);
        end;
	tmp:= PciReadDword(bus,dev,func,PCI_CONFIG_INTR);
	pdev.irq := tmp and $ff;
	pdev.bus := bus;
	pdev.func := func;
	pdev.dev:=dev;
	// the device is enque
	pdev.Next:=PciDevices;
    PciDevices:=pdev;
   end;
  end;
 end;
end;
end;

//
// PciInit :
// Initialization of structures
//
procedure PCIInit;
//var
// fd: PBios32;
begin
  PciDetect;

{
fd := pointer(ADDPCISTART);
printK_('PCI Driver ...',0);
while (fd < pointer($100000)) do
begin
 if fd.magic=$5F32335F then
 begin
  printK_('/VOk!\n/n',0);
  PciDetect;
  exit;
 end;
fd :=fd+1;
end;
printk_('/RFault\n/n',0); }
end;

// The driver is enque in Block Drivers tail.
procedure RegisterBlockDriver(Driver: PBlockDriver);
begin
  Driver.Next := BlockDevices;
  BlockDevices := Driver;
  {$IFDEF DebugFilesystem} DebugTrace('RegisterBlockDriver: New Driver', 0, 0, 0); {$ENDIF}
end;

// Protect the device of access from LOCAL CPU .
// For access from others CPU, it doesn't need protection because the device is DEDICATE.
procedure GetDevice(Dev: PBlockDriver);
var
  CurrentCPU: PCPU;
begin
  CurrentCPU := @CPU[GetApicid];
  if Dev.busy then
  begin
    // information for scheduling
    CurrentCPU.CurrentThread.State := tsIOPending;
    CurrentCPU.CurrentThread.IOScheduler.DeviceState:=@Dev.busy;
    {$IFDEF DebugFilesystem} DebugTrace('GetDevice: Sleeping', 0, 0, 0); {$ENDIF}
    ThreadSwitch;
  end;
  CurrentCPU.CurrentThread.IOScheduler.DeviceState:=nil;
  Dev.busy := True;
  Dev.WaitOn := CurrentCPU.CurrentThread;
  {$IFDEF DebugFilesystem} DebugTrace('GetDevice: Device in use', 0, 0, 0); {$ENDIF}
end;

// Free the use of device.
procedure FreeDevice(Dev: PBlockDriver);
begin
  Dev.busy := False;
  Dev.WaitOn:= nil;
  {$IFDEF DebugFilesystem} DebugTrace('FreeDevice: Device is Free', 0, 0, 0); {$ENDIF}
end;

// DedicateBlockFiles:
// Only called by Driver. Creates a Block file's descriptors in CPUID.
procedure DedicateBlockFile(FBlock: PFileBlock;CPUID: LongInt);
var
 CurrSTOS: PStorage;
begin
CurrSTOS := @Storages[CPUID];
FBlock.Next := CurrSTOS.BlockFiles;
CurrSTOS.BlockFiles := FBlock;
// cleaning Buffer Cache slot
FBlock.BufferCache.BuffersInCache:= MAX_BUFFERS_IN_CACHE;
FBlock.BufferCache.BlockCache:= nil;
FBlock.BufferCache.FreeBlocksCache:= nil;

  {$IFDEF DebugFilesystem} DebugTrace('DedicateBlockFile: New Block File Descriptor on CPU#%d , Minor: %d', 0, CPUID, FBlock.Minor); {$ENDIF}
end;

// Return a pointer to Block file's descriptor .
function SysOpenBlock(const Name: string; Minor: LongInt): THandle;
var
  CurrSTOS: PStorage;
  fl: PFileBlock;
begin
  CurrSTOS := @Storages[GetApicid];
  fl := CurrSTOS.BlockFiles;
  while (fl <> nil) do
  begin
    if (fl.BlockDriver.Name=Name) and (fl.Minor=Minor) then
    begin
      Result := Thandle(fl);
      {$IFDEF DebugFilesystem} DebugTrace('SysOpenBlock: Handle %q',Int64(result),0,0); {$ENDIF}
      Exit;
    end;
    fl:=fl.Next;
  end;
  Result := 0;
  {$IFDEF DebugFilesystem} DebugTrace('SysOpenBlock: Fail , Minor: %d',0,Minor,0); {$ENDIF}
end;

// Dedicate the Driver to CPU in CPUID variable.
procedure DedicateBlockDriver(const Name: string; CPUID: LongInt);
var
  dev: PBlockDriver;
begin
  dev := BlockDevices;
  while dev <> nil do
  begin
    if (dev.Name = name) and (dev.CPUID = -1) then
    begin
      dev.dedicate(Dev,CPUID);
      dev.CPUID := CPUID;
      {$IFDEF DebugFilesystem} DebugTrace('DedicateBlockDriver: New Driver dedicate to CPU#%d',0,CPUID,0); {$ENDIF}
      Exit;
    end;
    dev := dev.Next;
  end;
  {$IFDEF DebugFilesystem} DebugTrace('DedicateBlockDriver: Driver does not exist',0,0,0); {$ENDIF}
end;

// Write operation to Block Device.
function SysWriteBlock(Fl: THandle; Block, Count: LongInt; Buffer: pointer): LongInt;
var 
  PFl: PFileBlock;
begin
  PFl := PFileBlock(Fl);
  Result := PFl.BlockDriver.WriteBlock(PFl,Block,Count,Buffer);
  {$IFDEF DebugFilesystem} DebugTrace('SysWriteBlock: Handle %q, Result: %d', Int64(Fl), Result, 0); {$ENDIF}
end;

// Read Operation to Block Device
function SysReadBlock(Fl: THandle; Block, Count: LongInt; Buffer: Pointer): LongInt;
var 
 PFl: PFileBlock;
begin
  PFl := PFileBlock(Fl);
  Result := PFl.BlockDriver.ReadBlock(PFl,Block,Count,Buffer);
  {$IFDEF DebugFilesystem} DebugTrace('SysReadBlock: Handle %q,Result: %d', Int64(Fl), Result, 0); {$ENDIF}
end;

function FindBlock(Buffer: PBufferHead;Block,Size: LongInt): PBufferHead;
var
 Bhd: PBufferHead;
begin
result:= nil;
if Buffer=nil then
 exit;
Bhd:= Buffer;
repeat
 if (Buffer.block=Block) and (Buffer.Size=Size) then
 begin
  result:= Buffer;
  exit;
 end;
Buffer:= Buffer.Next;
until (Buffer=Bhd);
end;

procedure AddBuffer(var Queue: PBufferHead;bh: PBufferHead);
begin
if Queue= nil then
begin
 Queue:= bh;
 bh.Next:= bh;
 bh.prev:= bh;
 exit;
end;
bh.prev:= Queue.prev;
bh.Next:= Queue;
Queue.prev.Next:= bh;
Queue.prev:= bh;
end;


procedure RemoveBuffer(var Queue: PBufferHead;bh: PBufferHead);
begin
  if (Queue = bh) and (Queue.Next = Queue) then
  begin
    Queue:= nil;
    bh.Next:= nil;
    bh.prev:= nil;
    Exit;
  end;
  if Queue = bh then
    Queue := bh.Next;
  bh.prev.Next := bh.Next;
  bh.Next.prev := bh.prev;
  bh.Next := nil;
  bh.prev := nil;
end;

// Return a block from Buffer Cache in PFl block file.
function GetBlock(PFl: PFileBlock; Block, Size: LongInt): PBufferHead;
var
  bh: PBufferHead;
begin
  // Buffers in use
  bh := FindBlock(PFl.BufferCache.BlockCache,Block,Size);
  if bh <> nil then
  begin
    bh.count := bh.count+1;
    Result := bh;
    {$IFDEF DebugFilesystem} DebugTrace('GetBlock: Block: %d , Size: %d, In use', 0, Block, Size); {$ENDIF}
    Exit;
  end;
  // Free Buffers.
  bh := FindBlock(PFl.BufferCache.FreeBlocksCache,Block,Size);
  if bh <> nil then
  begin
    RemoveBuffer(PFl.BufferCache.FreeBlocksCache,bh);
    AddBuffer(PFl.BufferCache.BlockCache,bh);
    bh.count:= 1;
    Result:= bh;
    {$IFDEF DebugFilesystem} DebugTrace('GetBlock: Block: %d , Size: %d, In Free Block', 0, Block, Size); {$ENDIF}
    Exit;
  end;
  if PFl.BufferCache.BuffersInCache=0 then
  begin
    bh := PFl.BufferCache.FreeBlocksCache;
    if bh = nil then
    begin
      Result := nil;
      Exit;
    end;
    // last Block in Cache
    bh := bh.prev;
    if PFl.BlockDriver.ReadBlock(PFl,Block*(bh.size div PFL.BlockSize),bh.size div PFl.BlockSize ,bh.data) = 0 then
    begin
      Result:=nil;
      Exit;
    end;
    bh.count := 1;
    bh.block := block;
    bh.dirty := False;
    RemoveBuffer(PFl.BufferCache.FreeBlocksCache,bh);
    AddBuffer(PFl.BufferCache.BlockCache,bh);
    Result := bh;
    Exit;
  end;
  bh := ToroGetMem(sizeof(TBufferHead));
  if bh = nil then
  begin
    Result := nil;
    Exit;
  end;
  bh.data:= ToroGetMem(Size);
  if bh.data = nil then
  begin
    ToroFreeMem(bh);
    Result := nil;
    Exit;
  end;
  bh.count:= 1;
  bh.size:= Size;
  bh.dirty:= False;
  bh.block:= Block;
  if PFl.BlockDriver.ReadBlock(PFl, Block*(bh.size div PFL.BlockSize), Size div Pfl.BlockSize, bh.data) = 0 then
  begin
    ToroFreeMem(bh.data);
    ToroFreeMem(bh);
    Result := nil;
    Exit;
  end;
  AddBuffer(PFl.BufferCache.BlockCache,bh);
  PFl.BufferCache.BuffersInCache := PFl.BufferCache.BuffersInCache -1;
  Result := bh;
  {$IFDEF DebugFilesystem} DebugTrace('GetBlock: Block: %d , Size: %d, New in Buffer', 0, Block, Size); {$ENDIF}
end;

// Return a block to Buffer Cache in PFL FileBlock descriptor
procedure PutBlock(PFl: PFileBlock; Bh: PBufferHead);
begin
  Bh.count := Bh.count-1;
  if Bh.count = 0 then
  begin
    if Bh.dirty then
      PFl.BlockDriver.WriteBlock(PFl,bh.block,1,bh.data); // TODO: Test write operations
    Bh.dirty := False;
    RemoveBuffer(PFl.BufferCache.BlockCache,bh);
    AddBuffer(PFl.BufferCache.FreeBlocksCache,bh);
  end;
end;



function FindInode(Buffer: PInode;Inode: LongInt): PInode;
var
 Inohd: PInode;
begin
result:= nil;
If Buffer=nil then 
 exit;
Inohd:= Buffer;
repeat
 if Buffer.Ino=Inode then
 begin
  result:= Buffer;
  exit;
 end;
Buffer:= Buffer.Next;
until (Buffer=Inohd);
end;


procedure AddInode(var Queue: PInode;Inode: PInode);
begin
if Queue= nil then
begin
 Queue:= Inode;
 Inode.Next:= Inode;
 Inode.prev:= InoDE;
 exit;
end;
Inode.prev:= Queue.prev;
Inode.Next:= Queue;
Queue.prev.Next:= Inode;
Queue.prev:= Inode;
end;

procedure RemoveInode(var Queue: PInode;Inode: PInode);
begin
if (Queue=Inode) and (Queue.Next=Queue) then
begin
 Queue:= nil;
 Inode.Next:= nil;
 Inode.prev:= nil;
 exit;
end;
if Queue=Inode then
 Inode:=Inode.Next;
Inode.prev.Next:= Inode.Next;
Inode.Next.prev:= Inode.prev;
Inode.Next:= nil;
Inode.prev:= nil;
end;


//
// GetInode:
// Return a Inode from Inode-Cache of Local FileSystem Mounted
//
function GetInode(Inode: LongInt): PInode;
var
 CurrStos: PStorage;
 Ino: PInode;
begin
CurrStos:= @Storages[GetApicid];
// Is the Inode in Use?
Ino:= FindInode(CurrStos.FileSystemMounted.InodeCache.InodeBuffer,Inode);
if Ino<>nil then
begin
  Ino.count := Ino.count+1;
  Result := Ino;
  {$IFDEF DebugFilesystem} DebugTrace('GetInode: Inode: %d In Inode-Cache', 0, Ino.ino, 0); {$ENDIF}
  Exit;
end;
// Is the Inode in Free Tail?
Ino:= FindInode(CurrStos.FilesystemMounted.InodeCache.FreeInodesCache,Inode);
If Ino<>nil then 
begin
 RemoveInode(CurrStos.FilesystemMounted.InodeCache.FreeInodesCache,Ino);
 AddInode(CurrStos.FilesystemMounted.InodeCache.InodeBuffer,Ino);
 result:= Ino;
 Ino.count:= 1;
 {$IFDEF DebugFilesystem}
  DebugTrace('GetInode: Inode: %d In Inode-Cache',0,Ino.ino,0);
 {$ENDIF}
 exit;
end;
// Can i alloc memory for new Inode?
If CurrStos.FilesystemMounted.InodeCache.InodesInCache=0 then
begin
 Ino:= CurrStos.FilesystemMounted.InodeCache.FreeInodesCache;
 // the buffer is completed
 If Ino=nil then
 begin
  result:= nil;
  {$IFDEF DebugFilesystem}
   DebugTrace('GetInode: Inode Cache is Busy!',0,0,0);
  {$ENDIF}
  exit;
 end;
 // Is a LRU Tail
 Ino:= Ino.prev;
 Ino.ino:= Inode;
 Ino.dirty:= False;
 Ino.sb:= CurrStos.FileSystemMounted;
 Ino.sb.FileSystemDriver.ReadInode(Ino);
 // Error in read operations
 If Ino.dirty then
 begin
  result:= nil;
  {$IFDEF DebugFilesystem}
   DebugTrace('GetInode: Error reading Inode: %d',0,Inode,0);
  {$ENDIF}
  exit;
 end;
 result:= Ino;
 // add inode to  List of Inode in Use
 RemoveInode(CurrStos.FilesystemMounted.InodeCache.FreeInodesCache,Ino);
 AddInode(CurrStos.FilesystemMounted.InodeCache.InodeBuffer,Ino);
 {$IFDEF DebugFilesystem}
  DebugTrace('GetInode: Inode: %d In Inode-Cache',0,Ino.ino,0);
 {$ENDIF}
 exit;
end;
// I can alloc more memory to Inode-Cache
Ino:= ToroGetMem(sizeof(TInode));
If Ino=nil then 
begin 
 result:=nil;
 exit;
end;
Ino.ino:= Inode;
Ino.dirty:= False;
Ino.count:= 1;
Ino.sb:= CurrStos.FileSystemMounted;
CurrStos.FileSystemMounted.FileSystemDriver.ReadInode(Ino);
If Ino.dirty then
begin
 ToroFreeMem(Ino);
 result:= nil;
 {$IFDEF DebugFilesystem}
  DebugTrace('GetInode: Error reading Inode: %d',0,Inode,0);
 {$ENDIF}
 exit;
end;
AddInode(CurrStos.FilesystemMounted.InodeCache.InodeBuffer,Ino);
CurrStos.FilesystemMounted.InodeCache.InodesInCache:= CurrStos.FilesystemMounted.InodeCache.InodesInCache-1;
result:= Ino;
{$IFDEF DebugFilesystem}
 DebugTrace('GetInode: Inode: %d In Inode-Cache',0,Ino.ino,0);
{$ENDIF}
end;


//
// PutInode:
// Return a Inode to Inode-Cache
//
procedure PutInode(Inode: PInode);
begin
Inode.count:= Inode.count-1;
// the inode is moved to Free Inode cache
If Inode.count=0 then
begin
 If Inode.dirty then
  Inode.sb.FileSystemDriver.WriteInode(Inode);
 // here , if dirty=True then error in write operations
 RemoveInode(Inode.sb.InodeCache.InodeBuffer,Inode);
 AddInode(Inode.sb.InodeCache.FreeInodesCache,Inode);
 {$IFDEF DebugFilesystem}
  DebugTrace('PutInode: Inode %d return to Inode-LRU Cache',0,Inode.ino,0);
 {$ENDIF}
end;
end;

//
// RegisterFileSystem:
// Register a FileSystem Driver.
//
procedure RegisterFilesystem (Driver: PFileSystemDriver);
begin
  Driver.Next := FilesystemDrivers;
  FilesystemDrivers := Driver;
  {$IFDEF DebugFilesystem} DebugTrace('RegisterFilesystem: New Driver', 0, 0, 0); {$ENDIF}
end;

// Mount on current CPU the Filesystem, allocated in BlockName\Minor Device.
procedure SysMount(const FileSystemName, BlockName: string; Minor: LongInt);
var
  CurrSTOS: PStorage;
  fl: PFileBlock;
  Spb: PSuperBlock;
  PFs: PFileSystemDriver;
label _fail,_domount;
begin
  CurrSTOS := @Storages[GetApicid];
  fl := CurrSTOS.BlockFiles;
  // Is the Device valid?
  while (fl <> nil) do
  begin
    if (fl.BlockDriver.Name = BlockName) and (fl.Minor = Minor) then
    begin
      PFs := FileSystemDrivers;
      // Is the FileSystem valid?
      while PFs <> nil do
      begin
        if Pfs.Name = FilesystemName then
          goto _domount;
        Pfs:= Pfs.Next;
      end;
      printk_('CPU#%d : MountRoot Fail , unknow filesystem! \n',GetApicid);
      goto _fail;
    end;
    fl := fl.Next;
  end;
  printk_('CPU#%d : MountRoot Fail , unknow device! \n',GetApicid);

_fail:
  {$IFDEF DebugFilesystem}
    DebugTrace('SysMount: Mounting Root Filesystem -----> Fail',0,0,0);
  {$ENDIF}
  Exit;

_domount:
  // I can mount
  Spb:= ToroGetMem(sizeof(TSuperBlock));
  if Spb=nil then
    goto _fail;
  Spb.BlockDevice:= Fl;
  Spb.FileSystemDriver:= PFs;
  Spb.dirty:= False;
  Spb.flags:= 0;
  // Inode-Buffer Initialization
  Spb.InodeCache.InodesInCache:=  MAX_INODES_IN_CACHE;
  Spb.InodeCache.InodeBuffer:= nil;
  Spb.InodeCache. FreeInodesCache:= nil;
  // error in read operations
  CurrSTOS.FileSystemMounted:= Spb;
  if Pfs.ReadSuper(Spb)=nil then
  begin
    printK_('CPU#%d : Fail Reading SuperBlock\n', GetApicid);
    ToroFreeMem(Spb);
    CurrSTOS.FileSystemMounted := nil;
    goto _fail;
  end;
  {$IFDEF DebugFilesystem}
    DebugTrace('SysMount: Mounting Root Filesystem -----> Ok', 0, 0, 0);
  {$ENDIF}
  printK_('/VCore#%d/n : ROOT-Filesystem /VMounted/n\n', GetApicid);
end;

// Return the last Inode of path
function NameI (path: pchar) : PInode;
var 
  name: string;
  base: PInode;
  ino: PInode;
  Count: LongInt;
begin
  base := Storages[GetApicid].FileSystemMounted.InodeROOT;
  base.count := base.count+1;
  path := path+1;
  Count := 1;
  Result := nil;
  SetLength(Name, 0);
  while (path^ <> #0) do
  begin
    if path^ = '/' then
    begin
      // only inode dir please!
      if base.mode= INODE_DIR then
        ino:= base.sb.FilesystemDriver.LookUpInode(base, name)
      else
      begin
        PutInode(base);
        Exit;
      end;
      PutInode(Base);
      // error in operation
      if ino = nil then
        Exit;
      SetLength(Name, 0);
      base := ino;
      path := path+1;
      count := 1;
    end else begin
      SetLength(Name, Length(Name)+1);
      name[count] := path^;
      count := count+1;
      path := path+1;
    end;
  end;
  if name[count] = '/' then
  begin
    Result := base;
    Exit;
  end;
  ino := base.sb.FilesystemDriver.LookUpInode(base,name);
  PutInode(Base);
  Result := ino;
end;

//
// SysOpenFile :
// Open Regular File
//

function SysOpenFile(Path:pchar): THandle;
var
  pfl: PFileRegular;
  Ino: PInode;
begin
  pfl := ToroGetMem(sizeof(TFileRegular));
  result := 0;
  // we don't have memory!
  if pfl=nil then
    Exit;
  Ino:= NameI(Path);
  // looking for the inode from the path
  if Ino=nil then
  begin
    ToroFreeMem(pfl);
    {$IFDEF DebugFileSystem} DebugTrace('SysOpenFile: File not found',0,0,0); {$ENDIF}
    Exit;
  end;
  pfl.filepos := 0;
  pfl.Inode := Ino;
  // the descriptor is not enque in the tail , i don't need this
  Result := THandle(pfl);
  {$IFDEF DebugFileSystem} DebugTrace('SysOpenFile: File Openned',0,0,0); {$ENDIF}
end;

// Return Inode Information about last file in the path
function SysStatFile(Path: PChar; Buffer: PInode): LongInt;
var
  INode: PInode;
begin
  INode := NameI(Path);
  if INode = nil then
  begin
    // bad path
    Result := 0;
    Exit;
  end;
  Buffer^ := INode^;
  PutInode(INode);
  Result := 1;
end;

// Changes position of the File. I don't need the FileSystem Driver here.
function SysSeekFile(FileDesc: THandle; Offset, Whence: LongInt): LongInt;
var
 pfl: PFileRegular;
begin
pfl:= PFileRegular(Filedesc);
if pfl.Inode.mode=INODE_DIR then
 result:=0
else
begin
 case Whence of 
  SeekSet: pfl.filepos:= Offset;
  SeekCur: pfl.filepos:= pfl.filepos+Offset;
  SeekEof: pfl.filepos:= pfl.Inode.size;
 end;
 result:= pfl.filepos;
end; 
end;

// Read from Regular File
function SysReadFile(FileDesc: THandle;count:LongInt;Buffer:pointer): LongInt;
var
  pfl: PFileRegular;
begin
  pfl:= PFileRegular(FileDesc);
  if pfl.Inode.mode = INODE_DIR then
    Result:=0
  else
    Result:= pfl.Inode.Sb.FileSystemDriver.ReadFile(pfl,Count,Buffer);
  pfl.filepos := pfl.filepos + result;
  {$IFDEF DebugFileSystem} DebugTrace('SysReadFile: %d bytes readed, FilePos: %d', 0, Result, pfl.filepos); {$ENDIF}
end;

// Write to Regular File
function SysWriteFile(FileDesc: THandle;count:LongInt;Buffer:pointer): LongInt;
var
  pfl: PFileRegular;
begin
  pfl:= PFileRegular(FileDesc);
  if pfl.Inode.mode=INODE_DIR then
    Result:=0
  else
    Result:= pfl.Inode.Sb.FileSystemDriver.WriteFile(pfl,Count,Buffer);
  pfl.filepos := pfl.filepos + result;
  {$IFDEF DebugFileSystem} DebugTrace('SysWriteFile: %d bytes written, FilePos: %d', 0, Result, pfl.filepos); {$ENDIF}
end;

// Close regular File , very simple only return the inode and free memory
procedure SysCloseFile(FileDesc: THandle);
var
  pfl: PFileRegular;
begin
  pfl:= PFileRegular(FileDesc);
  PutInode(pfl.inode);
  ToroFreeMem(pfl);
end;

// Initialization of Virtual FileSystem's structures.
procedure FilesystemInit;
var
  I: LongInt;
begin
  printK_('Virtual Filesystem TORO ... /VOk!/n\n',0);
  for I := 0 to MAX_CPU-1 do
  begin
    Storages[I].BlockFiles :=nil;
    Storages[I].FileSystemMounted :=nil;
  end;
  BlockDevices := nil;
  FilesystemDrivers := nil;
  PCIDevices := nil;
  PCIinit;
end;


end.
