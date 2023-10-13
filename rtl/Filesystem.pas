//
// FileSystem.pas
//
// This unit contains the virtual filesystem.
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
unit FileSystem;

interface

{$I Toro.inc}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Process, Console, Memory;

const
  MAX_INODES_IN_CACHE= 300;

  INODE_DIR = 1;
  INODE_REG = 2;

  SeekSet = 0;
  SeekCur = 1;
  SeekEof = 2;

  MAX_DEV_NAME = 30;

  O_RDONLY = 0;
  O_WRONLY = 1;
  O_RDWR = 2;

type
  PBlockDriver = ^TBlockDriver;
  PStorage = ^TPerCPUStorage;
  PFileBlock = ^TFileBlock;
  PFileRegular = ^TFileRegular;
  PSuperBlock = ^TSuperBlock;
  PFileSystemDriver = ^TFileSystemDriver;
  PInode = ^TInode;

  TBlockDriver = record
    Busy: Boolean; // protection for access from Local CPU.
    WaitOn: PThread; // Thread using the Driver.
    Name: array[0..MAX_DEV_NAME-1] of Char;
    Major: LongInt;
    Dedicate: procedure (Controller:PBlockDriver;CPUID: LongInt);
    WriteBlock: function (FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
    ReadBlock: function (FileDesc: PFileBlock; Block, Count: LongInt; Buffer: Pointer): LongInt;
    CPUID: LongInt;
    Next: PBlockDriver;
  end;

  TFileBlock = record
    BlockDriver:PBlockDriver;
    Minor: LongInt;
    Next: PFileBlock;
  end;

  TFileRegular = record
    FilePos: LongInt;
    Opaque: QWord;
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
    Name: array[0..MAX_DEV_NAME-1] of Char; // e.g., ext2, fat, etc
    OpenFile: function (FileDesc: PFileRegular; Flags: Longint): LongInt;
    CloseFile: function (FileDesc: PFileRegular): LongInt;
    ReadFile: function (FileDesc: PFileRegular;count: LongInt;Buffer: Pointer): LongInt;
    WriteFile: function (FileDesc: PFileRegular;count: LongInt;Buffer: Pointer): LongInt;
    ReadInode: procedure (Ino: PInode);
    WriteInode: procedure (Ino: Pinode);
    CreateInode: function (Ino: PInode;name: PXChar): PInode;
    CreateInodeDir: function (Ino: PInode;name: PXChar): PInode;
    RemoveInode: function (Ino:PInode;name: PXChar): LongInt;
    LookupInode: function (Ino: PInode;name: PXChar): PInode;
    ReadSuper: function (Spb: PSuperBlock): PSuperBlock;
    Next: PFileSystemDriver;
  end;

  // PerCPU variables require to be padded to CACHELINE_LEN
  TPerCPUStorage = record
    BlockFiles : PFileBlock; // Block File Descriptors
    RegularFiles: PFileBlock; // Regular File Decriptors
    FileSystemMounted: PSuperBlock; // Pointer to mounted filesystem
    Pad: array[1..CACHELINE_LEN-3] of QWORD;
  end;

procedure FileSystemInit;
procedure GetDevice(Dev:PBlockDriver);
procedure FreeDevice(Dev:PBlockDriver);
procedure RegisterBlockDriver(Driver:PBlockDriver);
procedure RegisterFilesystem (Driver: PFileSystemDriver);
procedure DedicateBlockDriver(const Name: PXChar; CPUID: LongInt);
procedure DedicateBlockFile(FBlock: PFileBlock;CPUID: LongInt);
procedure SysCloseFile(FileHandle: THandle);
function SysMount(const FileSystemName, BlockName: PXChar; const Minor: LongInt): Boolean;
function SysOpenFile(Path: PXChar; Flags: Longint): THandle;
function SysCreateDir(Path: PXChar): Longint;
function SysSeekFile(FileHandle: THandle; Offset, Whence: LongInt): LongInt;
function SysStatFile(Path: PXChar; Buffer: PInode): LongInt;
function SysReadFile(FileHandle: THandle; Count: LongInt;Buffer:Pointer): LongInt;
function SysWriteFile(FileHandle: THandle; Count: LongInt; Buffer:Pointer): LongInt;
function GetInode(Inode: LongInt): PInode;
procedure PutInode(Inode: PInode);
function SysCreateFile(Path:  PXChar): THandle;

{$push}
{$codealign varmin=64}
var
  Storages: array[0..MAX_CPU-1] of TPerCPUStorage;
{$pop}

var
  FileSystemDrivers: PFileSystemDriver;

implementation

var
  BlockDevices: PBlockDriver; // Block Drivers installed

procedure RegisterBlockDriver(Driver: PBlockDriver);
begin
  Driver.Next := BlockDevices;
  BlockDevices := Driver;
  {$IFDEF DebugFS} WriteDebug('RegisterBlockDriver: New Driver\n',[]); {$ENDIF}
end;

procedure GetDevice(Dev: PBlockDriver);
begin
  if Dev.Busy then
  begin
    GetCurrentThread.State := tsIOPending;
    GetCurrentThread.IOScheduler.DeviceState:= @Dev.Busy;
    {$IFDEF DebugFS} WriteDebug('GetDevice: Sleeping\n',[]); {$ENDIF}
    SysThreadSwitch;
  end;
  GetCurrentThread.IOScheduler.DeviceState:=nil;
  Dev.Busy := True;
  Dev.WaitOn := GetCurrentThread;
  {$IFDEF DebugFS} WriteDebug('GetDevice: Device in use\n',[]); {$ENDIF}
end;

procedure FreeDevice(Dev: PBlockDriver);
begin
  Dev.Busy := False;
  Dev.WaitOn := nil;
  {$IFDEF DebugFS} WriteDebug('FreeDevice: Device is Free\n', []); {$ENDIF}
end;

procedure DedicateBlockDriver(const Name: PXChar; CPUID: LongInt);
var
  Dev: PBlockDriver;
begin
  Dev := BlockDevices;
  while Dev <> nil do
  begin
    if StrCmp(@Dev.Name, Name, StrLen(Name)) and (Dev.CPUID = -1) then
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

procedure DedicateBlockFile(FBlock: PFileBlock; CPUID: LongInt);
var
  Storage: PStorage;
begin
  Storage := @Storages[CPUID];
  FBlock.Next := Storage.BlockFiles;
  Storage.BlockFiles := FBlock;
  {$IFDEF DebugFS} WriteDebug('DedicateBlockFile: New Block File Descriptor on CPU#%d , Minor: %d\n', [CPUID, FBlock.Minor]); {$ENDIF}
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
    Queue := Inode.Next;
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
  Result := nil;
  Storage := @Storages[GetCoreId];
  Ino := FindInode(Storage.FileSystemMounted.InodeCache.InodeBuffer,Inode);
  if Ino <> nil then
  begin
    Inc(Ino.Count);
    Result := Ino;
    {$IFDEF DebugFS} WriteDebug('GetInode: Inode: %d In Inode-Cache from InodeCache\n', [Ino.ino]); {$ENDIF}
    Exit;
  end;
  Ino := FindInode(Storage.FilesystemMounted.InodeCache.FreeInodesCache, Inode);
  if Ino <> nil then
  begin
    RemoveInode(Storage.FilesystemMounted.InodeCache.FreeInodesCache, Ino);
    AddInode(Storage.FilesystemMounted.InodeCache.InodeBuffer, Ino);
    Result := Ino;
    Ino.Count := 1;
    {$IFDEF DebugFS} WriteDebug('GetInode: Inode: %d in Inode-Cache from FreeInodesCache\n', [Ino.ino]); {$ENDIF}
    Exit;
  end;
  if Storage.FilesystemMounted.InodeCache.InodesInCache=0 then
  begin
    Ino := Storage.FilesystemMounted.InodeCache.FreeInodesCache;
    if Ino = nil then
    begin
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
      {$IFDEF DebugFS} WriteDebug('GetInode: Error reading Inode: %d\n', [Inode]); {$ENDIF}
      Exit;
    end;
    Result := Ino;
    RemoveInode(Storage.FilesystemMounted.InodeCache.FreeInodesCache,Ino);
    AddInode(Storage.FilesystemMounted.InodeCache.InodeBuffer,Ino);
    Ino.Count := 1;
    {$IFDEF DebugFS} WriteDebug('GetInode: running out of space, Inode: %d In Inode-Cache from FreeInodesCache\n', [Ino.ino]); {$ENDIF}
    Exit;
  end;
  Ino := ToroGetMem(SizeOf(TInode));
  if Ino = nil then
    Exit;
  Ino.ino := Inode;
  Ino.Dirty := False;
  Ino.SuperBlock := Storage.FileSystemMounted;
  Storage.FileSystemMounted.FileSystemDriver.ReadInode(Ino);
  Ino.Count := 1;
  if Ino.Dirty then
  begin
    ToroFreeMem(Ino);
    {$IFDEF DebugFS} WriteDebug('GetInode: Error reading Inode: %d\n', [Inode]); {$ENDIF}
    Exit;
  end;
  AddInode(Storage.FilesystemMounted.InodeCache.InodeBuffer, Ino);
  Dec(Storage.FilesystemMounted.InodeCache.InodesInCache);
  Result := Ino;
  {$IFDEF DebugFS} WriteDebug('GetInode: allocating new Inode: %d in Inode-Cache\n', [Ino.ino]); {$ENDIF}
end;

procedure PutInode(Inode: PInode);
begin
  {$IFDEF DebugFS} WriteDebug('PutInode: Inode %d, Count: %d\n', [Inode.ino, Inode.Count]); {$ENDIF}
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

function FindFileSystemDriver(Storage: PStorage; const FileSystemName, BlockName: PXChar; const Minor: LongInt; var FileBlock: PFileBlock): PFileSystemDriver;
begin
  Result := nil;
  FileBlock := Storage.BlockFiles;
  while FileBlock <> nil do
  begin
    if StrCmp(@FileBlock.BlockDriver.Name, BlockName, Strlen(BlockName)) and (FileBlock.Minor = Minor) then
    begin
      Result := FileSystemDrivers;
      while Result <> nil do
      begin
        if StrCmp(@Result.Name, FileSystemName, Strlen(FileSystemName)) then
          Exit;
        Result := Result.Next;
      end;
    end;
    FileBlock := FileBlock.Next;
  end;
end;

function SysMount(const FileSystemName, BlockName: PXChar; const Minor: LongInt): Boolean;
var
  FileBlock: PFileBlock;
  FileSystem: PFileSystemDriver;
  Storage: PStorage;
  SuperBlock: PSuperBlock;
begin
  Result := False;
  Storage := @Storages[GetCoreId];
  FileSystem := FindFileSystemDriver(Storage, FileSystemName, BlockName, Minor, FileBlock);
  if FileSystem = nil then
  begin
    WriteConsoleF('CPU#%d: SysMount Failed, unknown filesystem!\n', [GetCoreId]);
    {$IFDEF DebugFS} WriteDebug('CPU#%d: Mounting FileSystem -> Failed\n', [GetCoreId]); {$ENDIF}
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
    WriteConsoleF('CPU#%d: Fail Reading SuperBlock\n', [GetCoreId]);
    ToroFreeMem(SuperBlock);
    Storage.FileSystemMounted := nil;
    {$IFDEF DebugFS} WriteDebug('SysMount: Mounting Root Filesystem, Cannot read SuperBlock -> Failed\n', []); {$ENDIF}
    Exit;
  end;
  {$IFDEF DebugFS} WriteDebug('SysMount: Mounting Root Filesystem -> Ok\n', []); {$ENDIF}
  WriteConsoleF('SysMount: Filesystem mounted on CPU#%d\n', [GetCoreId]);
  Result := True;
end;

function NameI(Path: PXChar): PInode;
var
  Base: PInode;
  Count: LongInt;
  Name: array[0..254] of Char;
  ino: PInode;
begin
  Result := nil;
  Base := Storages[GetCoreId].FileSystemMounted.InodeROOT;
  {$IFDEF DebugFS} WriteDebug('NameI: Path: %p, Inode Base: %d, Count: %d\n', [PtrUInt(Path), Base.Ino, Base.Count]); {$ENDIF}
  Inc(Base.Count);
  Inc(Path);
  count := 0;
  Name[0] := #0;
  while PtrUint(Path^) <> 0 do
  begin
    // ascii code of '/'
    if PtrUint(Path^) = 47 then
    begin
      if Base.Mode= INODE_DIR then
        ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, Name)
      else
      begin
        {$IFDEF DebugFS} WriteDebug('NameI: Base is not a directory, Path: %p, Inode Base: %d\n', [PtrUInt(Path), Base.Ino]); {$ENDIF}
        PutInode(Base);
        Exit;
      end;
      PutInode(Base);
      if ino = nil then
        Exit;
      Name[0] := #0;
      Base := ino;
      Inc(Path);
      count := 0;
    end else begin
      Name[count] := Path^;
      Name[count + 1] := #0;
      Inc(Count);
      Inc(Path);
    end;
  end;
  if Name[count-1] = '/' then
  begin
    Result := Base;
    Exit;
  end;
  Name[count] := #0;
  ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, Name);
  PutInode(Base);
  Result := ino;
end;

function SysCreateDir(Path: PXChar): Longint;
var
  Base: PInode;
  Count: LongInt;
  Name: array[0..254] of Char;
  ino: PInode;
  {$IFDEF DebugFS}SPath: PChar;{$ENDIF}
begin
  Result := 0;
  Base := Storages[GetCoreId].FileSystemMounted.InodeROOT;
  Inc(Base.Count);
  Inc(Path);
  Count := 0;
  Name[0] := #0;
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
        ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, @Name)
      else
      begin
        PutInode(Base);
        Exit;
      end;
      PutInode(Base);
      if ino = nil then
        Exit;
      Name[0] := #0;
      Base := ino;
      Inc(Path);
      count := 0;
    end else begin
      Name[count] := Path^;
      Name[count+1] := #0;
      Inc(Count);
      Inc(Path);
    end;
  end;
  if Name[count-1] = '/' then
  begin
    Name[count] := #0;
  end;
  ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, @Name);
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

function SysCreateFile(Path: PXChar): THandle;
var
  Base: PInode;
  Count: LongInt;
  Name: array[0..254] of Char;
  ino: PInode;
  SPath: PChar;
begin
  Result := 0;
  Base := Storages[GetCoreId].FileSystemMounted.InodeROOT;
  Inc(Base.Count);
  SPath := Path;
  {$IFDEF DebugFS}
    WriteDebug('SysCreateFile: creating file %p\n', [PtrUInt(SPath)]);
  {$ENDIF}
  Inc(Path);
  Count := 0;
  Name[0] := #0;
  while PtrUint(Path^) <> 0 do
  begin
    if PtrUint(Path^) = 47 then
    begin
      if Base.Mode = INODE_DIR then
        ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, @Name)
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
      Name[0] := #0;
      Base := ino;
      Inc(Path);
      count := 0;
    end else
    begin
      Name[count] := Path^;
      Name[count+1] := #0;
      Inc(Count);
      Inc(Path);
    end;
  end;
  if Name[count-1] = '/' then
  begin
    Name[count] := #0;
  end;
  ino := Base.SuperBlock.FileSystemDriver.LookUpInode(Base, @Name);
  if ino <> nil then
  begin
    {$IFDEF DebugFS} WriteDebug('SysCreateFile: file %p exists, exiting\n', [PtrUInt(SPath)]); {$ENDIF}
    PutInode(Base);
    Exit;
  end;
  ino := Base.SuperBlock.FileSystemDriver.CreateInode(Base, @Name);
  if ino = nil then
  begin
   {$IFDEF DebugFS} WriteDebug('SysCreateFile: creating %p failed\n', [PtrUInt(SPath)]); {$ENDIF}
    PutInode(Base);
  end else
  begin
    PutInode(ino);
    PutInode(Base);
    Result:= SysOpenFile(SPath, O_RDWR);
    {$IFDEF DebugFS} WriteDebug('SysCreateFile: new file created in %p, THandle: %d\n', [PtrUInt(SPath), PtrUInt(Result)]); {$ENDIF}
  end;
end;

function SysOpenFile(Path: PXChar; Flags: Longint): THandle;
var
  FileRegular: PFileRegular;
  Ino: PInode;
begin
  Result := 0;
  FileRegular := ToroGetMem(SizeOf(TFileRegular));
  if FileRegular = nil then
    Exit;
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
  // TODO: to check OpenFile
  If Pointer(@FileRegular.Inode.SuperBlock.FileSystemDriver.OpenFile) <> nil then
    FileRegular.Inode.SuperBlock.FileSystemDriver.OpenFile(FileRegular, Flags);
  Result := THandle(FileRegular);
  {$IFDEF DebugFS} WriteDebug('SysOpenFile: File Openned\n', []); {$ENDIF}
end;

function SysSeekFile(FileHandle: THandle; Offset, Whence: LongInt): LongInt;
var
  FileRegular: PFileRegular;
begin
  Result := 0;
  FileRegular := PFileRegular(FileHandle);
  if FileRegular.Inode.Mode = INODE_DIR then
    Exit
  else if Whence = SeekSet then
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
  Result := 0;
  FileRegular := PFileRegular(FileHandle);
  {$IFDEF DebugFS} WriteDebug('SysReadFile: File: %d, Count: %d, FilePos: %d\n', [PtrUInt(FileHandle), Count, FileRegular.FilePos]); {$ENDIF}
  if FileRegular.Inode.Mode = INODE_DIR then
    Exit
  else
    Result := FileRegular.Inode.SuperBlock.FileSystemDriver.ReadFile(FileRegular, Count, Buffer);
  {$IFDEF DebugFS} WriteDebug('SysReadFile: %d bytes read, FilePos: %d\n', [Result, FileRegular.FilePos]); {$ENDIF}
end;

function SysStatFile(Path: PXChar; Buffer: PInode): LongInt;
var
  INode: PInode;
begin
  Result := 0;
  INode := NameI(Path);
  if INode = nil then
    Exit;
  Buffer^ := INode^;
  PutInode(INode);
  Result := 1;
end;

function SysWriteFile(FileHandle: THandle; Count: LongInt; Buffer: Pointer): LongInt;
var
  FileRegular: PFileRegular;
begin
  Result := 0;
  FileRegular := PFileRegular(FileHandle);
  if FileRegular.Inode.Mode = INODE_DIR then
    Exit
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
  if @FileRegular.Inode.SuperBlock.FileSystemDriver.CloseFile <> nil then
    FileRegular.Inode.SuperBlock.FileSystemDriver.CloseFile(FileRegular);
  ToroFreeMem(FileRegular);
end;

procedure FileSystemInit;
var
  I: LongInt;
begin
  for I := 0 to MAX_CPU-1 do
  begin
    Storages[I].BlockFiles := nil;
    Storages[I].FileSystemMounted := nil;
  end;
  BlockDevices := nil;
  FileSystemDrivers := nil;
end;

end.
