//
// Memory.pas
//
// Allocator is working with a SX (Size indeX) that distributes block size from 8 bytes up to multi-TB
// BlockSize increments by Power2
// Memory allocator directory maintains lists of free blocks pointers of sizes 8, 16, 32, 64, 128, ..., 1K, 2K, 4K, 1MB, (compiling for Toro, blocks up to multi-TB)
// Memory allocator maintains one directory per CPU
//
// Changes :
//
// 2009.11.01 CPU Cache's Manager Implementation
// 2009.06.09 XMLHeapNuma adapted for TORO by Matias Vara (XMLRAD UltimX - http://xmlrad.sourceforge.net)
// 2009.05.20 Slab allocator is replaced with Cache Allocator
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
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

unit Memory;

{$I Toro.inc}

{$DEFINE XHEAP_STATS}
{$DEFINE XHEAP_STATS2}
{$DEFINE HEAP_STATS}
{$DEFINE HEAP_STATS2}
//{$DEFINE HEAP_STATS_REQUESTED_SIZE}

interface

uses  
  {$IFDEF DEBUG} Debug, {$ENDIF}
  Arch, Console;

const
  MAX_SX = 30; // Size indeX used to access MemoryAllocator directory
  XHEAP_INITIAL_CAPACITY = 1024*128; // 256KB including TXHeap record
  XHEAP_MAX_CHUNKS = 128;
  XHEAP_CHUNK_CAPACITY = 1024*1024; // 1MB

type
  TPointerArray = array[0..0] of Pointer;
  PPointerArray = ^TPointerArray;
  TXHeap = record // Private heap
    ChunkIndex: Integer;
    ChunkOffset: PtrUInt;
    ChunkCapacity: PtrUInt;
    Chunks: array[0..XHEAP_MAX_CHUNKS-1] of Pointer; // Each chunk is 1MB
    StatsCurrent: Integer; // Count of current blocks allocated
    StatsSize: Integer; // Size allocated
    StatsTotal: Integer; // Total of blocks allocated
    StatsVirtualAllocSize: Int64; // Count of VirtualAlloc is ChunkIndex+1
  end;
  PXHeap = ^TXHeap;
  TBlockList = record
    MaxAllocBlockCount: Cardinal; // 1024 default
    CurrentVirtualAlloc: Integer; // for this BlockList
    TotalVirtualAlloc: Integer; // for this BlockList
  	Current: Cardinal; 	// Counter to track the current number of allocated blocks
    Total: Integer;     // Counter to track the total number of memory allocations
  	Capacity: Cardinal;  // Capacity of the List
    Count: Cardinal;			// Actual number of item in List
  	List: PPointerArray;
  end;
  PBlockList = ^TBlockList;
  TMemoryAllocator = record // per CPU
    StartAddress: Pointer;
    EndAddress : Pointer ;
    Size: PtrUInt;
    Initialized: Boolean; // Was Internal Tables initialized ?
    CurrentVirtualAlloc: Integer; // for this CPU
    TotalVirtualAlloc: Integer; // for this CPU
  	Current: Integer; // Counter to track the current number of allocated blocks
    CurrentAllocatedSize: Integer;
    Total: Integer; // Counter to track the total number of memory allocations
    FreeCount: Integer; // for this CPU
    FreeSize: Cardinal; // for this CPU
  	Directory: array[0..MAX_SX-1] of TBlockList; // Index is the SX (Size indeX)
  end;
  PMemoryAllocator = ^TMemoryAllocator;
  TMemoryAllocators = array[0..MAX_CPU-1] of TMemoryAllocator;

var
  DirectorySX: array[0..MAX_SX-1] of PtrUInt; // SX starts at 8 bytes
  DirectoryRequestedSize: array[0..1024] of Integer;
  MemoryAllocators: TMemoryAllocators;
  XHeapStatsCurrent: Integer; // number of TXHeap actually in use
  XHeapStatsTotal: Integer; // total number of TXHeap acquired from boot
  XHeapStatsCurrentVirtualAllocCount: Integer;
  XHeapStatsCurrentVirtualAllocSize: Int64;
  XHeapStatsMaxVirtualAllocCount: Integer;
  XHeapStatsTotalVirtualAllocCount: Integer;
  XHeapStatsTotalVirtualAllocSize: Int64;
  XHeapStatsTotalCount: Int64; // under DEFINE XHEAP_STATS2, updated when TXHeap is released
  XHeapStatsTotalSize: Int64;  // under DEFINE XHEAP_STATS2, updated when TXHeap is released
  MemoryPerCpu : PtrInt; // Amount of memory for every CPU

function GetPointerSize(P: Pointer): Integer;
function XHeapAcquire: PXHeap;
procedure XHeapRelease(Heap: PXHeap);
function XHeapAlloc(Heap: PXHeap; Size: PtrUInt): Pointer;
function XHeapRealloc(Heap: PXHeap; P: Pointer; NewSize: PtrUInt): Pointer;

function GetHeapStatus: THeapStatus;
function ToroGetMem(Size: PtrUInt): Pointer;
function ToroFreeMem(P: Pointer): Integer;
function ToroReAllocMem(P: Pointer; NewSize: PtrUInt): Pointer;
function SysCacheRegion(Add: Pointer; Size: LongInt): Boolean;
function SysUnCacheRegion(Add: Pointer; Size: LongInt): Boolean;
procedure MemoryInit;

implementation

const
  INITIAL_ALLOC_SIZE = 1024*1024; // 1MB
  INITIAL_MAXALLOC_BLOCKCOUNT = 1024; // foreach subsequent SX -> div 2
  BLOCKLIST_INITIAL_CAPACITY = 1024; // 1024 items capacity foreach BlockList (BlockList.Count=0)
  BLOCK_HEADER_SIZE = SizeOf(Cardinal); // the pointer on the block keep track of SX in header PCardinal(Cardinal(P)-BLOCK_HEADER_SIZE)^ = SX
  MINIMUM_VIRTUALALLOC_SIZE = 1024*1024+BLOCK_HEADER_SIZE; // 1MB -> this chunk will be splitted in a BlockList
  MAX_BLOCKSIZE = 1024*1024*1024; // Max block size of memory in allocator
  FLAG_FREE = 1;
  FLAG_PRIVATE_HEAP = 2;
  SX_SHIFT = 16;
  CPU_SHIFT = 2;
  CPU_MASK = $FFFF; // Usage: (Header and CPU_MASK) shr CPU_SHIFT
  MAPSX_COUNT = 1024;
//  PRIVATEHEAP_MAX_BLOCKSIZE = 64*1024*1024; // 64MB

var
	ToroMemoryManager: TMemoryManager;
{$IFDEF HEAP_STATS}
  CurrentVirtualAllocated: Int64;
{$ENDIF}
{$IFDEF HEAP_STATS2}
  TotalVirtualAllocated: Int64;
{$ENDIF}
  MapSX: array[0..MAPSX_COUNT-1] of Byte; // every Index is calculated from Size div 8   
  MIN_GETSX: Byte;

// Returns the upper index for a specific Size, to ensure that any block size requested would fit at least the returned index
// TODO: inline this function
function GetSX(Size: PtrUInt): Byte;
begin
  if Size < MAPSX_COUNT*8 then
  begin
    Result := MapSX[Size div 8];
    Exit;
  end;
  Result := MIN_GETSX;
	while { (Result < MAX_SX-1) and } (DirectorySX[Result] < Size) do
  	Inc(Result);
end;

function GetPointerSize(P: Pointer): Integer;
var
  Header: Cardinal;
begin
  if P = nil then
  begin
    Result := 0;
    Exit;
  end;
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  Header := PCardinal(P)^;
  if Header and FLAG_PRIVATE_HEAP = FLAG_PRIVATE_HEAP then
    Result := DirectorySX[Header shr SX_SHIFT]
  else
    Result := (Header shr 2) * 8;
end;

// Size is 23 bits (max 8x1024x1024, Value div 8 -> encode max 64MB)
// CPU is 6 bits (max 64 CPUs)
// @FlagFree (1 bit): FLAG_FREE to flag if the block is Free
procedure SetHeaderSX(CPU, SX, FlagFree: Byte; P: Pointer);
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  PCardinal(P)^ := FlagFree or (CPU shl CPU_SHIFT) or (SX shl SX_SHIFT);
end;

procedure SetHeaderPrivate(FlagFree: Byte; SizeAlign8: PtrUInt; P: Pointer);
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  PCardinal(P)^ := FlagFree or FLAG_PRIVATE_HEAP or ((SizeAlign8 div 8) shl 2);
end;

procedure ResetFreeFlag(P: Pointer);
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  PCardinal(P)^ := PCardinal(P)^ and $FFFFFFFE;
end;

procedure SetFreeFlag(P: Pointer);
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  PCardinal(P)^ := FLAG_FREE or PCardinal(P)^;
end;

procedure GetHeader(P: Pointer; var CPU, SX, FlagFree, FlagPrivateHeap: Byte; var Size: PtrUInt);
var
  Header: Cardinal;
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  Header := PCardinal(P)^;
  FlagPrivateHeap := Header and FLAG_PRIVATE_HEAP;
  if FlagPrivateHeap <> FLAG_PRIVATE_HEAP then
  begin
    SX := Header shr SX_SHIFT;
    CPU := (Header and CPU_MASK) shr CPU_SHIFT;
    Size := DirectorySX[SX];
  end else begin
    CPU := 0;
    SX := 0;
    Size := (Header shr 2)*8; 
  end;
  FlagFree := Header and FLAG_FREE;
end;

function XHeapAcquire: PXHeap;
begin
  Result := ToroGetMem(XHEAP_INITIAL_CAPACITY);
  Result.ChunkIndex := 0;
  Result.Chunks[0] := Pointer(PtrUInt(Result)+SizeOf(TXHeap));
  Result.ChunkOffset := SizeOf(TXHeap);
  Result.ChunkCapacity := XHEAP_INITIAL_CAPACITY-SizeOf(TXHeap);
{$IFDEF XHEAP_STATS}
  Result.StatsVirtualAllocSize := XHEAP_INITIAL_CAPACITY;
  Inc(XHeapStatsCurrent);
  Inc(XHeapStatsTotal);
  Inc(XHeapStatsCurrentVirtualAllocCount);
  Inc(XHeapStatsCurrentVirtualAllocSize, XHEAP_INITIAL_CAPACITY);
  Inc(XHeapStatsTotalVirtualAllocCount);
  Inc(XHeapStatsTotalVirtualAllocSize, XHEAP_INITIAL_CAPACITY);
{$ENDIF}
{$IFDEF XHEAP_STATS2}
  Result.StatsCurrent := 0;
  Result.StatsSize := 0;
  Result.StatsTotal := 0;
{$ENDIF}
end;

function XHeapAlloc(Heap: PXHeap; Size: PtrUInt): Pointer;
var
  BlockSize: PtrUInt;
  SizeMod8: PtrUInt;
begin
  SizeMod8 := Size mod 8;
  if SizeMod8 > 0 then 
    Inc(Size, 8-SizeMod8); // Align to 8 byte upper boundary
  BlockSize := Size+BLOCK_HEADER_SIZE;
  if Heap.ChunkOffset+BlockSize >= Heap.ChunkCapacity then
  begin
    if Heap.ChunkIndex >= XHEAP_MAX_CHUNKS-1 then
    begin
      Result := nil;
      Exit;
    end;
    Inc(Heap.ChunkIndex);
    Result:= ToroGetMem(XHEAP_CHUNK_CAPACITY);
    if Result = nil then
      Exit;
    Heap.Chunks[Heap.ChunkIndex] := Result;
    Heap.ChunkCapacity := XHEAP_CHUNK_CAPACITY;
    Heap.ChunkOffset := 0;
{$IFDEF XHEAP_STATS}
    Inc(Heap.StatsVirtualAllocSize, Heap.ChunkCapacity);
    Inc(XHeapStatsCurrentVirtualAllocCount);
    Inc(XHeapStatsCurrentVirtualAllocSize, Heap.ChunkCapacity);
    Inc(XHeapStatsTotalVirtualAllocCount);
    Inc(XHeapStatsTotalVirtualAllocSize, Heap.ChunkCapacity);
{$ENDIF}
  end;
  Result := Pointer(PtrUInt(Heap.Chunks[Heap.ChunkIndex])+Heap.ChunkOffset+BLOCK_HEADER_SIZE);
  SetHeaderPrivate(0, Size, Result);
  Inc(Heap.ChunkOffset, BlockSize);
{$IFDEF XHEAP_STATS2}
  Inc(Heap.StatsCurrent);
  Inc(Heap.StatsTotal);
  Inc(Heap.StatsSize, Size);
{$ENDIF}
end;

 function XHeapRealloc(Heap: PXHeap; P: Pointer; NewSize: PtrUInt): Pointer;
var
  CPU: Byte;
  IsFree: Byte;
  IsPrivateHeap: Byte;
	OldSize: PtrUInt;
  OldSX: Byte;
begin
	if P = nil then
  begin
    Result := XHeapAlloc(Heap, NewSize);
    Exit;
  end;
  if NewSize = 0 then
  begin
    ToroFreeMem(P);
    Result := nil;
    Exit;
  end;
  GetHeader(P, CPU, OldSX, IsFree, IsPrivateHeap, OldSize);
  if NewSize <= OldSize then
  begin
    Result := P;
    Exit;
  end;
  Result := XHeapAlloc(Heap, NewSize);
  if Result = nil then
    Exit;
	Move(PByte(P)^, PByte(Result)^, OldSize);
  ToroFreeMem(P);
end;

procedure XHeapRelease(Heap: PXHeap);
var
  I: Integer;
begin
  if Heap = nil then
    Exit;
{$IFDEF XHEAP_STATS2}
  Inc(XHeapStatsTotalCount, Heap.StatsTotal);
  Inc(XHeapStatsTotalSize, Heap.StatsSize);
{$ENDIF}
  for I := 1 to Heap.ChunkIndex do // First Index is the Heap itself
  begin
   // TODO: release in PoolChunks upto a threshold
   ToroFreeMem(Heap.Chunks[I]);
  end;
{$IFDEF XHEAP_STATS}
  Dec(XHeapStatsCurrent);
  Dec(XHeapStatsCurrentVirtualAllocCount, Heap.ChunkIndex+1);
  if Heap.ChunkIndex+1 > XHeapStatsMaxVirtualAllocCount then
    XHeapStatsMaxVirtualAllocCount := Heap.ChunkIndex+1;
  Dec(XHeapStatsCurrentVirtualAllocSize, Heap.StatsVirtualAllocSize);
{$ENDIF}
  Heap.ChunkIndex := -1;
  Heap.ChunkOffset := 0;
  // TODO: release in PoolHeaps upto a threshold
  ToroFreeMem(Heap);
end;

// Called by DistributeChunk and FreeMem
procedure BlockListAdd(BlockList: PBlockList; P: Pointer);
// var
//  NewCapacity: Cardinal;
//  NewList: PPointerArray;
begin
  if BlockList.Count >= BlockList.Capacity then
  begin
   (* // TODO: Need to handle to realloc BlockList in case the actual capacity is reached 
    NewCapacity := BlockList.Capacity*2;
    NewList := ToroGetMem(NewCapacity*SizeOf(Pointer));
    Move(BlockList.List^, NewList^, BlockList.Capacity*SizeOf(Pointer));
    ToroFreeMem(BlockList.List);
    {$IFDEF HEAP_STATS} Inc(CurrentVirtualAllocated, NewCapacity-BlockList.Capacity); {$ENDIF}
    {$IFDEF HEAP_STATS2} Inc(TotalVirtualAllocated, NewCapacity-BlockList.Capacity); {$ENDIF}
	BlockList.Capacity := NewCapacity;
    BlockList.List := NewList;
   	*)
  end;
  BlockList.List^[BlockList.Count] := P;
  Inc(BlockList.Count);
end;

// Make an assignation of Chunk to directory every directory
procedure DistributeChunk(MemoryAllocator: PMemoryAllocator; Chunk: Pointer; ChunkSize: PtrInt);
var
  BlockCount: Cardinal;
  BlockList: PBlockList;
  CPU: longint;
  SX: Byte;
begin
{$IFDEF DebugMemory} DebugTrace('DistributeChunk %h %d bytes', 0, PtrUInt(Chunk), ChunkSize); {$ENDIF}
  {$IFDEF HEAP_STATS} BlockCount := 0; {$ENDIF}
  CPU := GetApicid;
  while ChunkSize > 0 do
  begin
    // DO NOT use GetSX in this case, since we are locating the lower index and not the upper index
    SX := 0;
    while (SX < MAX_SX-2) and (DirectorySX[SX+1]+BLOCK_HEADER_SIZE <= ChunkSize) do
      Inc(SX);
    Chunk := Pointer(PtrUInt(Chunk)+BLOCK_HEADER_SIZE);
    SetHeaderSX(CPU, SX, 1, Chunk);
    BlockList := @MemoryAllocator.Directory[SX];
    BlockListAdd(BlockList, Chunk);
    {$IFDEF HEAP_STATS} Inc(BlockCount); {$ENDIF}
    Chunk := Pointer(PtrUInt(Chunk)+DirectorySX[SX]);
    ChunkSize := ChunkSize-BLOCK_HEADER_SIZE-DirectorySX[SX];
  end;
  {$IFDEF HEAP_STATS} Inc(MemoryAllocators[CPU].FreeSize, BlockCount*DirectorySX[SX]); {$ENDIF}
  {$IFDEF HEAP_STATS2} Inc(MemoryAllocators[CPU].FreeCount, BlockCount); {$ENDIF}
end;

// Initialize MemoryAllocator.Directory splitting the memory chunk reserved for the CPU
// Do one times per CPU
// TODO : Maybe the chuck is too small and i haven't memory for pointer's table
procedure InitializeDirectory(MemoryAllocator: PMemoryAllocator;Chunk:pointer;ChunkSize:PtrUint);
var
  BlockList: PBlockList;
  MaxAllocBlockCount: Integer;
  SX: Byte;
begin
  // this is assignation is only for pointers's tables
  if not MemoryAllocator.Initialized then
  begin
    FillChar(MemoryAllocator.Directory, SizeOf(MemoryAllocator.Directory), 0); // .Capacity=0 .Count=0 .List=nil
    MaxAllocBlockCount := INITIAL_MAXALLOC_BLOCKCOUNT;
    // The tables has been initilized
    MemoryAllocator.Initialized := not (MemoryAllocator.Initialized);
    // ForEach Directory[SX] entry: reserve BLOCKLIST_INITIAL_CAPACITY items.
    for SX := 0 to MAX_SX-1 do
    begin
      BlockList := @MemoryAllocator.Directory[SX];
      BlockList.MaxAllocBlockCount := MaxAllocBlockCount;
      if (MaxAllocBlockCount > 1) and ((SX+1) mod 4 = 0) then
        MaxAllocBlockCount := MaxAllocBlockCount div 2;
      BlockList.Capacity := BLOCKLIST_INITIAL_CAPACITY; // Should be a SX (Size indeX)
      BlockList.Count := 0;
      BlockList.List := Chunk;
      ChunkSize := ChunkSize-BlockList.Capacity*SizeOf(Pointer);
      {$IFDEF HEAP_STATS} Inc(CurrentVirtualAllocated, BlockList.Capacity); {$ENDIF}
      {$IFDEF HEAP_STATS2} Inc(TotalVirtualAllocated, BlockList.Capacity); {$ENDIF}
      Chunk := Pointer(PtrUInt(Chunk)+BlockList.Capacity*SizeOf(Pointer));
    end;
  end;
  DistributeChunk(MemoryAllocator, Chunk, ChunkSize);
end;

// Distribution of Memory for every core .
// this procedure is executed only in Initialization
procedure DistributeMemoryRegions ;
var
  Amount, Counter: PtrUInt;
  Buff: TMemoryRegion;
  CPU, ID: Cardinal;
  StartAddress: Pointer;
begin
  // I am thinking that the regions are sorted
  // Looking for the first ID avaiable
  ID:=1;
  // First Region must start at ALLOC_MEMORY_START
  // Starts at ALLOC_MEMORY_START. The first ALLOC_MEMORY_START are used for internal usage
  while GetMemoryRegion(ID,@Buff) <> 0 do
  begin
    if (Buff.base < ALLOC_MEMORY_START) and (Buff.base+Buff.length-1 > ALLOC_MEMORY_START) and (Buff.Flag <> MEM_RESERVED) then
      Break;
    Inc(ID);
  end;
  // free memory on region
  Amount := Buff.length;
  // allocation start here
  StartAddress := pointer(ALLOC_MEMORY_START);
  for CPU := 0 to CPU_COUNT-1 do
  begin
    // that isn't an continuos block of memory
    MemoryAllocators[CPU].StartAddress := StartAddress;
    MemoryAllocators[CPU].Size := MemoryPerCPU;
    // assignation per CPU
    Counter := MemoryPerCpu;
    while Counter <> 0 do
    begin
      if Amount > Counter then
      begin
        Amount := Amount - Counter;
        // the amount is assigned to the directory
        InitializeDirectory(@MemoryAllocators[CPU], StartAddress, Counter);
        // same region block
        StartAddress:= StartAddress + Counter;
        MemoryAllocators[CPU].EndAddress:=StartAddress;
        // change the cpu
        Counter := 0;
      end else if Amount = Counter then
      begin
        InitializeDirectory(@MemoryAllocators[CPU], StartAddress, Amount);
        MemoryAllocators[CPU].EndAddress := StartAddress + Amount;
        // change the cpu
        Counter := 0;
        // looking for a free block of memory
        Inc(ID);
        while GetMemoryRegion(ID,@Buff) <> 0 do
        begin
          if Buff.Flag = MEM_AVAILABLE then
            Break;
          Inc(ID);
        end;
        // new asignation of memory
        Amount := Buff.length;
        StartAddress := Pointer(Buff.base)
      end else if Amount < Counter then
      begin
        InitializeDirectory(@MemoryAllocators[CPU], StartAddress, Amount);
        Counter := Counter-Amount;
        // looking for a free block of memory
        Inc(ID);
        while GetMemoryRegion(ID,@Buff) <> 0 do
        begin
          if Buff.Flag= MEM_AVAILABLE then
            Break;
          Inc(ID);
        end;
        // new asignation of memory
        Amount := Buff.length;
        StartAddress := Pointer(Buff.base);
      end;
    end;
  end;
end;

// Reasignation of memory
function MemoryReassignation(ChuckSize, SX: longint; MemoryAllocator: PMemoryAllocator): Pointer;
var
  ChunkSX: longint;
  CPU: longint;
  ChunkBlockList: PBlockList;
  Chunk: Pointer;
  ChunkSize: PtrUInt;
  BlockList: PBlockList;
begin
  CPU := GetApicid;
  BlockList := @MemoryAllocator.Directory[SX];
  if SX < 8 then // if Size < 128 bytes
    ChunkSX := 8 // Avoid loss of too small blocks (<32 bytes)
  else
    ChunkSX := SX+1;
  // looking for free blocks
  while (ChunkSX < MAX_SX) and (MemoryAllocator.Directory[ChunkSX].Count = 0) do
    Inc(ChunkSX);
  ChunkBlockList := @MemoryAllocator.Directory[ChunkSX];
  // taking a block
  Chunk := ChunkBlockList.List^[ChunkBlockList.Count-1];
  Dec(ChunkBlockList.Count);
  ChunkSize := DirectorySX[ChunkSX];
  Result := Chunk;
  Chunk := Pointer(PtrUInt(Chunk)+DirectorySX[SX]);
  ChunkSize := ChunkSize-DirectorySX[SX];
  // if BlockSize < 64 bytes then add 3 blocks (2 here and 1 in the SX<8 section) of same size as requested in the Directory of free blocks
  if (SX < 4) and (ChunkSize >= 3*DirectorySX[SX]) then
  begin
    // Optimization to avoid getting too small blocks -> force to split 4 blocks of SX in the Chunk
    SetHeaderSX(CPU, SX, 1, Chunk);
    BlockListAdd(BlockList, Chunk);
    Chunk := Pointer(PtrUInt(Chunk)+DirectorySX[SX]);
    SetHeaderSX(CPU, SX, 1, Chunk);
    BlockListAdd(BlockList, Chunk);
    Chunk := Pointer(PtrUInt(Chunk)+DirectorySX[SX]);
    ChunkSize := ChunkSize-2*DirectorySX[SX];
  end; // DO NOT else on following block this is incremental
  if (SX < 8) and (ChunkSize >= DirectorySX[SX]) then // if BlockSize < 128 bytes then add a second block of same size as requested in the Directory of free blocks
  begin
    // Optimization to avoid getting too small blocks -> force to split 4 blocks of SX in the Chunk
    Chunk := Pointer(PtrUInt(Chunk)+DirectorySX[SX]);
    SetHeaderSX(CPU, SX, 1, Chunk);
    BlockListAdd(BlockList, Chunk);
    ChunkSize := ChunkSize-DirectorySX[SX];
  end;
  // Any other cases should be handled
  DistributeChunk(MemoryAllocator, Chunk, ChunkSize);
end;

function ToroGetMem(Size: PtrUInt): Pointer;
var
  BlockList: PBlockList;
  ChunkSize: Cardinal;
  CPU: Byte;
  MemoryAllocator: PMemoryAllocator;
  SX: Byte;
begin
  Result := nil;
  // What are you trying to do?
  if Size > MAX_BLOCKSIZE then
  begin
    {$IFDEF DebugMemory}DebugTrace('ToroGetMem: Size: %d , fail', 0, Size, 0);{$ENDIF}
    Exit;
  end;
  CPU := GetApicid;
  MemoryAllocator := @MemoryAllocators[CPU];
  SX := GetSX(Size);
{$IFDEF HEAP_STATS_REQUESTED_SIZE}
  if Size <= 1024 then
    Inc(DirectoryRequestedSize[Size]);
{$ENDIF}
    BlockList := @MemoryAllocator.Directory[SX];
    if BlockList.Count = 0 then
    begin
      ChunkSize := DirectorySX[SX];
      Result := MemoryReassignation(ChunkSize, SX, MemoryAllocator);
      ResetFreeFlag(Result);
      if Result = nil then
        Exit;
      {$IFDEF HEAP_STATS} Inc(CurrentVirtualAllocated, ChunkSize); {$ENDIF}
      {$IFDEF HEAP_STATS2}
        Inc(TotalVirtualAllocated, ChunkSize);
        Inc(MemoryAllocator.CurrentVirtualAlloc);
        Inc(MemoryAllocator.TotalVirtualAlloc);
        Inc(BlockList.CurrentVirtualAlloc);
        Inc(BlockList.TotalVirtualAlloc);
      {$ENDIF}
      {$IFDEF DebugMemory}DebugTrace('ToroGetMem: Pointer %q , Size: %d',PtrUint(Result),Size,0);{$ENDIF}
      Exit;
    end;
    Result := BlockList.List^[BlockList.Count-1];
    ResetFreeFlag(Result);
    Dec(BlockList.Count);
  {$IFDEF HEAP_STATS}
    Inc(MemoryAllocator.CurrentAllocatedSize, DirectorySX[SX]);
    Dec(MemoryAllocator.FreeSize, DirectorySX[SX]);
  {$ENDIF}
  {$IFDEF HEAP_STATS2}
    Inc(MemoryAllocator.Current);
    Dec(MemoryAllocator.FreeCount);
    Inc(MemoryAllocator.Total);
    Inc(BlockList.Current); // Counters do not need to be under Lock
    Inc(BlockList.Total);
  {$ENDIF}
  {$IFDEF DebugMemory}DebugTrace('ToroGetMem: Pointer %q , Size: %d',PtrUint(Result),DirectorySX[SX],0);{$ENDIF}
end;

function ToroFreeMem(P: Pointer): Integer;
var
  BlockList: PBlockList;
  CPU: Byte;
  IsFree, IsPrivateHeap: Byte;
  MemoryAllocator: PMemoryAllocator;
  Size: PtrUInt;
  SX: Byte;
begin
  GetHeader(P, CPU, SX, IsFree, IsPrivateHeap, Size); // return block to original CPU MMU
  if IsFree = FLAG_FREE then // already freed
  begin
    Result := -1; // Invalid pointer operation
    Exit;
  end;
  if IsPrivateHeap = FLAG_PRIVATE_HEAP then
  begin
    SetFreeFlag(P); // not necessary, just in case we want to check that a block is not freed twice
    {$IFDEF XHEAP_STATS2}
 //    Dec(CurrentHeap.StatsCurrent); //CurrentHeap may not be the heap of this pointer
 //    Dec(CurrentHeap.StatsSize, Size);
    {$ENDIF}
    Result := 0;
    {$IFDEF DebugMemory}DebugTrace('ToroFreeMem: Pointer %q , PRIVATE HEAP is free',PtrUint(P),0,0);{$ENDIF}
    Exit;
  end;
  MemoryAllocator := @MemoryAllocators[CPU];
  BlockList :=  @MemoryAllocator.Directory[SX];
  SetFreeFlag(P);
  BlockListAdd(BlockList, P);
  {$IFDEF HEAP_STATS}
    Dec(MemoryAllocator.CurrentAllocatedSize, DirectorySX[SX]);
    Inc(MemoryAllocator.FreeSize, DirectorySX[SX]);
  {$ENDIF}
  {$IFDEF HEAP_STATS2}
    Dec(MemoryAllocator.Current);
    Inc(MemoryAllocator.FreeCount);
    Dec(BlockList.Current);
  {$ENDIF}
  {$IFDEF DebugMemory}DebugTrace('ToroFreeMem: Pointer %q',PtrUint(P),0,0);{$ENDIF}
  Result := 0;
end;

// Returns free block of memory filling with zeros
function ToroAllocMem(Size : PtrUInt): Pointer;
begin
	Result := ToroGetMem(Size);
	if Result <> nil then
  	FillChar(Result^, Size, 0);
end;

// Expand (or truncate) the size of block pointed by p and return the new pointer
function ToroReAllocMem(P: Pointer; NewSize: PtrUInt): Pointer;
var
  CPU: Byte;
  IsFree: Byte;
  IsPrivateHeap: Byte;
	OldSize: PtrUInt;
  OldSX: Byte;
begin
	if P = nil then
  begin
    Result := ToroGetMem(NewSize);
    Exit;
  end;
  if NewSize = 0 then
  begin
    ToroFreeMem(P);
    Result := nil;
    Exit;
  end;
  GetHeader(P, CPU, OldSX, IsFree, IsPrivateHeap, OldSize);
  OldSize := DirectorySX[OldSX];
  if NewSize <= OldSize then
  begin
    Result := P;
    Exit; 
  end;
 	Result := ToroGetMem(NewSize);
  if Result = nil then
    Exit;
	Move(PByte(P)^, PByte(Result)^, OldSize); 
  ToroFreeMem(P);
end;

function GetHeapStatus: THeapStatus;
var
  CPU: Byte;
  MemoryAllocator: PMemoryAllocator;
begin
  Result.TotalCommitted := 0;
  {$IFDEF HEAP_STATS}
    Result.TotalCommitted := CurrentVirtualAllocated;
  {$ENDIF}
  Result.TotalAllocated := 0;
  for CPU := 0 to CPU_Count-1 do
  begin
    MemoryAllocator := @MemoryAllocators[CPU];
    if MemoryAllocator = nil then
      Continue;
    {$IFDEF HEAP_STATS}
     	Inc(Result.TotalAllocated, MemoryAllocator.CurrentAllocatedSize);
    {$ENDIF}
  end;
end;


//
// User's Memory Cache Manager
//
// Warnings:
// - Cache's Manager can just mark a region as cacheable when then region is a multiple of 2MB.
// For example:  if you make as CACHEABLE the region from $500000-$900000 , realy, the kernel marks as cacheable the region :
// between $20000-$100000. The Unit in Cache's Manager is the PAGE_SIZE.
//
// - Call to Syscall for Cache the Region from the CORE where are you working . If you call to syscall from CORE#0 and the memory
// region will be useb by CORE#2 the change won't be effect.
//

// Set a Memory's Region as CACHEABLE
function SysCacheRegion(Add: Pointer; Size: LongInt): Boolean;
var
  StartPage, EndPage: Pointer;
  C: PtrUInt;
begin
  // Can Arch Unit hand a Cache's Memory?
  if not HasCacheHandler then
  begin
    Result := False;
    Exit;
  end;
  C := 0;
  while c <= PtrUInt(Add) do
    C := C+PAGE_SIZE;
  if C <> 0 then
    C := C-PAGE_SIZE;
  // StartPage is a Page_Size multipler
  StartPage := Pointer(C);
  Size := Size + PtrUint(Add) mod PAGE_SIZE;
  C := Size div PAGE_SIZE;
  if (Size mod PAGE_SIZE) <> 0 then
    Inc(C);
  EndPage := StartPage+ C*PAGE_SIZE;
  // every page is mark it as CACHEABLE
  while StartPage < EndPage do
  begin
    SetPageCache(StartPage);
    Inc(StartPage, PAGE_SIZE);
  end;
  Result := True;
end;



// Set a Memory's Region as NO-CACHEABLE
function SysUnCacheRegion(Add: Pointer; Size: LongInt): Boolean;
var
  StartPage, EndPage: Pointer;
  C: PtrUInt;
begin
  // Can Arch Unit hand a Cache's Memory?
  if not HasCacheHandler then
  begin
    Result := False;
    Exit;
  end;
  C := 0;
  while c < PtrUInt(Add) do
    C := C+PAGE_SIZE;
  if c <> 0 then
    C := C-PAGE_SIZE;
  // StartPage is a Page_Size multipler
  StartPage := Pointer(c);
  Size := Size + PtrUint(Add) mod PAGE_SIZE;
  C := Size div PAGE_SIZE;
  if (Size mod PAGE_SIZE) <> 0 then
    C := C+1;
  EndPage := StartPage;
  Inc(EndPage, C*PAGE_SIZE);
  // every page is mark it as CACHEABLE
  while StartPage < EndPage do
  begin
    RemovePageCache(StartPage);
    Inc(StartPage,PAGE_SIZE);
  end;
  Result:=true;
end;

// Initilization of Memory Directory for every Core
procedure MemoryInit;
var
  MajorBlockSize: PtrUInt;
  SizeDiv8: Cardinal;
  SX: Byte;
begin
  DirectorySX[0] := 0;
  MajorBlockSize := 8; // First Size indeX is 8 bytes, then 16, 32, 64, 128, ...
  SX := 1;
  while SX < MAX_SX do
  begin
    DirectorySX[SX] := MajorBlockSize;        
    Inc(SX);
    MajorBlockSize := MajorBlockSize*2;
  end;
  SX := 0;
  for SizeDiv8 := 0 to MAPSX_COUNT-1 do
  begin
    while (SX < MAX_SX-1) and (DirectorySX[SX] < SizeDiv8*8+7) do
      Inc(SX);
    MapSX[SizeDiv8] := SX;
  end;
  MIN_GETSX := MapSX[MAPSX_COUNT-1];
  // Linear Assignation for every Core
  MemoryPerCpu := AvailableMemory div CPU_COUNT;
  printk_('System Memory ... /V%d/n bytes\n',AvailableMemory);
  printk_('Memory per Core ... /V%d/n bytes\n',MemoryPerCpu);
  DistributeMemoryRegions; // Initilization of Directory for every Core
  ToroMemoryManager.GetMem := @ToroGetMem;
  ToroMemoryManager.FreeMem := @ToroFreeMem;
  ToroMemoryManager.AllocMem := @ToroAllocMem;
  ToroMemoryManager.ReAllocMem := @ToroReAllocMem;
  SetMemoryManager(ToroMemoryManager);
end;
  
end.

