//
// FileSystem.pas
//
// This unit contains the virtual filesystem.
//
// Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
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
unit FileSystem;

interface

{$I Toro.inc}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Process, Console, Memory;

const
  MAX_BUFFERS_IN_CACHE = 5000;
  MAX_INODES_IN_CACHE= 300;

  INODE_DIR = 1;
  INODE_REG = 2;

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

  TBlockDriver = record
    Busy: Boolean; // protection for access from Local CPU.
    WaitOn: PThread; // Thread using the Driver.
    Name: AnsiString; // Driver identificators is used by the Kernel
    Major: LongInt;
    Dedicate: procedure (Controller:PBlockDriver;CPUID: LongInt);
    WriteBlock: function (FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
    ReadBlock: function (FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
    CPUID: LongInt;
    Next: PBlockDriver;
  end;

  TBufferCacheSlot = record
    BuffersInCache: Int64;
    BlockCache: PBufferHead;
    FreeBlocksCache: PBufferHead;
  end;

  TFileBlock = record
    BlockDriver:PBlockDriver;
    BlockSize: LongInt;
    BufferCache: TBufferCacheSlot;
    Minor: LongInt;
    Next: PFileBlock;
  end;

  TBufferHead = record
    Block: LongInt ;
    size:  LongInt;
    Count: int64;
    Dirty: Boolean;
    data: Pointer;
    next: PBufferHead;
    Prev: PBufferHead;
  end;

  TFileRegular = record
    FilePos: LongInt;
    Inode: PInode;
  end;

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

  TInodeCacheSlot= record
    InodesInCache: Int64;
    InodeBuffer: PInode;
    FreeInodesCache: PInode;
  end;

  TSuperBlock = record
    BlockDevice: PFileBlock;
    InodeROOT: PInode;
    Dirty: Boolean;
    Flags: LongInt;
    BlockSize: LongInt;
    SbInfo: Pointer;
    FileSystemDriver: PFilesystemDriver;
    InodeCache: TInodeCacheSlot;
  end;

  TFileSystemDriver = record
    Name: AnsiString; // e.g., ext2, fat, etc
    ReadFile: function (FileDesc: PFileRegular;count: LongInt;Buffer: Pointer): LongInt;
    WriteFile: function (FileDesc: PFileRegular;count: LongInt;Buffer: Pointer): LongInt;
    ReadInode: procedure (Ino: PInode);
    WriteInode: procedure (Ino: Pinode);
    CreateInode: function (Ino: PInode;name: AnsiString): PInode;
    CreateInodeDir: function (Ino: PInode;name: AnsiString): PInode;
    RemoveInode: function (Ino:PInode;name: AnsiString): LongInt;
    LookupInode: function (Ino: PInode;name: AnsiString): PInode;
    ReadSuper: function (Spb: PSuperBlock): PSuperBlock;
    Next: PFileSystemDriver;
  end;

  TStorage = record
    BlockFiles : PFileBlock; // Block File Descriptors
    RegularFiles: PFileBlock; // Regular File Decriptors
    FileSystemMounted: PSuperBlock; // ??? Not sure about it ???
  end;

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
function SysCreateDir(Path: PAnsiChar): Longint;
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
procedure WriteBlock(FileBlock: PFileBlock; Bh: PBufferHead);
function SysCreateFile(Path:  PAnsiChar): THandle;

var
  FileSystemDrivers: PFileSystemDriver;

implementation

var
  Storages: array [0..MAX_CPU-1] of TStorage; // Dedicated Storage
  BlockDevices: PBlockDriver; // Block Drivers installed

procedure RegisterBlockDriver(Driver: PBlockDriver);
begin
  Driver.Next := BlockDevices;
  BlockDevices := Driver;
  {$IFDEF DebugFS} WriteDebug('RegisterBlockDriver: New Driver\n',[]); {$ENDIF}
end;

procedure GetDevice(Dev: PBlockDriver);
var
  CurrentCPU: PCPU;
begin
  CurrentCPU := @CPU[GetApicID];
  if Dev.Busy then
  begin
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

procedure FreeDevice(Dev: PBlockDriver);
begin
  Dev.Busy := False;
  Dev.WaitOn := nil;
  {$IFDEF DebugFS} WriteDebug('FreeDevice: Device is Free\n', []); {$ENDIF}
end;

procedure DedicateBlockFile(FBlock: PFileBlock; CPUID: LongInt);
var
  Storage: PStorage;
begin
  Storage := @Storages[CPUID];
  FBlock.Next := Storage.BlockFiles;
  Storage.BlockFiles := FBlock;
  FBlock.BufferCache.BuffersInCache := MAX_BUFFERS_IN_CACHE;
  FBlock.BufferCache.BlockCache := nil;
  FBlock.BufferCache.FreeBlocksCache := nil;
  {$IFDEF DebugFS} WriteDebug('DedicateBlockFile: New Block File Descriptor on CPU#%d , Minor: %d\n', [CPUID, FBlock.Minor]); {$ENDIF}
end;

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

function SysWriteBlock(FileHandle: THandle; Block, Count: LongInt; Buffer: Pointer): LongInt;
var
  FileBlock: PFileBlock;
begin
  FileBlock := PFileBlock(FileHandle);
  Result := FileBlock.BlockDriver.WriteBlock(FileBlock,Block,Count,Buffer);
  {$IFDEF DebugFS} WriteDebug('SysWriteBlock: Handle %q, Result: %d', [Int64(FileHandle), Result]); {$ENDIF}
end;

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
    Queue := nil;
    bh.Next := nil;
    bh.Prev := nil;
    Exit;
  end;
  if Queue = bh then
    Queue := bh.Next;
  bh.Prev.Next := bh.Next;
  bh.Next.Prev := bh.Prev;
  bh.Next := nil;
  bh.Prev := nil;
end;

function GetBlock(FileBlock: PFileBlock; Block, Size: LongInt): PBufferHead;
var
  bh: PBufferHead;
begin
  bh := FindBlock(FileBlock.BufferCache.BlockCache, Block, Size);
  Result := nil;
  if bh <> nil then
  begin
    Inc(bh.Count);
    Result := bh;
    {$IFDEF DebugFS} WriteDebug('GetBlock: Block: %d , Size: %d, In use\n', [Block, Size]); {$ENDIF}
    Exit;
  end;
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
      Exit;
    end;
    bh := bh.Prev;
    if FileBlock.BlockDriver.ReadBlock(FileBlock, Block*(bh.size div FileBlock.BlockSize), bh.size div FileBlock.BlockSize, bh.data) = 0 then
    begin
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
    Exit;
  end;
  bh.data := ToroGetMem(Size);
  if bh.data = nil then
  begin
    ToroFreeMem(bh);
    Exit;
  end;
  bh.Count := 1;
  bh.size := Size;
  bh.Dirty := False;
  bh.Block := Block;
  if FileBlock.BlockDriver.ReadBlock(FileBlock, Block *(bh.size div FileBlock.BlockSize), Size div FileBlock.BlockSize, bh.data) = 0 then
  begin
    ToroFreeMem(bh.data);
    ToroFreeMem(bh);
    Exit;
  end;
  AddBuffer(FileBlock.BufferCache.BlockCache,bh);
  Dec(FileBlock.BufferCache.BuffersInCache);
  Result := bh;
  {$IFDEF DebugFS} WriteDebug('GetBlock: Block: %d , Size: %d, New in Buffer\n', [Block, Size]); {$ENDIF}
end;

procedure PutBlock(FileBlock: PFileBlock; Bh: PBufferHead);
begin
  Dec(Bh.Count);
  if Bh.Count = 0 then
  begin
    if Bh.Dirty then
    begin
      FileBlock.BlockDriver.WriteBlock(FileBlock, bh.Block *(bh.size div FileBlock.BlockSize), bh.size div FileBlock.BlockSize, bh.data);
      {$IFDEF DebugFS} WriteDebug('PutBlock: Writing Block: %d\n', [Bh.Block]); {$ENDIF}
    end;
    Bh.Dirty := False;
    RemoveBuffer(FileBlock.BufferCache.BlockCache, bh);
    AddBuffer(FileBlock.BufferCache.FreeBlocksCache, bh);
  end;
  {$IFDEF DebugFS} WriteDebug('PutBlock: Block: %d\n', [Bh.Block]); {$ENDIF}
end;

procedure WriteBlock(FileBlock: PFileBlock; Bh: PBufferHead);
begin
  FileBlock.BlockDriver.WriteBlock(FileBlock, bh.Block *(bh.size div FileBlock.BlockSize), bh.size div FileBlock.BlockSize, bh.data);
  Bh.Dirty:= False;
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
    Inode.Prev := Inode;
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
    Queue := nil;
    Inode.Next := nil;
    Inode.Prev := nil;
    Exit;
  end;
  if Queue = Inode then
    Inode := Inode.Next;
  Inode.Prev.Next := Inode.Next;
  Inode.Next.Prev := Inode.Prev;
  Inode.Next:= nil;
  Inode.Prev:= nil;
end;

function GetInode(Inode: LongInt): PInode;
var
  Storage: PStorage;
  Ino: PInode;
begin
  Storage := @Storages[GetApicID];
  Ino := FindInode(Storage.FileSystemMounted.InodeCache.InodeBuffer,Inode);
  if Ino <> nil then
  begin
    Inc(Ino.Count);
    Result := Ino;
    {$IFDEF DebugFS} WriteDebug('GetInode: Inode: %d In Inode-Cache\n', [Ino.ino]); {$ENDIF}
    Exit;
  end;
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
  if Storage.FilesystemMounted.InodeCache.InodesInCache=0 then
  begin
    Ino := Storage.FilesystemMounted.InodeCache.FreeInodesCache;
    if Ino = nil then
    begin
      Result := nil;
      {$IFDEF DebugFS} WriteDebug('GetInode: Inode Cache is Busy!\n', []); {$ENDIF}
      Exit;
    end;
    Ino := Ino.Prev;
    Ino.ino := Inode;
    Ino.Dirty := False;
    Ino.SuperBlock := Storage.FileSystemMounted;
    Ino.SuperBlock.FileSystemDriver.ReadInode(Ino);
    if Ino.Dirty then
    begin
      Result := nil;
      {$IFDEF DebugFS} WriteDebug('GetInode: Error reading Inode: %d\n', [Inode]); {$ENDIF}
      Exit;
    end;
    Result := Ino;
    RemoveInode(Storage.FilesystemMounted.InodeCache.FreeInodesCache,Ino);
    AddInode(Storage.FilesystemMounted.InodeCache.InodeBuffer,Ino);
    {$IFDEF DebugFS} WriteDebug('GetInode: Inode: %d In Inode-Cache\n', [Ino.ino]); {$ENDIF}
    Exit;
  end;
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
  Dec(Storage.FilesystemMounted.InodeCache.InodesInCache);
  Result:= Ino;
  {$IFDEF DebugFS} WriteDebug('GetInode: Inode: %d In Inode-Cache\n', [Ino.ino]); {$ENDIF}
end;

procedure PutInode(Inode: PInode);
begin
  Dec(Inode.Count);
  if Inode.Count > 0 then
    Exit;
  if Inode.Dirty then
    Inode.SuperBlock.FileSystemDriver.WriteInode(Inode);
  RemoveInode(Inode.SuperBlock.InodeCache.InodeBuffer,Inode);
  AddInode(Inode.SuperBlock.InodeCache.FreeInodesCache,Inode);
  {$IFDEF DebugFS} WriteDebug('PutInode: Inode %d return to Inode-LRU Cache\n', [Inode.ino]); {$ENDIF}
end;

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
  while FileBlock <> nil do
  begin
    if (FileBlock.BlockDriver.Name = BlockName) and (FileBlock.Minor = Minor) then
    begin
      Result := FileSystemDrivers;
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
    WriteConsoleF('CPU#%d: SysMount Failed, unknown filesystem!\n', [GetApicID]);
    {$IFDEF DebugFS} WriteDebug('CPU#%d: Mounting FileSystem -> Failed\n', [GetApicID]); {$ENDIF}
  Exit;
  end;
  SuperBlock := ToroGetMem(SizeOf(TSuperBlock));
  if SuperBlock = nil then
  begin
    {$IFDEF DebugFS} WriteDebug('SysMount: Mounting Root Filesystem, SuperBlock=nil -> Failed\n', []); {$ENDIF}
     WriteConsoleF('SysMount: Mounting Root Filesystem, SuperBlock=nil -> Failed\n', []);
    Exit;
  end;
  SuperBlock.BlockDevice := FileBlock;
  SuperBlock.FileSystemDriver := FileSystem;
  SuperBlock.Dirty := False;
  SuperBlock.Flags := 0;
  SuperBlock.InodeCache.InodesInCache :=  MAX_INODES_IN_CACHE;
  SuperBlock.InodeCache.InodeBuffer := nil;
  SuperBlock.InodeCache. FreeInodesCache := nil;
  Storage.FileSystemMounted := SuperBlock;
  if FileSystem.ReadSuper(SuperBlock) = nil then
  begin
    WriteConsoleF('CPU#%d: Fail Reading SuperBlock\n', [GetApicID]);
    ToroFreeMem(SuperBlock);
    Storage.FileSystemMounted := nil;
    {$IFDEF DebugFS} WriteDebug('SysMount: Mounting Root Filesystem, Cannot read SuperBlock -> Failed\n', []); {$ENDIF}
    Exit;
  end;
  {$IFDEF DebugFS} WriteDebug('SysMount: Mounting Root Filesystem -> Ok\n', []); {$ENDIF}
  WriteConsoleF('SysMount: Filesystem /Vmounted/n on CPU#%d\n', [GetApicID]);
end;

function NameI(Path:  PAnsiChar): PInode;
var
  Base: PInode;
  Count: LongInt;
  Name: String;
  ino: PInode;
begin
  Base := Storages[GetApicID].FileSystemMounted.InodeROOT;
  Inc(Base.Count);
  Inc(Path);
  Count := 1;
  Result := nil;
  SetLength(Name, 0);
  while PtrUint(Path^) <> 0 do
  begin
    // ascii code of '/'
    if PtrUint(Path^) = 47 then
    begin
      if Base.Mode= INODE_DIR then
        ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, Name)
      else
      begin
        PutInode(Base);
        Exit;
      end;
      PutInode(Base);
      if ino = nil then
        Exit;
      SetLength(Name, 0);
      Base := ino;
      Inc(Path);
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

function SysCreateDir(Path: PAnsiChar): Longint;
var
  Base: PInode;
  Count: LongInt;
  Name: String;
  ino: PInode;
  {$IFDEF DebugFS}SPath: PChar;{$ENDIF}
begin
  Base := Storages[GetApicID].FileSystemMounted.InodeROOT;
  Inc(Base.Count);
  Inc(Path);
  Count := 1;
  Result := 0;
  SetLength(Name, 0);
  {$IFDEF DebugFS}
    SPath := Path;
    WriteDebug('SysCreateDir: creating directoy %p\n', [PtrUInt(SPath)]);
  {$ENDIF}
  while PtrUint(Path^) <> 0 do
  begin
    // ascii code of '/'
    if PtrUint(Path^) = 47 then
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
      if ino = nil then
        Exit;
      SetLength(Name, 0);
      Base := ino;
      Inc(Path);
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
    Name[count] := #0;
    SetLength(Name, Length(Name)-1);
  end;
  ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, Name);
  if (ino <> nil) then
  begin
      {$IFDEF DebugFS} WriteDebug('SysCreateDir: dir %p exists, exiting\n', [PtrUInt(SPath)]); {$ENDIF}
      PutInode(Base);
      Exit;
  end;
  ino := Base.SuperBlock.FileSystemDriver.CreateInodeDir(Base, Name);
  if (ino = nil) then
  begin
     {$IFDEF DebugFS} WriteDebug('SysCreateDir: creating %p failed\n', [PtrUInt(SPath)]); {$ENDIF}
      PutInode(Base);
  end else
  begin
    PutInode(ino);
    PutInode(Base);
    Result := 1;
    {$IFDEF DebugFS} WriteDebug('SysCreateDir: new directory created at %p\n', [PtrUInt(SPath)]); {$ENDIF}
  end;
end;

function SysCreateFile(Path: PAnsiChar): THandle;
var
  Base: PInode;
  Count: LongInt;
  Name: String;
  ino: PInode;
  SPath: PChar;
begin
  Base := Storages[GetApicID].FileSystemMounted.InodeROOT;
  Inc(Base.Count);
  SPath := Path;
  {$IFDEF DebugFS}
    WriteDebug('SysCreateFile: creating file %p\n', [PtrUInt(SPath)]);
  {$ENDIF}
  Inc(Path);
  Count := 1;
  Result := 0;
  SetLength(Name, 0);
  while PtrUint(Path^) <> 0 do
  begin
    if PtrUint(Path^) = 47 then
    begin
      if Base.Mode = INODE_DIR then
        ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, Name)
      else
      begin
        PutInode(Base);
        {$IFDEF DebugFS} WriteDebug('SysCreateFile: failing bad path %p\n', [PtrUInt(SPath)]); {$ENDIF}
        Exit;
      end;
      PutInode(Base);
      if ino = nil then
      begin
        {$IFDEF DebugFS} WriteDebug('SysCreateFile: failing in LookUpInode\n', []); {$ENDIF}
        Exit;
      end;
      SetLength(Name, 0);
      Base := ino;
      Inc(Path);
      count := 1;
    end else
    begin
      SetLength(Name, Length(Name)+1);
      Name[count] := Path^;
      Inc(Count);
      Inc(Path);
    end;
  end;
  if Name[count] = '/' then
  begin
    Name[count] := #0;
    SetLength(Name, Length(Name)-1);
  end;
  ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, Name);
  if ino <> nil then
  begin
    {$IFDEF DebugFS} WriteDebug('SysCreateFile: file %p exists, exiting\n', [PtrUInt(SPath)]); {$ENDIF}
    PutInode(Base);
    Exit;
  end;
  ino := Base.SuperBlock.FileSystemDriver.CreateInode(Base, Name);
  if ino = nil then
  begin
   {$IFDEF DebugFS} WriteDebug('SysCreateFile: creating %p failed\n', [PtrUInt(SPath)]); {$ENDIF}
    PutInode(Base);
  end else
  begin
    PutInode(ino);
    PutInode(Base);
    Result:= SysOpenFile(SPath);
    {$IFDEF DebugFS} WriteDebug('SysCreateFile: new file created in %p, THandle: %d\n', [PtrUInt(SPath), PtrUInt(Result)]); {$ENDIF}
  end;
end;

function SysOpenFile(Path: PXChar): THandle;
var
  FileRegular: PFileRegular;
  Ino: PInode;
begin
  FileRegular := ToroGetMem(SizeOf(TFileRegular));
  if FileRegular = nil then
    Exit;
  Result := 0;
  {$IFDEF DebugFS} WriteDebug('SysOpenFile: opening path: %p\n', [PtrUInt(Path)]); {$ENDIF}
  Ino:= NameI(Path);
  if Ino=nil then
  begin
    ToroFreeMem(FileRegular);
    {$IFDEF DebugFS} WriteDebug('SysOpenFile: File not found\n', []); {$ENDIF}
    Exit;
  end;
  FileRegular.FilePos := 0;
  FileRegular.Inode := Ino;
  Result := THandle(FileRegular);
  {$IFDEF DebugFS} WriteDebug('SysOpenFile: File Openned\n', []); {$ENDIF}
end;

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
    FileRegular.FilePos := Offset
  else if Whence = SeekCur then
    FileRegular.FilePos := FileRegular.FilePos+Offset
  else if Whence = SeekEof then
    FileRegular.FilePos := FileRegular.Inode.Size;
  Result := FileRegular.FilePos;
end;

function SysReadFile(FileHandle: THandle; Count: LongInt; Buffer: Pointer): LongInt;
var
  FileRegular: PFileRegular;
begin
  FileRegular := PFileRegular(FileHandle);
  {$IFDEF DebugFS} WriteDebug('SysReadFile: File: %d, Count: %d, FilePos: %d\n', [PtrUInt(FileHandle), Count, FileRegular.FilePos]); {$ENDIF}
  if FileRegular.Inode.Mode = INODE_DIR then
    Result := 0
  else
    Result := FileRegular.Inode.SuperBlock.FileSystemDriver.ReadFile(FileRegular, Count, Buffer);
  {$IFDEF DebugFS} WriteDebug('SysReadFile: %d bytes read, FilePos: %d\n', [Result, FileRegular.FilePos]); {$ENDIF}
end;

function SysStatFile(Path: PXChar; Buffer: PInode): LongInt;
var
  INode: PInode;
begin
  INode := NameI(Path);
  if INode = nil then
  begin
    Result := 0;
    Exit;
  end;
  Buffer^ := INode^;
  PutInode(INode);
  Result := 1;
end;

function SysWriteFile(FileHandle: THandle; Count: LongInt; Buffer: Pointer): LongInt;
var
  FileRegular: PFileRegular;
begin
  FileRegular := PFileRegular(FileHandle);
  if FileRegular.Inode.Mode = INODE_DIR then
    Result := 0
  else
    Result := FileRegular.Inode.SuperBlock.FileSystemDriver.WriteFile(FileRegular, Count, Buffer);
  {$IFDEF DebugFS} WriteDebug('SysWriteFile: %d bytes written, FilePos: %d\n', [Result, FileRegular.FilePos]); {$ENDIF}
end;

procedure SysCloseFile(FileHandle: THandle);
var
  FileRegular: PFileRegular;
begin
  FileRegular := PFileRegular(FileHandle);
  {$IFDEF DebugFS} WriteDebug('SysCloseFile: Closing file %d\n', [PtrUInt(FileHandle)]); {$ENDIF}
  PutInode(FileRegular.inode);
  ToroFreeMem(FileRegular);
end;

procedure FileSystemInit;
var
  I: LongInt;
begin
  WriteConsoleF('Loading Virtual FileSystem ...\n',[]);
  for I := 0 to MAX_CPU-1 do
  begin
    Storages[I].BlockFiles := nil;
    Storages[I].FileSystemMounted := nil;
  end;
  BlockDevices := nil;
  FileSystemDrivers := nil;
end;

end.
