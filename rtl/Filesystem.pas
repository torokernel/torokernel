//
// FileSystem.pas
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
unit FileSystem;

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
    Busy: Boolean; // protection for access from Local CPU.
    WaitOn: PThread; // Thread using the Driver.
    Name: AnsiString; // Driver identificators is used by the Kernel
    // Internal Identificator can be used by Driver  , is not used by the Kernel
    Major: LongInt;
    // Handlers
    Dedicate: procedure (Controller:PBlockDriver;CPUID: LongInt);
    WriteBlock: function (FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
    ReadBlock: function (FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
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
    Next: PFileBlock;
  end;
 
 // Entry in the Cache of Block
  TBufferHead = record
    Block: LongInt ;
    size:  LongInt;
    Count: int64;
    Dirty: Boolean;
    data: Pointer;
    next: PBufferHead;
    Prev: PBufferHead;
  end;
 
  // Regular File Descriptor
  TFileRegular = record
    FilePos: LongInt;
    Inode: PInode;
  end;

  // VFS Inode
  TInode = record
    ino: LongInt;
    Dirty: Boolean;
    Count: LongInt;
    Size: LongInt;
    SuperBlock: PSuperBlock;
    Mode: LongInt;
    ATime: LongInt;
    CTime: LongInt;
    MTime: LongInt;
    DTime: LongInt;
    InoInfo: Pointer;
    Next: PInode;
    Prev: PInode;
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
    Dirty: Boolean;
    Flags: LongInt;
    BlockSize: LongInt;
    SbInfo: Pointer;
    FileSystemDriver: PFilesystemDriver;
    // Dedicate Inode-Cache
    InodeCache: TInodeCacheSlot;
  end;

  // VFS Filesystem driver structure
  TFileSystemDriver = record
    Name: AnsiString; // FileSystem Name like ext2,fat,etc
    // Regular Files operations
    ReadFile: function (FileDesc: PFileRegular;count: LongInt;Buffer: Pointer): LongInt;
    WriteFile: function (FileDesc: PFileRegular;count: LongInt;Buffer: Pointer): LongInt;
    // Inode operations
    ReadInode: procedure (Ino: PInode);
    WriteInode: procedure (Ino: Pinode);
    CreateInode: function (Ino: PInode;name: AnsiString): PInode;
    RemoveInode: function (Ino:PInode;name: AnsiString): LongInt;
    LookupInode: function (Ino: PInode;name: AnsiString): PInode;
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
    IO: array[0..5] of UInt32;
    Vendor: UInt32;
    Device: UInt32;
    MainClass: UInt32;
    SubClass: UInt32;
    Next: PBusDevInfo;
 end;
 
// Programmer's Interface
procedure FileSystemInit;
procedure GetDevice(Dev:PBlockDriver);
procedure FreeDevice(Dev:PBlockDriver);
procedure RegisterBlockDriver(Driver:PBlockDriver);
procedure RegisterFilesystem (Driver: PFileSystemDriver);
procedure DedicateBlockDriver(const Name: AnsiString; CPUID: LongInt);
procedure DedicateBlockFile(FBlock: PFileBlock;CPUID: LongInt);
procedure SysCloseFile(FileHandle: THandle);
procedure SysMount(const FileSystemName, BlockName: AnsiString; const Minor: LongInt);
function SysOpenFile(Path: PXChar): THandle;
function SysSeekFile(FileHandle: THandle; Offset, Whence: LongInt): LongInt;
function SysStatFile(Path: PXChar; Buffer: PInode): LongInt;
function SysReadFile(FileHandle: THandle; Count: LongInt;Buffer:Pointer): LongInt;
function SysWriteFile(FileHandle: THandle; Count: LongInt; Buffer:Pointer): LongInt;
function SysWriteBlock(FileHandle: THandle; Block, Count: LongInt; Buffer: Pointer): LongInt;
function SysReadBlock(FileHandle: THandle;Block,Count: LongInt; Buffer: Pointer): LongInt;
function SysOpenBlock (const Name: AnsiString; Minor: LongInt): THandle;
function GetBlock(FileBlock: PFileBlock; Block, Size: LongInt): PBufferHead;
procedure PutBlock(FileBlock: PFileBlock; Bh: PBufferHead);
function GetInode(Inode: LongInt): PInode;
procedure PutInode(Inode: PInode);

var
  PCIDevices: PBusDevInfo; // List of Devices in PCI Bus .
  FileSystemDrivers: PFileSystemDriver; // Filesystem Drivers installed
 
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
  PBios32 = ^TBios32;
  TBios32 = record
    Magic: LongInt;
    phys_entry: LongInt;
    Revision: Byte;
    Length : Byte;
    CRC: XChar;
    Reserved: array [1..5] of Byte;
 end;

// Detect all devices in PCI Buses.
procedure PciDetect;
var
  dev, func, Bus, Vendor, Device, regnum: UInt32;
  DevInfo: PBusDevInfo;
  I, Tmp, btmp: UInt32;
begin
  btmp := 0;
  // this is not the best way to look the PCI devices.
  for Bus := 0 to MAX_PCIBUS-1 do
  begin
    for dev := 0 to MAX_PCIDEV-1 do
    begin
      {$IFDEF DebugArch} WriteDebug('PciDetect - Bus: %d Dev: %d', [Bus, Dev]); {$ENDIF}
      for func := 0 to MAX_PCIFUNC-1 do
      begin
        {$IFDEF DebugArch} WriteDebug('PciDetect - Before PciReadDword Bus: %q dev: %d func: %d', [Bus, dev, func]); {$ENDIF}
        Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_VENDOR);
        {$IFDEF DebugArch} WriteDebug('PciDetect - PciReadDword PCI_CONFIG_VENDOR func: %d Tmp: %h', [Tmp, func]); {$ENDIF}
        Vendor := Tmp and $FFFF;
        Device := Tmp div 65536;
        // some bug
        if func = 0 then
          btmp := Device
        else if Device = btmp then
          Break;
        // the device exists
        if (Vendor = $ffff) or (Vendor = 0) then
          Continue;
        DevInfo := ToroGetMem(SizeOf(TBusDevInfo));
        if DevInfo = nil then
          Exit;
        DevInfo.Device := Device;
        DevInfo.Vendor := Vendor;
        Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_CLASS_REV);
        {$IFDEF DebugArch} WriteDebug('PciDetect - PciReadDword PCI_CONFIG_CLASS_REV func: %d Tmp: %h', [Tmp, func]); {$ENDIF}
        DevInfo.MainClass := Tmp div 16777216;
        DevInfo.SubClass := (Tmp div 65536) and $ff;
        for I := 0 to 5 do
        begin
          regnum := PCI_CONFIG_BASE_ADDR_0+I;
          {$IFDEF DebugArch} WriteDebug('PciDetect - Before PciReadDword Bus: %q dev: %d func: %d', [Bus, dev, func]); {$ENDIF}
          {$IFDEF DebugArch} WriteDebug('PciDetect - Before PciReadDword I: %d', [I]); {$ENDIF}
          Tmp := PciReadDword(Bus, dev, func, regnum);
          {$IFDEF DebugArch} WriteDebug('PciDetect - After PciReadDword Bus: %q dev: %d func: %d', [Bus, dev, func]); {$ENDIF}
          {$IFDEF DebugArch} WriteDebug('PciDetect - PciReadDword PCI_CONFIG_BASE_ADDR_0+%d, Tmp: %h', [Tmp, I]); {$ENDIF}
          if (Tmp and 1) = 1 then
          begin
            DevInfo.IO[I] := Tmp and $FFFFFFFC // IO port
          end else begin
            DevInfo.IO[I] := Tmp; // Memory Address
          end;
        end;
        Tmp := PciReadDword(Bus, dev, func, PCI_CONFIG_INTR);
        {$IFDEF DebugArch} WriteDebug('PciDetect - PciReadDword PCI_CONFIG_INTR, func: %d, Tmp: %h', [Tmp, func]); {$ENDIF}
        DevInfo.irq := Tmp and $ff;
        DevInfo.bus := Bus;
        DevInfo.func := func;
        DevInfo.dev := dev;
        DevInfo.Next := PciDevices; // the device is added
        PciDevices := DevInfo;
      end;
    end;
  end;
end;

// Initialization of structures
procedure PciInit;
//var
// fd: PBios32;
begin
  PciDetect;
{
  fd := Pointer(ADDPCISTART);
  printK_('PCI Driver ...',0);
  while (fd < Pointer($100000)) do
  begin
   if fd.magic=$5F32335F then
   begin
    printK_('/VOk!\n/n',0);
    PciDetect;
    exit;
   end;
  fd :=fd+1;
  end;
  printk_('/RFault\n/n',0);
}
end;

// The driver is enque in Block Drivers tail.
procedure RegisterBlockDriver(Driver: PBlockDriver);
begin
  Driver.Next := BlockDevices;
  BlockDevices := Driver;
  {$IFDEF DebugFS} WriteDebug('RegisterBlockDriver: New Driver\n',[]); {$ENDIF}
end;

// Protect the device of access from LOCAL CPU .
// For access from others CPU, it doesn't need protection because the device is DEDICATE.
procedure GetDevice(Dev: PBlockDriver);
var
  CurrentCPU: PCPU;
begin
  CurrentCPU := @CPU[GetApicID];
  if Dev.Busy then
  begin
    // information for scheduling
    CurrentCPU.CurrentThread.State := tsIOPending;
    CurrentCPU.CurrentThread.IOScheduler.DeviceState:=@Dev.Busy;
    {$IFDEF DebugFS} WriteDebug('GetDevice: Sleeping\n',[]); {$ENDIF}
    SysThreadSwitch;
  end;
  CurrentCPU.CurrentThread.IOScheduler.DeviceState:=nil;
  Dev.Busy := True;
  Dev.WaitOn := CurrentCPU.CurrentThread;
  {$IFDEF DebugFS} WriteDebug('GetDevice: Device in use\n',[]); {$ENDIF}
end;

// Free the use of device.
procedure FreeDevice(Dev: PBlockDriver);
begin
  Dev.Busy := False;
  Dev.WaitOn:= nil;
  {$IFDEF DebugFS} WriteDebug('FreeDevice: Device is Free\n', []); {$ENDIF}
end;

// Only called by Driver. Creates a Block file's descriptors in CPUID.
procedure DedicateBlockFile(FBlock: PFileBlock;CPUID: LongInt);
var
  Storage: PStorage;
begin
  Storage := @Storages[CPUID];
  FBlock.Next := Storage.BlockFiles;
  Storage.BlockFiles := FBlock;
  // cleaning Buffer Cache slot
  FBlock.BufferCache.BuffersInCache := MAX_BUFFERS_IN_CACHE;
  FBlock.BufferCache.BlockCache := nil;
  FBlock.BufferCache.FreeBlocksCache := nil;
  {$IFDEF DebugFS} WriteDebug('DedicateBlockFile: New Block File Descriptor on CPU#%d , Minor: %d\n', [CPUID, FBlock.Minor]); {$ENDIF}
end;

// Return a Pointer to Block file's descriptor .
function SysOpenBlock(const Name: AnsiString; Minor: LongInt): THandle;
var
  Storage: PStorage;
  FileBlock: PFileBlock;
begin
  Storage := @Storages[GetApicID];
  FileBlock := Storage.BlockFiles;
  while (FileBlock <> nil) do
  begin
    if (FileBlock.BlockDriver.Name = Name) and (FileBlock.Minor=Minor) then
    begin
      Result := Thandle(FileBlock);
      {$IFDEF DebugFS} WriteDebug('SysOpenBlock: Handle %q\n',[Int64(result)]); {$ENDIF}
      Exit;
    end;
    FileBlock:=FileBlock.Next;
  end;
  Result := 0;
  {$IFDEF DebugFS} WriteDebug('SysOpenBlock: Fail , Minor: %d\n', [Minor]); {$ENDIF}
end;

// Dedicate the Driver to CPU in CPUID variable.
procedure DedicateBlockDriver(const Name: AnsiString; CPUID: LongInt);
var
  Dev: PBlockDriver;
begin
  Dev := BlockDevices;
  while Dev <> nil do
  begin
    if (Dev.Name = Name) and (Dev.CPUID = -1) then
    begin
      Dev.Dedicate(Dev, CPUID);
      Dev.CPUID := CPUID;
      {$IFDEF DebugFS} WriteDebug('DedicateBlockDriver: New Driver dedicated to CPU#%d\n', [CPUID]); {$ENDIF}
      Exit;
    end;
    Dev := Dev.Next;
  end;
  {$IFDEF DebugFS} WriteDebug('DedicateBlockDriver: Driver does not exist\n',[]); {$ENDIF}
end;

// Write operation to Block Device.
function SysWriteBlock(FileHandle: THandle; Block, Count: LongInt; Buffer: Pointer): LongInt;
var 
  FileBlock: PFileBlock;
begin
  FileBlock := PFileBlock(FileHandle);
  Result := FileBlock.BlockDriver.WriteBlock(FileBlock,Block,Count,Buffer);
  {$IFDEF DebugFS} WriteDebug('SysWriteBlock: Handle %q, Result: %d', [Int64(FileHandle), Result]); {$ENDIF}
end;

// Read Operation to Block Device
function SysReadBlock(FileHandle: THandle; Block, Count: LongInt; Buffer: Pointer): LongInt;
var
  FileBlock: PFileBlock;
begin
  FileBlock := PFileBlock(FileHandle);
  Result := FileBlock.BlockDriver.ReadBlock(FileBlock,Block,Count,Buffer);
  {$IFDEF DebugFS} WriteDebug('SysReadBlock: Handle %q, Result: %d', [Int64(FileHandle), Result]); {$ENDIF}
end;

function FindBlock(Buffer: PBufferHead; Block, Size: LongInt): PBufferHead;
var
  Bhd: PBufferHead;
begin
  Result := nil;
  if Buffer = nil then
    Exit;
  Bhd := Buffer;
  repeat
    if (Buffer.Block = Block) and (Buffer.Size = Size) then
    begin
      Result := Buffer;
      Exit;
    end;
    Buffer := Buffer.Next;
  until Buffer = Bhd;
end;

procedure AddBuffer(var Queue: PBufferHead; bh: PBufferHead);
begin
  if Queue = nil then
  begin
    Queue := bh;
    bh.Next := bh;
    bh.Prev := bh;
    Exit;
  end;
  bh.Prev := Queue.Prev;
  bh.Next := Queue;
  Queue.Prev.Next := bh;
  Queue.Prev := bh;
end;

procedure RemoveBuffer(var Queue: PBufferHead; bh: PBufferHead);
begin
  if (Queue = bh) and (Queue.Next = Queue) then
  begin
    Queue:= nil;
    bh.Next:= nil;
    bh.Prev:= nil;
    Exit;
  end;
  if Queue = bh then
    Queue := bh.Next;
  bh.Prev.Next := bh.Next;
  bh.Next.Prev := bh.Prev;
  bh.Next := nil;
  bh.Prev := nil;
end;

// Return a block from Buffer Cache in FileBlock.
function GetBlock(FileBlock: PFileBlock; Block, Size: LongInt): PBufferHead;
var
  bh: PBufferHead;
begin
  // Buffers in use
  bh := FindBlock(FileBlock.BufferCache.BlockCache, Block, Size);
  if bh <> nil then
  begin
    bh.Count := bh.Count+1;
    Result := bh;
    {$IFDEF DebugFS} WriteDebug('GetBlock: Block: %d , Size: %d, In use\n', [Block, Size]); {$ENDIF}
    Exit;
  end;
  // Free Buffers.
  bh := FindBlock(FileBlock.BufferCache.FreeBlocksCache, Block, Size);
  if bh <> nil then
  begin
    RemoveBuffer(FileBlock.BufferCache.FreeBlocksCache, bh);
    AddBuffer(FileBlock.BufferCache.BlockCache, bh);
    bh.Count := 1;
    Result := bh;
    {$IFDEF DebugFS} WriteDebug('GetBlock: Block: %d , Size: %d, In Free Block\n', [Block, Size]); {$ENDIF}
    Exit;
  end;
  if FileBlock.BufferCache.BuffersInCache=0 then
  begin
    bh := FileBlock.BufferCache.FreeBlocksCache;
    if bh = nil then
    begin
      Result := nil;
      Exit;
    end;
    // last Block in Cache
    bh := bh.Prev;
    if FileBlock.BlockDriver.ReadBlock(FileBlock, Block*(bh.size div FileBlock.BlockSize), bh.size div FileBlock.BlockSize, bh.data) = 0 then
    begin
      Result:=nil;
      Exit;
    end;
    bh.Count := 1;
    bh.Block := block;
    bh.Dirty := False;
    RemoveBuffer(FileBlock.BufferCache.FreeBlocksCache,bh);
    AddBuffer(FileBlock.BufferCache.BlockCache,bh);
    Result := bh;
    Exit;
  end;
  bh := ToroGetMem(SizeOf(TBufferHead));
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
  bh.Count:= 1;
  bh.size:= Size;
  bh.Dirty:= False;
  bh.Block:= Block;
  if FileBlock.BlockDriver.ReadBlock(FileBlock, Block*(bh.size div FileBlock.BlockSize), Size div FileBlock.BlockSize, bh.data) = 0 then
  begin
    ToroFreeMem(bh.data);
    ToroFreeMem(bh);
    Result := nil;
    Exit;
  end;
  AddBuffer(FileBlock.BufferCache.BlockCache,bh);
  FileBlock.BufferCache.BuffersInCache := FileBlock.BufferCache.BuffersInCache -1;
  Result := bh;
  {$IFDEF DebugFS} WriteDebug('GetBlock: Block: %d , Size: %d, New in Buffer\n', [Block, Size]); {$ENDIF}
end;

// Return a block to Buffer Cache in FileBlock descriptor
procedure PutBlock(FileBlock: PFileBlock; Bh: PBufferHead);
begin
  Bh.Count := Bh.Count-1;
  if Bh.Count = 0 then
  begin
    if Bh.Dirty then
      FileBlock.BlockDriver.WriteBlock(FileBlock, bh.Block, 1, bh.data); // TODO: Test write operations
    Bh.Dirty := False;
    RemoveBuffer(FileBlock.BufferCache.BlockCache, bh);
    AddBuffer(FileBlock.BufferCache.FreeBlocksCache, bh);
  end;
end;

function FindInode(Buffer: PInode;Inode: LongInt): PInode;
var
  Inohd: PInode;
begin
  Result := nil;
  if Buffer = nil then
    Exit;
  Inohd := Buffer;
  repeat
    if Buffer.Ino = Inode then
    begin
      Result := Buffer;
      Exit;
    end;
    Buffer := Buffer.Next;
  until Buffer = Inohd;
end;

procedure AddInode(var Queue: PInode;Inode: PInode);
begin
  if Queue = nil then
  begin
    Queue := Inode;
    Inode.Next := Inode;
    Inode.Prev := InoDE;
    Exit;
  end;
  Inode.Prev := Queue.Prev;
  Inode.Next := Queue;
  Queue.Prev.Next := Inode;
  Queue.Prev := Inode;
end;

procedure RemoveInode(var Queue: PInode;Inode: PInode);
begin
  if (Queue = Inode) and (Queue.Next = Queue) then
  begin
    Queue:= nil;
    Inode.Next:= nil;
    Inode.Prev:= nil;
    Exit;
  end;
  if Queue = Inode then
    Inode := Inode.Next;
  Inode.Prev.Next:= Inode.Next;
  Inode.Next.Prev:= Inode.Prev;
  Inode.Next:= nil;
  Inode.Prev:= nil;
end;

// Return a Inode from Inode-Cache of Local FileSystem Mounted
function GetInode(Inode: LongInt): PInode;
var
  Storage: PStorage;
  Ino: PInode;
begin
  Storage := @Storages[GetApicID];
  // Is the Inode in Use?
  Ino := FindInode(Storage.FileSystemMounted.InodeCache.InodeBuffer,Inode);
  if Ino <> nil then
  begin
    Ino.Count := Ino.Count+1;
    Result := Ino;
    {$IFDEF DebugFS} WriteDebug('GetInode: Inode: %d In Inode-Cache\n', [Ino.ino]); {$ENDIF}
    Exit;
  end;
  // Is the Inode in Free Tail?
  Ino := FindInode(Storage.FilesystemMounted.InodeCache.FreeInodesCache, Inode);
  if Ino <> nil then
  begin
    RemoveInode(Storage.FilesystemMounted.InodeCache.FreeInodesCache, Ino);
    AddInode(Storage.FilesystemMounted.InodeCache.InodeBuffer, Ino);
    Result := Ino;
    Ino.Count := 1;
    {$IFDEF DebugFS} WriteDebug('GetInode: Inode: %d In Inode-Cache\n', [Ino.ino]); {$ENDIF}
    Exit;
  end;
  // Can i alloc memory for new Inode?
  if Storage.FilesystemMounted.InodeCache.InodesInCache=0 then
  begin
    Ino := Storage.FilesystemMounted.InodeCache.FreeInodesCache;
    // the buffer is completed
    if Ino = nil then
    begin
      Result := nil;
      {$IFDEF DebugFS} WriteDebug('GetInode: Inode Cache is Busy!\n', []); {$ENDIF}
      Exit;
    end;
    // Is a LRU Tail
    Ino := Ino.Prev;
    Ino.ino:= Inode;
    Ino.Dirty:= False;
    Ino.SuperBlock := Storage.FileSystemMounted;
    Ino.SuperBlock.FileSystemDriver.ReadInode(Ino);
    // Error in read operations
    if Ino.Dirty then
    begin
      Result := nil;
      {$IFDEF DebugFS} WriteDebug('GetInode: Error reading Inode: %d\n', [Inode]); {$ENDIF}
      Exit;
    end;
    Result := Ino;
    // add inode to  List of Inode in Use
    RemoveInode(Storage.FilesystemMounted.InodeCache.FreeInodesCache,Ino);
    AddInode(Storage.FilesystemMounted.InodeCache.InodeBuffer,Ino);
    {$IFDEF DebugFS} WriteDebug('GetInode: Inode: %d In Inode-Cache\n', [Ino.ino]); {$ENDIF}
    Exit;
  end;
  // I can alloc more memory to Inode-Cache
  Ino := ToroGetMem(SizeOf(TInode));
  if Ino = nil then
  begin
    Result := nil;
    Exit;
  end;
  Ino.ino := Inode;
  Ino.Dirty := False;
  Ino.Count := 1;
  Ino.SuperBlock := Storage.FileSystemMounted;
  Storage.FileSystemMounted.FileSystemDriver.ReadInode(Ino);
  if Ino.Dirty then
  begin
    ToroFreeMem(Ino);
    Result := nil;
    {$IFDEF DebugFS} WriteDebug('GetInode: Error reading Inode: %d\n', [Inode]); {$ENDIF}
    Exit;
  end;
  AddInode(Storage.FilesystemMounted.InodeCache.InodeBuffer, Ino);
  Storage.FilesystemMounted.InodeCache.InodesInCache := Storage.FilesystemMounted.InodeCache.InodesInCache-1;
  Result:= Ino;
  {$IFDEF DebugFS} WriteDebug('GetInode: Inode: %d In Inode-Cache\n', [Ino.ino]); {$ENDIF}
end;

// Returns a Inode to Inode-Cache
procedure PutInode(Inode: PInode);
begin
  Inode.Count := Inode.Count-1;
  if Inode.Count > 0 then
    Exit;
 // Inode is moved to Free Inode cache
  if Inode.Dirty then
    Inode.SuperBlock.FileSystemDriver.WriteInode(Inode);
  // here , if dirty=True then error in write operations
  RemoveInode(Inode.SuperBlock.InodeCache.InodeBuffer,Inode);
  AddInode(Inode.SuperBlock.InodeCache.FreeInodesCache,Inode);
  {$IFDEF DebugFS} WriteDebug('PutInode: Inode %d return to Inode-LRU Cache\n', [Inode.ino]); {$ENDIF}
end;

// Register a FileSystem Driver.
procedure RegisterFilesystem (Driver: PFileSystemDriver);
begin
  Driver.Next := FileSystemDrivers;
  FileSystemDrivers := Driver;
  {$IFDEF DebugFS} WriteDebug('RegisterFilesystem: New Driver\n', []); {$ENDIF}
end;

function FindFileSystemDriver(Storage: PStorage; const FileSystemName, BlockName: AnsiString; const Minor: LongInt; var FileBlock: PFileBlock): PFileSystemDriver;
begin
  Result := nil;
  FileBlock := Storage.BlockFiles;
  // Is the Device valid?
  while FileBlock <> nil do
  begin
    if (FileBlock.BlockDriver.Name = BlockName) and (FileBlock.Minor = Minor) then
    begin
      Result := FileSystemDrivers;
      // Is the FileSystem valid?
      while Result <> nil do
      begin
        if Result.Name = FileSystemName then
          Exit;
        Result := Result.Next;
      end;
    end;
    FileBlock := FileBlock.Next;
  end;
end;

// Mount on current CPU the Filesystem, allocated in BlockName\Minor Device.
procedure SysMount(const FileSystemName, BlockName: AnsiString; const Minor: LongInt);
var
  FileBlock: PFileBlock;
  FileSystem: PFileSystemDriver;
  Storage: PStorage;
  SuperBlock: PSuperBlock;
begin
  Storage := @Storages[GetApicID];
  FileSystem := FindFileSystemDriver(Storage, FileSystemName, BlockName, Minor, FileBlock);
  if FileSystem = nil then
  begin
    WriteConsole('CPU#%d: SysMount Failed, unknown filesystem!\n', [GetApicID]);
    {$IFDEF DebugFS} WriteDebug('CPU#%d: Mounting FileSystem -> Failed\n', [GetApicID]); {$ENDIF}
  Exit;
  end;
  SuperBlock:= ToroGetMem(SizeOf(TSuperBlock));
  if SuperBlock = nil then
  begin // not enough memory
    {$IFDEF DebugFS} WriteDebug('SysMount: Mounting Root Filesystem, SuperBlock=nil -> Failed\n', []); {$ENDIF}
     WriteConsole('SysMount: Mounting Root Filesystem, SuperBlock=nil -> Failed\n', []);
    Exit;
  end;
  SuperBlock.BlockDevice := FileBlock;
  SuperBlock.FileSystemDriver := FileSystem;
  SuperBlock.Dirty:= False;
  SuperBlock.Flags:= 0;
  // Inode-Buffer Initialization
  SuperBlock.InodeCache.InodesInCache:=  MAX_INODES_IN_CACHE;
  SuperBlock.InodeCache.InodeBuffer:= nil;
  SuperBlock.InodeCache. FreeInodesCache:= nil;
  // error in read operations
  Storage.FileSystemMounted:= SuperBlock;
  if FileSystem.ReadSuper(SuperBlock) = nil then
  begin
    WriteConsole('CPU#%d: Fail Reading SuperBlock\n', [GetApicID]);
    ToroFreeMem(SuperBlock);
    Storage.FileSystemMounted := nil;
    {$IFDEF DebugFS} WriteDebug('SysMount: Mounting Root Filesystem, Cannot read SuperBlock -> Failed\n', []); {$ENDIF}
    Exit;
  end;
  {$IFDEF DebugFS} WriteDebug('SysMount: Mounting Root Filesystem -> Ok\n', []); {$ENDIF}
  WriteConsole('SysMount: Filesystem /Vmounted/n on CPU#%d\n', [GetApicID]);
end;

// Return the last Inode of path
function NameI(Path:  PAnsiChar): PInode;
var 
  Base: PInode;
  Count: LongInt;
  Name: AnsiString;
  ino: PInode;
begin
  Base := Storages[GetApicID].FileSystemMounted.InodeROOT;
  Base.Count := Base.Count+1;
  Path := Path+1;
  Count := 1;
  Result := nil;
  SetLength(Name, 0);
  while PtrUint(Path^) <> 0 do
  begin
    if PtrUint(Path^) = 12 then
    begin
      // only inode dir please!
      if Base.Mode= INODE_DIR then
        ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, Name)
      else
      begin
        PutInode(Base);
        Exit;
      end;
      PutInode(Base);
      // error in operation
      if ino = nil then
        Exit;
      SetLength(Name, 0);
      Base := ino;
      Path := Path+1;
      count := 1;
    end else begin
      SetLength(Name, Length(Name)+1);
      Name[count] := Path^;
      Inc(Count);
      Inc(Path);
    end;
  end;
  if Name[count] = '/' then
  begin
    Result := Base;
    Exit;
  end;
  ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, Name);
  PutInode(Base);
  Result := ino;
end;

function SysOpenFile(Path: PXChar): THandle;
var
  FileRegular: PFileRegular;
  Ino: PInode;
begin
  FileRegular := ToroGetMem(SizeOf(TFileRegular));
  Result := 0;
  // we don't have memory!
  if FileRegular=nil then
    Exit;
  {$IFDEF DebugFS} WriteDebug('SysOpenFile: opening path: %p\n', [PtrUInt(Path)]); {$ENDIF}
  Ino:= NameI(Path);
  // looking for the inode from the path
  if Ino=nil then
  begin
    ToroFreeMem(FileRegular);
    {$IFDEF DebugFS} WriteDebug('SysOpenFile: File not found\n', []); {$ENDIF}
    Exit;
  end;
  FileRegular.FilePos := 0;
  FileRegular.Inode := Ino;
  // the descriptor is not enque in the tail , i don't need this
  Result := THandle(FileRegular);
  {$IFDEF DebugFS} WriteDebug('SysOpenFile: File Openned\n', []); {$ENDIF}
end;

// Changes position of the File. I don't need the FileSystem Driver here.
function SysSeekFile(FileHandle: THandle; Offset, Whence: LongInt): LongInt;
var
  FileRegular: PFileRegular;
begin
  FileRegular := PFileRegular(FileHandle);
  if FileRegular.Inode.Mode = INODE_DIR then
  begin
    Result := 0;
    Exit;
  end else if Whence = SeekSet then
    FileRegular.FilePos:= Offset
  else if Whence = SeekCur then
    FileRegular.FilePos := FileRegular.FilePos+Offset
  else if Whence = SeekEof then
    FileRegular.FilePos := FileRegular.Inode.Size;
  Result := FileRegular.FilePos;
end;

// Read from Regular File
function SysReadFile(FileHandle: THandle; Count: LongInt; Buffer: Pointer): LongInt;
var
  FileRegular: PFileRegular;
begin
  FileRegular:= PFileRegular(FileHandle);
  if FileRegular.Inode.Mode = INODE_DIR then
    Result:=0
  else
    Result:= FileRegular.Inode.SuperBlock.FileSystemDriver.ReadFile(FileRegular, Count, Buffer);
  FileRegular.FilePos := FileRegular.FilePos + result;
  {$IFDEF DebugFS} WriteDebug('SysReadFile: %d bytes read, FilePos: %d\n', [Result, FileRegular.FilePos]); {$ENDIF}
end;

// Return Inode Information about last file in the path
function SysStatFile(Path: PXChar; Buffer: PInode): LongInt;
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

// Write to Regular File
function SysWriteFile(FileHandle: THandle; Count: LongInt; Buffer: Pointer): LongInt;
var
  FileRegular: PFileRegular;
begin
  FileRegular := PFileRegular(FileHandle);
  if FileRegular.Inode.Mode = INODE_DIR then
    Result := 0
  else
    Result := FileRegular.Inode.SuperBlock.FileSystemDriver.WriteFile(FileRegular, Count, Buffer);
  FileRegular.FilePos := FileRegular.FilePos + Result;
  {$IFDEF DebugFS} WriteDebug('SysWriteFile: %d bytes written, FilePos: %d\n', [Result, FileRegular.FilePos]); {$ENDIF}
end;

// Close regular File , very simple only return the inode and free memory
procedure SysCloseFile(FileHandle: THandle);
var
  FileRegular: PFileRegular;
begin
  FileRegular := PFileRegular(FileHandle);
  PutInode(FileRegular.inode);
  ToroFreeMem(FileRegular);
end;

// Initialization of Virtual FileSystem's structures.
procedure FileSystemInit;
var
  I: LongInt;
begin
  WriteConsole('Loading Virtual FileSystem ...\n',[]);
  for I := 0 to MAX_CPU-1 do
  begin
    Storages[I].BlockFiles := nil;
    Storages[I].FileSystemMounted := nil;
  end;
  BlockDevices := nil;
  FileSystemDrivers := nil;
  PCIDevices := nil;
  PciInit;
end;

end.
