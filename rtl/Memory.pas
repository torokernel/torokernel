//
// Memory.pas
//
// Allocator is working with a SX (Size indeX) that distributes block size from 8 bytes up to multi-TB
// BlockSize increments by Power2.
// Memory allocator directory maintains lists of free blocks pointers of sizes 8, 16, 32, 64, 128, ..., 1K, 2K, 4K, 1MB, (compiling for Toro, blocks up to multi-TB).
// Memory allocator maintains one directory per CPU.
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

unit Memory;

{$I Toro.inc}

{$DEFINE XHEAP_STATS}
{$DEFINE XHEAP_STATS2}
{$DEFINE HEAP_STATS}
{$DEFINE HEAP_STATS2}
//{$DEFINE HEAP_STATS_REQUESTED_SIZE}

interface

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Process, Console;

const
  MAX_SX = 30; // Size indeX used to access MemoryAllocator directory
  XHEAP_INITIAL_CAPACITY = 1024*128; // 256KB including TXHeap record
  XHEAP_MAX_CHUNKS = 128;
  XHEAP_MAX_LARGEBLOCKS = 128; // meaning 128x1MB+
  XHEAP_MAX_STACK = 128;
  XHEAP_CHUNK_CAPACITY = 1024*1024; // 1MB
  POOLHEAP_MAX = 1024; // 1024 heap of 128K per NUMA node -> 128MB
  POOLHEAP_MAXCHUNK = 128; // 128 chunks of 1MB per NUMA node -> 128MB

type
  TBlockHeader = UInt64;
  PBlockHeader = ^TBlockHeader;
  TPointerArray = array[0..0] of Pointer;
  PPointerArray = ^TPointerArray;
  PXHeap = ^TXHeap;
  TXHeap = record // Private heap
    MemoryAllocator: Byte; // used to return heap to proper MemoryAllocators[MemoryAllocator].PoolHeap
    ChunkCount: Integer;
    ChunkIndex: Integer;
    ChunkOffset: PtrUInt;
    ChunkCapacity: PtrUInt;
    {$IFNDEF RELEASE}
      ChunkWaterMark: Integer; // !!! only for debug purpose
      ChunkStackLevel: Integer; // !!! only for debug purpose
      ChunkStackLevelWaterMark: Integer; // !!! only for debug purpose
    {$ENDIF}
    Chunks: array[0..XHEAP_MAX_CHUNKS-1] of Pointer; // Each chunk is 1MB
    LargeBlockCount: Integer;
    LargeBlocks: array[0..XHEAP_MAX_LARGEBLOCKS-1] of Pointer; // Each chunk is 1MB
    Root: PXHeap;
    StackHeaps: array[0..XHEAP_MAX_STACK-1] of PXHeap; // only for RootHeap, Pool of StackHeap used by every call to XScratchStack
    StackHeapCount: Integer;
    StackHeapIndex: Integer;
    StatsCurrent: Integer; // Count of current blocks allocated
    StatsSize: Integer; // Size allocated
    StatsTotal: Integer; // Total of blocks allocated
    StatsVirtualAllocSize: Int64; // Count of VirtualAlloc is ChunkIndex+1
    {$IFNDEF RELEASE}
      WaterMark: PtrUInt; // only for debug purpose to track infinite growing Private/Scratch
    {$ENDIF}
  end;
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
    CurrentAllocatedSize: PtrUInt;
    Total: Integer; // Counter to track the total number of memory allocations
    FreeCount: Integer; // for this CPU
    FreeSize: PtrUInt; // for this CPU
    Directory: array[0..MAX_SX-1] of TBlockList; // Index is the SX (Size indeX)
    PoolHeap: TBlockList; // Blocks of XHEAP_INITIAL_CAPACITY (128KB)
    PoolHeapChunk: TBlockList; // Blocks of XHEAP_CHUNK_CAPACITY (1MB)
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
  MemoryPerCpu: PtrUInt; // Amount of memory for every CPU

function GetPointerSize(P: Pointer): Integer;
function IsPrivateHeap(P: Pointer): Byte; inline;
function XHeapAcquire(CPU: Byte): PXHeap;
function XHeapAlloc(Heap: PXHeap; Size: PtrUInt): Pointer;
procedure XHeapFree(Heap: PXHeap; P: Pointer);
function XHeapRealloc(Heap: PXHeap; P: Pointer; NewSize: PtrUInt): Pointer;
procedure XHeapRelease(Heap: PXHeap);
function XHeapStack(Heap: PXHeap): PXHeap;
function XHeapUnstack(Heap: PXHeap): PXHeap;

function ToroGetMem(Size: PtrUInt): Pointer;
function ToroFreeMem(P: Pointer): Integer;
function NumaFreeMem(P: Pointer): Integer;
function ToroReAllocMem(var P: Pointer; NewSize: PtrUInt): Pointer;
function NumaReAllocMem(P: Pointer; NewSize: PtrUInt): Pointer;
function SysCacheRegion(Add: Pointer; Size: PtrUInt): Boolean;
function SysUnCacheRegion(Add: Pointer; Size: PtrUInt): Boolean;
procedure MemoryInit;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}

const
  INITIAL_ALLOC_SIZE = 1024*1024; // 1MB
  INITIAL_MAXALLOC_BLOCKCOUNT = 1024; // foreach subsequent SX -> div 2
  BLOCKLIST_INITIAL_CAPACITY = 1024; // 1024 items capacity foreach BlockList (BlockList.Count=0)
  BLOCK_HEADER_SIZE = SizeOf(TBlockHeader); // the pointer on the block keep track of SX in header PBlockHeader(TBlockHeader(P)-BLOCK_HEADER_SIZE)^ = SX
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
{$IFDEF FPC}
  ToroMemoryManager: TMemoryManager;
{$ELSE}
  ToroMemoryManager: TMemoryManagerEx;
{$ENDIF}
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
  if Size = 0 then
  begin
    Result := 0;
    Exit;
  end;
  if Size < MAPSX_COUNT*8 then
  begin
    Result := MapSX[(Size-1) div 8]; // KW 20110804 changed from MapSX[Size div 8]
    Exit;
  end;
  Result := MIN_GETSX;
  while { (Result < MAX_SX-1) and } (DirectorySX[Result] < Size) do
    Inc(Result);
end;

function GetPointerSize(P: Pointer): Integer;
var
  Header: TBlockHeader;
begin
  if P = nil then
  begin
    Result := 0;
    Exit;
  end;
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  Header := PBlockHeader(P)^;
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
  PBlockHeader(P)^ := FlagFree or (CPU shl CPU_SHIFT) or (SX shl SX_SHIFT);
end;

procedure SetHeaderPrivate(FlagFree: Byte; SizeAlign8: PtrUInt; P: Pointer);
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  PBlockHeader(P)^ := FlagFree or FLAG_PRIVATE_HEAP or ((SizeAlign8 div 8) shl 2);
end;

procedure ResetFreeFlag(P: Pointer);
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  PBlockHeader(P)^ := PBlockHeader(P)^ and $FFFFFFFE;
end;


function IsFree (P: Pointer): Byte; inline;
var
  Header: TBlockHeader;
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  Header := PBlockHeader(P)^;
  Result := Header and FLAG_FREE;
end;

procedure SetFreeFlag(P: Pointer);
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  PBlockHeader(P)^ := PBlockHeader(P)^ or FLAG_FREE;
end;

procedure GetHeader(P: Pointer; out CPU, SX, FlagFree, FlagPrivateHeap: Byte; out Size: PtrUInt);
var
  Header: TBlockHeader;
begin
  P := Pointer(PtrUInt(P)-BLOCK_HEADER_SIZE);
  Header := PBlockHeader(P)^;
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

function IsPrivateHeap(P: Pointer): Byte; inline;
begin
  Result := PBlockHeader(PtrUInt(P)-BLOCK_HEADER_SIZE)^ and FLAG_PRIVATE_HEAP;
end;

// Shared between XHeapAcquire and XHeapStack
procedure XHeapReset(Heap: PXHeap); inline;
begin
  Heap.ChunkIndex := 0;
  Heap.ChunkOffset := SizeOf(TXHeap);
  Heap.ChunkCapacity := XHEAP_INITIAL_CAPACITY-SizeOf(TXHeap);
  Heap.LargeBlockCount := 0;
end;

function XHeapAcquire(CPU: Byte): PXHeap;
var
  {$IFDEF HEAP_STATS2} BlockList: PBlockList; {$ENDIF}
  MemoryAllocator: PMemoryAllocator;
begin
  Result := nil;
  MemoryAllocator := @MemoryAllocators[CPU];
  if MemoryAllocator.PoolHeap.Count > 0 then
  begin
    Result := MemoryAllocator.PoolHeap.List[MemoryAllocator.PoolHeap.Count-1];
    Result.MemoryAllocator := CPU;
    Dec(MemoryAllocator.PoolHeap.Count);
  end;
  if Result = nil then
  begin
    Result := ToroGetMem(XHEAP_INITIAL_CAPACITY);
    if Result = nil then
    begin
      Exit;
    end;
    Result.MemoryAllocator := CPU;
  end;
  XHeapReset(Result);
  Result.Chunks[0] := Pointer(PtrUInt(Result)+SizeOf(TXHeap));
  Result.ChunkCount := 1;
  Result.Root := nil;
  Result.StackHeapIndex := 0;
  Result.StackHeapCount := 1;
  Result.StackHeaps[0] := Result;
  {$IFDEF XHEAP_STATS2}
    Result.StatsCurrent := 0;
    Result.StatsSize := 0;
    Result.StatsTotal := 0;
  {$ENDIF}
  {$IFDEF HEAP_STATS}
    Dec(MemoryAllocator.FreeSize, XHEAP_INITIAL_CAPACITY);
    Inc(MemoryAllocator.CurrentAllocatedSize, XHEAP_INITIAL_CAPACITY);
  {$ENDIF}
  {$IFDEF HEAP_STATS2}
    Dec(MemoryAllocator.FreeCount);
    Inc(MemoryAllocator.Current);
    Inc(MemoryAllocator.Total);
    BlockList := @MemoryAllocator.PoolHeap;
    Inc(BlockList.Current); // Counters do not need to be under Lock
    Inc(BlockList.Total);
  {$ENDIF}
end;

function XHeapAddChunk(Heap: PXHeap): Pointer;
begin
  Result := nil;
  if Heap.ChunkIndex >= XHEAP_MAX_CHUNKS-1 then
    Exit;
  Inc(Heap.ChunkIndex);
  Result := ToroGetMem(XHEAP_CHUNK_CAPACITY);
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

function XHeapAlloc(Heap: PXHeap; Size: PtrUInt): Pointer;
var
  BlockSize: PtrUInt;
  SizeMod8: PtrUInt;
begin
  SizeMod8 := Size mod 8;
  if SizeMod8 > 0 then
    Inc(Size, 8-SizeMod8); // Align to 8 byte upper boundary
  if Size+BLOCK_HEADER_SIZE >= MINIMUM_VIRTUALALLOC_SIZE then
  begin
    if Heap.LargeBlockCount >= XHEAP_MAX_LARGEBLOCKS then
    begin
      Result := nil; // it will raise OutOfMemory by XAlloc
      Exit;
    end;
    Result := ToroGetMem(Size);
    if Result = nil then
    begin
      Exit;
    end;
    Heap.LargeBlocks[Heap.LargeBlockCount] := Result;
    // NOTE: for large blocks allocated on private heap, the programmer must only use XFree(Heap, P) and not FreeMem(P)
    Inc(Heap.LargeBlockCount);
    Exit;
  end;
  BlockSize := Size+BLOCK_HEADER_SIZE;
  if Heap.ChunkOffset+BlockSize >= Heap.ChunkCapacity then
  begin
    Result := XHeapAddChunk(Heap);
    if Result = nil then
      Exit;
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

procedure XHeapFree(Heap: PXHeap; P: Pointer);
var
  Index, Index2: Integer;
begin
  for Index := Heap.LargeBlockCount-1 downto 0 do
  begin
    if Heap.LargeBlocks[Index] = P then
    begin
      for Index2 := Index to Heap.LargeBlockCount-2 do
        Heap.LargeBlocks[Index2] := Heap.LargeBlocks[Index2+1];
      Dec(Heap.LargeBlockCount);
      ToroFreeMem(P);
      Break;
    end;
  end;
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

// Expand pointer array
function BlockListExpand(BlockList: PBlockList): Boolean;
var
  NewCapacity: Cardinal;
  NewList, tmp: PPointerArray;
begin
  {$IFDEF DebugMemory}WriteDebug('BlockListExpand: BlockList: %h, Count: %d, Capacity: %d\n',[PtrUInt(BlockList), BlockList.Count, BlockList.Capacity]);{$ENDIF}
  Result := False;
  NewCapacity := BlockList.Capacity*2;
  NewList := ToroGetMem(NewCapacity*SizeOf(Pointer));
  if NewList = nil then
    Exit;
  Move(BlockList.List^, NewList^, BlockList.Capacity*SizeOf(Pointer));
  tmp := BlockList.List;
  BlockList.Capacity := NewCapacity;
  BlockList.List := NewList;
  ToroFreeMem(tmp);
  Result := True;
  {$IFDEF HEAP_STATS} Inc(CurrentVirtualAllocated, NewCapacity-BlockList.Capacity); {$ENDIF}
  {$IFDEF HEAP_STATS2} Inc(TotalVirtualAllocated, NewCapacity-BlockList.Capacity); {$ENDIF}
end;

// Called by DistributeChunk and FreeMem
procedure BlockListAdd(BlockList: PBlockList; P: Pointer);
begin
  {$IFDEF DebugMemory}WriteDebug('BlockListAdd: BlockList: %h, P: %h\n',[PtrUInt(BlockList), PtrUInt(P)]);{$ENDIF}
  BlockList.List^[BlockList.Count] := P;
  Inc(BlockList.Count);
  // to avoid race condition with GetMem(), expand before it is full
  if BlockList.Count = BlockList.Capacity-1 then
  begin
    if not BlockListExpand(BlockList) then
      Panic(True, 'BlockListAdd: No enough memory for expanding a list\n', []);
  end;
  {$IFDEF DebugMemory}WriteDebug('BlockListAdd: Chunk: %h, List: %h, Count: %d\n', [PtrUInt(P), PtrUInt(BlockList), BlockList.Count]); {$ENDIF}
end;

procedure PoolHeapRelease(MemoryAllocator: PMemoryAllocator; Heap: PXHeap);
begin
  if MemoryAllocator.PoolHeap.Count < POOLHEAP_MAX then
  begin
    BlockListAdd(@MemoryAllocator.PoolHeap, Heap);
    {$IFDEF HEAP_STATS}
      Dec(MemoryAllocator.CurrentAllocatedSize, XHEAP_INITIAL_CAPACITY);
      Inc(MemoryAllocator.FreeSize, XHEAP_INITIAL_CAPACITY);
    {$ENDIF}
    {$IFDEF HEAP_STATS2}
      Dec(MemoryAllocator.Current);
      Inc(MemoryAllocator.FreeCount);
      Dec(MemoryAllocator.PoolHeap.Current);
    {$ENDIF}
    Exit;
  end;
  ToroFreeMem(Heap);
  {$IFDEF XHEAP_STATS}
    Dec(XHeapStatsCurrentVirtualAllocCount);
    Dec(XHeapStatsCurrentVirtualAllocSize, XHEAP_INITIAL_CAPACITY);
  {$ENDIF}
  {$IFDEF HEAP_STATS}
    Dec(CurrentVirtualAllocated, XHEAP_INITIAL_CAPACITY);
    Dec(MemoryAllocator.CurrentAllocatedSize, XHEAP_INITIAL_CAPACITY);
  {$ENDIF}
  {$IFDEF HEAP_STATS2}
    Dec(MemoryAllocator.CurrentVirtualAlloc);
    Dec(MemoryAllocator.Current);
    Dec(MemoryAllocator.PoolHeap.CurrentVirtualAlloc);
    Dec(MemoryAllocator.PoolHeap.Current);
  {$ENDIF}
end;

procedure PoolHeapChunkRelease(MemoryAllocator: PMemoryAllocator; Chunk: Pointer);
begin
  if MemoryAllocator.PoolHeapChunk.Count < POOLHEAP_MAXCHUNK then
  begin
    BlockListAdd(@MemoryAllocator.PoolHeapChunk, Chunk);
    {$IFDEF HEAP_STATS}
      Dec(MemoryAllocator.CurrentAllocatedSize, XHEAP_CHUNK_CAPACITY);
      Inc(MemoryAllocator.FreeSize, XHEAP_CHUNK_CAPACITY);
    {$ENDIF}
    {$IFDEF HEAP_STATS2}
      Dec(MemoryAllocator.Current);
      Inc(MemoryAllocator.FreeCount);
      Dec(MemoryAllocator.PoolHeapChunk.Current);
    {$ENDIF}
    Exit;
  end;
  ToroFreeMem(Chunk);
  {$IFDEF XHEAP_STATS}
    Dec(XHeapStatsCurrentVirtualAllocCount);
    Dec(XHeapStatsCurrentVirtualAllocSize, XHEAP_CHUNK_CAPACITY);
  {$ENDIF}
  {$IFDEF HEAP_STATS}
    Dec(CurrentVirtualAllocated, XHEAP_CHUNK_CAPACITY);
    Dec(MemoryAllocator.CurrentAllocatedSize, XHEAP_CHUNK_CAPACITY);
  {$ENDIF}
  {$IFDEF HEAP_STATS2}
    Dec(MemoryAllocator.CurrentVirtualAlloc);
    Dec(MemoryAllocator.Current);
    Dec(MemoryAllocator.PoolHeapChunk.CurrentVirtualAlloc);
    Dec(MemoryAllocator.PoolHeapChunk.Current);
  {$ENDIF}
end;

procedure XHeapReleaseStackHeaps(Heap: PXHeap);
var
  I: Integer;
begin
  for I := 1 to Heap.StackHeapCount-1 do // First Index is the Heap itself
    XHeapRelease(Heap.StackHeaps[I]);
end;

procedure XHeapRelease(Heap: PXHeap);
var
  Chunk: Pointer;
  I: Integer;
  MemoryAllocator: PMemoryAllocator;
begin
  if Heap = nil then
    Exit;
  MemoryAllocator := @MemoryAllocators[Heap.MemoryAllocator];
{$IFDEF XHEAP_STATS2}
  Inc(XHeapStatsTotalCount, Heap.StatsTotal);
  Inc(XHeapStatsTotalSize, Heap.StatsSize);
{$ENDIF}
  for I := 0 to Heap.LargeBlockCount-1 do
    ToroFreeMem(Heap.LargeBlocks[I]);
  for I := 1 to Heap.ChunkCount-1 do // First Index is the Heap itself
  begin
    Chunk := Heap.Chunks[I];
    PoolHeapChunkRelease(MemoryAllocator, Chunk);
  end;
  if Heap.Root = nil then
    XHeapReleaseStackHeaps(Heap);
  {$IFDEF XHEAP_STATS}
    if Heap.ChunkIndex+1 > XHeapStatsMaxVirtualAllocCount then
      XHeapStatsMaxVirtualAllocCount := Heap.ChunkCount;
  {$ENDIF}
  Heap.ChunkCount := 0;
  Heap.ChunkIndex := -1;
  Heap.ChunkOffset := 0;
  Heap.LargeBlockCount := 0;
  PoolHeapRelease(MemoryAllocator, Heap);
end;

// Heap cannot be nil
function XHeapStack(Heap: PXHeap): PXHeap;
var
  Root: PXHeap;
begin
  if Heap.Root = nil then
    Root := Heap
  else
    Root := Heap.Root;
  Inc(Root.StackHeapIndex);
  if Root.StackHeapIndex < Root.StackHeapCount then
  begin
    Result := Root.StackHeaps[Root.StackHeapIndex];
    XHeapReset(Result);
  end else begin
    if Root.StackHeapIndex = XHEAP_MAX_STACK then
    begin
      Result := nil; // this maybe a cause for future memory leak (due to not releasing the whole root Scratch)
      Exit;
    end;
    Result := XHeapAcquire(GetCoreId);
    Root.StackHeaps[Root.StackHeapIndex] := Result;
    Inc(Root.StackHeapCount);
    Result.Root := Root;
  end;
end;

// Heap cannot be nil
function XHeapUnstack(Heap: PXHeap): PXHeap;
var
  I: Integer;
  Root: PXHeap;
begin
  if Heap.Root = nil then
    Root := Heap
  else
    Root := Heap.Root;
  for I := 0 to Heap.LargeBlockCount-1 do
    ToroFreeMem(Heap.LargeBlocks[I]);
  Heap.LargeBlockCount := 0;
  Dec(Root.StackHeapIndex);
  Result := Root.StackHeaps[Root.StackHeapIndex];
end;

// Called by ToroGetMem->ObtainFromLargerChunk and by MemoryInit->DistributeMemoryRegions->InitializeDirectory
// Split large chunk into smaller chunks and distribute these smaller chunk in every directory they belongs
procedure SplitChunk(MemoryAllocator: PMemoryAllocator; Chunk: Pointer; ChunkSize: PtrUInt);
var
  BlockCount: Cardinal;
  BlockList: PBlockList;
  CPU: longint;
  SX: Byte;
begin
  {$IFDEF DebugMemory} WriteDebug('SplitChunk Chunk: %h Size: %d bytes\n', [PtrUInt(Chunk), ChunkSize]); {$ENDIF}
  {$IFDEF HEAP_STATS} BlockCount := 0; {$ENDIF}
  SX := 0; // avoid warning when using dcc64
  CPU := GetCoreId;
  while ChunkSize > 0 do
  begin
    // DO NOT use GetSX in this case, since we are locating the lower index and not the upper index
    SX := 0;
    while (SX < MAX_SX-2) and (DirectorySX[SX+1]+BLOCK_HEADER_SIZE <= ChunkSize) do
      Inc(SX);
    Chunk := Pointer(PtrUInt(Chunk)+BLOCK_HEADER_SIZE);
    SetHeaderSX(CPU, SX, FLAG_FREE, Chunk);
    BlockList := @MemoryAllocator.Directory[SX];
    BlockListAdd(BlockList, Chunk);
    ChunkSize := ChunkSize-BLOCK_HEADER_SIZE-DirectorySX[SX];
    {$IFDEF DebugMemory} WriteDebug('SplitChunk Add Block (marked as free): %h SizeSX: %d Remaining ChunkSize: %d\n', [PtrUInt(Chunk), DirectorySX[SX], ChunkSize]); {$ENDIF}
    {$IFDEF HEAP_STATS} Inc(BlockCount); {$ENDIF}
    Chunk := Pointer(PtrUInt(Chunk)+DirectorySX[SX]);
  end;
  {$IFDEF HEAP_STATS} Inc(MemoryAllocators[CPU].FreeSize, BlockCount*DirectorySX[SX]); {$ENDIF}
  {$IFDEF HEAP_STATS2} Inc(MemoryAllocators[CPU].FreeCount, BlockCount); {$ENDIF}
end;

function ObtainFromLargerChunk(SX: LongInt; MemoryAllocator: PMemoryAllocator): Pointer;
var
  ChunkSX: longint;
  ChunkBlockList: PBlockList;
  Chunk: Pointer;
  ChunkSize: PtrUInt;
  bCPU: Byte;
  bIsFree, bIsPrivateHeap: Byte;
  bSX: byte;
  bSize: PtrUInt;
  {$IFDEF DebugMemory}
  j: longint;
  {$ENDIF}
begin
  ChunkSX := SX+1;
  Result := nil;
  while (ChunkSX < MAX_SX) and (MemoryAllocator.Directory[ChunkSX].Count = 0) do
    Inc(ChunkSX);
  ChunkBlockList := @MemoryAllocator.Directory[ChunkSX];
  if ChunkBlockList.Count = 0 then
    Exit;
  Chunk := ChunkBlockList.List^[ChunkBlockList.Count-1];
  {$IFDEF DebugMemory} WriteDebug('ObtainFromLargerChunk: Whole chunk: %h, Size: %d, Count: %d\n', [PtrUInt(Chunk),DirectorySX[ChunkSX], ChunkBlockList.Count]); {$ENDIF}
  {$IFDEF DebugMemory}
    for j:= 0 to (ChunkBlockList.Count-1) do
    begin
      WriteDebug('ObtainFromLargerChunk: dump list %h\n', [PtrUInt(ChunkBlockList.List^[j])]);
    end;
  {$ENDIF}
  if Chunk = nil then
    Exit;
  Dec(ChunkBlockList.Count);
  ChunkSize := DirectorySX[ChunkSX];
  // update the size of block in the header
  // TODO: replace for something simpler
  GetHeader(Chunk , bCPU, bSX, bIsFree, bIsPrivateHeap, bSize);
  bSX := SX;
  SetHeaderSX(bCPU, bSX, bIsFree, Chunk);
  {$IFDEF DebugMemory} WriteDebug('ObtainFromLargerChunk: selected Chunk %h, BlockList: %h, SX: %d\n', [PtrUInt(Chunk),PtrUInt(ChunkBlockList),DirectorySX[bSX]]); {$ENDIF}
  {$IFDEF HEAP_STATS} Dec(MemoryAllocator.FreeSize, DirectorySX[ChunkSX]); {$ENDIF}
  {$IFDEF HEAP_STATS2} Dec(MemoryAllocator.FreeCount); {$ENDIF}
  Result := Chunk;
  Chunk := Pointer(PtrUInt(Chunk)+DirectorySX[SX]);
  ChunkSize := ChunkSize-DirectorySX[SX];
  {$IFDEF DebugMemory} WriteDebug('ObtainFromLargerChunk: Chunk to split: %h Size: %d\n', [PtrUInt(Chunk), ChunkSize]); {$ENDIF}
  SplitChunk(MemoryAllocator, Chunk, ChunkSize);
end;

// Returns a pointer to a block of memory of len at least equal than Size
function ToroGetMem(Size: PtrUInt): Pointer;
var
  BlockList: PBlockList;
  CPU: Byte;
  MemoryAllocator: PMemoryAllocator;
  SX: Byte;
  {$IFDEF DebugMemory}
    bCPU: Byte;
    bIsFree, bIsPrivateHeap: Byte;
    bSX: byte;
    bSize: PtrUInt;
  {$ENDIF}
begin
  DisableInt;
  Result := nil;
  if Size > MAX_BLOCKSIZE then
  begin
    {$IFDEF DebugMemory} WriteDebug('ToroGetMem - Size: %d , fail\n', [Size]); {$ENDIF}
    RestoreInt;
    Exit;
  end;
  CPU := GetCoreId;
  MemoryAllocator := @MemoryAllocators[CPU];
  SX := GetSX(Size);
  {$IFDEF HEAP_STATS_REQUESTED_SIZE}
  if Size <= 1024 then
    Inc(DirectoryRequestedSize[Size]);
  {$ENDIF}
  BlockList := @MemoryAllocator.Directory[SX];
  if BlockList.Count = 0 then
  begin
    {$IFDEF DebugMemory} WriteDebug('ToroGetMem - SplitLargerChunk Size: %d SizeSX: %d\n', [Size, DirectorySX[SX]]); {$ENDIF}
    Result := ObtainFromLargerChunk(SX, MemoryAllocator);
    if Result = nil then
    begin
      WriteConsoleF('ToroGetMem: we ran out of memory!!!\n', []);
    {$IFDEF DebugMemory} WriteDebug('ToroGetMem: we ran out of memory!!!\n', []); {$ENDIF}
      RestoreInt;
      Exit;
    end;
  {$IFDEF DebugMemory}
    // This helps to find corruptions in the headers
    GetHeader(Result , bCPU, bSX, bIsFree, bIsPrivateHeap, bSize);
    WriteDebug('ToroGetMem: Header SXSize %d - List SXSize %d \n', [DirectorySX[bSX],DirectorySX[SX]]);
  {$ENDIF}
  Panic(IsFree(Result)=0,'ToroGetMem: the memory block list has been corrupted\n', []);
  ResetFreeFlag(Result);
  {$IFDEF HEAP_STATS}
    Inc(MemoryAllocator.CurrentAllocatedSize, DirectorySX[SX]);
    Dec(MemoryAllocator.FreeSize, DirectorySX[SX]);
      {$IFDEF InformMemory}
      WriteDebug('ToroGetMem: CurrentAllocatedSize: %dB, FreeSize: %dB\n', [MemoryAllocator.CurrentAllocatedSize, MemoryAllocator.FreeSize]);
    {$ENDIF}
  {$ENDIF}
  {$IFDEF HEAP_STATS2}
    Inc(MemoryAllocator.Current);
    Inc(MemoryAllocator.Total);
    Inc(BlockList.Current); // Counters do not need to be under Lock
    Inc(BlockList.Total);
  {$ENDIF}
  {$IFDEF DebugMemory} WriteDebug('ToroGetMem - Pointer: %h Size: %d SizeSX: %d\n', [PtrUInt(Result), Size, DirectorySX[SX]]); {$ENDIF}
  RestoreInt;
  Exit;
  end;
  Result := BlockList.List^[BlockList.Count-1];
  {$IFDEF DebugMemory}
  WriteDebug('ToroGetMem: Pointer: %h, %d\n',[PtrUInt(Result), BlockList.Count]);
  // This helps to find corruptions in the headers
  GetHeader(Result , bCPU, bSX, bIsFree, bIsPrivateHeap, bSize);
  WriteDebug('ToroGetMem: Header SXSize %d - Lista SXSize %d \n', [DirectorySX[bSX],DirectorySX[SX]]);
  {$ENDIF}
  Panic(IsFree(Result)=0, 'ToroGetMem: the memory block list has been corrupted\n', []);
  ResetFreeFlag(Result);
  Dec(BlockList.Count);
  {$IFDEF HEAP_STATS}
    Inc(MemoryAllocator.CurrentAllocatedSize, DirectorySX[SX]);
    Dec(MemoryAllocator.FreeSize, DirectorySX[SX]);
    {$IFDEF InformMemory}
      WriteDebug('ToroGetMem: CurrentAllocatedSize: %dB, FreeSize: %dB\n', [MemoryAllocator.CurrentAllocatedSize, MemoryAllocator.FreeSize]);
    {$ENDIF}
  {$ENDIF}
  {$IFDEF HEAP_STATS2}
    Inc(MemoryAllocator.Current);
    Dec(MemoryAllocator.FreeCount);
    Inc(MemoryAllocator.Total);
    Inc(BlockList.Current); // Counters do not need to be under Lock
    Inc(BlockList.Total);
  {$ENDIF}
  {$IFDEF DebugMemory} WriteDebug('ToroGetMem - Pointer: %h Size: %d SizeSX: %d\n', [PtrUInt(Result), Size, DirectorySX[SX]]); {$ENDIF}
    RestoreInt;
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
  Result := 1;
  if P = nil then
  begin
    {$IFDEF DebugMemory} WriteDebug('ToroFreeMem: freeing nil pointer\n', []); {$ENDIF}
    Exit;
  end;
  DisableInt;
  GetHeader(P, CPU, SX, IsFree, IsPrivateHeap, Size); // return block to original CPU MMU
  Panic(Size = 0, 'ToroFreeMem: Size of pointer %h cannot be zero, memory has been corrupted\n', [PtrUInt(P)]);
  {$IFDEF DebugMemory} WriteDebug('ToroFreeMem: GetHeader Size %d, p: %h\n', [DirectorySX[SX], PtrUInt(P)]); {$ENDIF}
  Panic(IsFree = FLAG_FREE, 'ToroFreeMem: memory block list corrupted\n', []);
  if IsPrivateHeap = FLAG_PRIVATE_HEAP then
  begin
    SetFreeFlag(P); // not necessary, just in case we want to check that a block is not freed twice
    {$IFDEF XHEAP_STATS2}
 //    Dec(CurrentHeap.StatsCurrent); //CurrentHeap may not be the heap of this pointer
 //    Dec(CurrentHeap.StatsSize, Size);
    {$ENDIF}
    Result := 0;
    {$IFDEF DebugMemory} WriteDebug('ToroFreeMem - Pointer: %h PRIVATE HEAP is free\n', [PtrUInt(P)]);{$ENDIF}
    RestoreInt;
    Exit;
  end;
  MemoryAllocator := @MemoryAllocators[CPU];
  BlockList :=  @MemoryAllocator.Directory[SX];
  SetFreeFlag(P);
  BlockListAdd(BlockList, P);
  {$IFDEF HEAP_STATS}
    Dec(MemoryAllocator.CurrentAllocatedSize, DirectorySX[SX]);
    Inc(MemoryAllocator.FreeSize, DirectorySX[SX]);
    {$IFDEF InformMemory}
      WriteDebug('ToroFreeMem: CurrentAllocatedSize: %dB, FreeSize: %dB\n', [MemoryAllocator.CurrentAllocatedSize, MemoryAllocator.FreeSize]);
    {$ENDIF}
  {$ENDIF}
  {$IFDEF HEAP_STATS2}
    Dec(MemoryAllocator.Current);
    Inc(MemoryAllocator.FreeCount);
    Dec(BlockList.Current);
  {$ENDIF}
  Result := 0;
  RestoreInt;
    {$IFDEF DebugMemory} WriteDebug('ToroFreeMem: Pointer %h, Size: %d\n', [PtrUInt(P), DirectorySX[SX]]); {$ENDIF}
end;

function NumaFreeMem(P: Pointer): Integer;
begin
  Result := ToroFreeMem(P);
end;

// Returns free block of memory filling with zeros
function ToroAllocMem(Size: PtrUInt): Pointer;
begin
  Result := ToroGetMem(Size);
  if Result <> nil then
     FillChar(Result^, Size, 0);
end;

// Expand (or truncate) the size of block pointed by p and return the new pointer
function ToroReAllocMem(var P: Pointer; NewSize: PtrUInt): Pointer;
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

function NumaReAllocMem(P: Pointer; NewSize: PtrUInt): Pointer;
begin
  Result := ToroReAllocMem(P, NewSize);
end;

//
// User's Memory Cache Manager
//
// Warnings:
// - Cache's Manager can just mark a region as cacheable when then region is a multiple of 2MB.
// For example:  if you make as CACHEABLE the region from $500000-$900000 , realy, the kernel marks as cacheable the region :
// between $20000-$100000. The Unit in Cache's Manager is the PAGE_SIZE.
//
// - Call to Syscall for Cache the Region from the CORE where are you working . If you call from CORE#0 and the memory
// region is in CORE#2 the change won't be taken.
//

// Set a Memory's Region as CACHEABLE
function SysCacheRegion(Add: Pointer; Size: PtrUInt): Boolean;
var
  StartPage, EndPage: Pointer;
  PageCount, PageStart: PtrUInt;
begin
  // Can Arch Unit hand a Cache's Memory?
  if not HasCacheHandler then
  begin
    Result := False;
    Exit;
  end;
  PageStart := 0;
  while PageStart <= PtrUInt(Add) do
    PageStart := PageStart+PAGE_SIZE;
  if PageStart <> 0 then
    PageStart := PageStart-PAGE_SIZE;
  // StartPage is a Page_Size multipler
  StartPage := Pointer(PageStart);
  Size := Size + PtrUInt(Add) mod PAGE_SIZE;
  PageCount := Size div PAGE_SIZE;
  if Size mod PAGE_SIZE <> 0 then
    Inc(PageCount);
  EndPage := Pointer(PtrUInt(StartPage)+ PageCount*PAGE_SIZE);
  // every page is mark it as CACHEABLE
  while PtrUInt(StartPage) < PtrUInt(EndPage) do
  begin
    SetPageCache(StartPage);
    StartPage := Pointer(PtrUInt(StartPage) + PAGE_SIZE);
  end;
  Result := True;
end;

// Set a Memory's Region as NO-CACHEABLE
function SysUnCacheRegion(Add: Pointer; Size: PtrUInt): Boolean;
var
  StartPage, EndPage: Pointer;
  PageCount, PageStart: PtrUInt;
begin
  // Can Arch Unit hand a Cache's Memory?
  if not HasCacheHandler then
  begin
    Result := False;
    Exit;
  end;
  PageStart := 0;
  while PageStart < PtrUInt(Add) do
    PageStart := PageStart+PAGE_SIZE;
  if PageStart <> 0 then
    PageStart := PageStart-PAGE_SIZE;
  // StartPage is a Page_Size multipler
  StartPage := Pointer(PageStart);
  Size := Size + PtrUInt(Add) mod PAGE_SIZE;
  PageCount := Size div PAGE_SIZE;
  if Size mod PAGE_SIZE <> 0 then
    Inc(PageCount);
  EndPage := StartPage;
  EndPage := Pointer(PtrUInt(EndPage) + PageCount*PAGE_SIZE);
  // every page is mark it as CACHEABLE
  while PtrUInt(StartPage) < PtrUInt(EndPage) do
  begin
    RemovePageCache(StartPage);
    StartPage := Pointer(PtrUInt(StartPage)+PAGE_SIZE);
  end;
  Result := True;
end;

// Initialize MemoryAllocator.Directory splitting the memory chunk reserved for the CPU
// Do one times per CPU
// TODO : Maybe the chuck is too small and i haven't memory for pointer's table
procedure InitializeDirectory(MemoryAllocator: PMemoryAllocator; Chunk: Pointer; ChunkSize: PtrUInt);
var
  BlockList: PBlockList;
  MaxAllocBlockCount: Integer;
  Shift: PtrUInt;
  SX, bSX: Byte;
begin
  {$IFDEF DebugMemory} WriteDebug('InitializeDirectory Chunk: %h Size: %d\n', [PtrUInt(Chunk), ChunkSize]); {$ENDIF}
  // this is assignation is only for pointers's tables
  if not MemoryAllocator.Initialized then
  begin
    {$IFDEF DebugMemory} WriteDebug('InitializeDirectory first initialization\n', []); {$ENDIF}
    FillChar(MemoryAllocator.Directory, SizeOf(MemoryAllocator.Directory), 0); // .Capacity=0 .Count=0 .List=nil
    MaxAllocBlockCount := INITIAL_MAXALLOC_BLOCKCOUNT;
    MemoryAllocator.Initialized := True;
    // ForEach Directory[SX] entry: reserve BLOCKLIST_INITIAL_CAPACITY items
    for SX := 0 to MAX_SX-1 do
    begin
      BlockList := @MemoryAllocator.Directory[SX];
      BlockList.MaxAllocBlockCount := MaxAllocBlockCount;
      {$IFDEF DebugMemory} WriteDebug('InitializeDirectory: SX: %d, MaxAllocBlockCount: %d\n',[DirectorySX[SX], MaxAllocBlockCount]);{$ENDIF}
      if (MaxAllocBlockCount > 1) and ((SX+1) mod 4 = 0) then
        MaxAllocBlockCount := MaxAllocBlockCount div 2;
      BlockList.Capacity := BLOCKLIST_INITIAL_CAPACITY; // Should be a SX (Size indeX)
      BlockList.Count := 0;
      Chunk := Chunk + SizeOf(BLOCK_HEADER_SIZE);
      bSX := GetSX(BlockList.Capacity*SizeOf(Pointer));
      SetHeaderSX(GetCoreId, bSX, 0, Chunk);
      BlockList.List := Chunk;
      ChunkSize := ChunkSize - DirectorySX[bSX] - sizeof(BLOCK_HEADER_SIZE);
      {$IFDEF HEAP_STATS} Inc(CurrentVirtualAllocated, BlockList.Capacity); {$ENDIF}
      {$IFDEF HEAP_STATS2} Inc(TotalVirtualAllocated, BlockList.Capacity); {$ENDIF}
      Shift := BlockList.Capacity*SizeOf(Pointer);
      Chunk := Pointer(PtrUInt(Chunk)+Shift);
    end;
  end;
  SplitChunk(MemoryAllocator, Chunk, ChunkSize);
end;

procedure InitBlockList(BlockList: PBlockList; MaxAllocBlockCount: Cardinal);
begin
  BlockList.MaxAllocBlockCount := MaxAllocBlockCount;
  BlockList.CurrentVirtualAlloc := 0;
  BlockList.TotalVirtualAlloc := 0;
  BlockList.Current := 0;
  BlockList.Total := 0;
  BlockList.Capacity := BLOCKLIST_INITIAL_CAPACITY; // Should be a SX (Size indeX)
  BlockList.Count := 0;
  BlockList.List := ToroGetMem(BlockList.Capacity*SizeOf(Pointer));
end;

// This is called by MemoryInit()
// It distributes the physical memory for each core
// It split the first block that above $100000 and with the AVAILABLE flag
// TODO: To test in a system with more than 3.5 Gb physical memory
procedure DistributeMemoryRegions;
var
  AssignableMemory: QWord;
  Buff: TMemoryRegion;
  ID, CPU: LongInt;
  MemoryAllocator: PMemoryAllocator;
  StartAddress: Pointer;
begin
  ID := 1;
  while GetMemoryRegion(ID, @Buff) <> 0 do
  begin
    if (Buff.Flag = MEM_AVAILABLE) and (Buff.Base >= $10000) then
      Break;
    Inc(ID);
  end;
  Panic(Buff.Flag = MEM_RESERVED,'DistributeMemoryRegions: Cannot find available memory region\n', []);
  Panic(Buff.Length <= ALLOC_MEMORY_START,'DistributeMemoryRegions: Not enough memory to initialize\n', []);
  AssignableMemory := Buff.Length - (ALLOC_MEMORY_START - PtrUInt(Buff.Base));
  MemoryPerCpu := AssignableMemory div CPU_COUNT;
  WriteConsoleF('System Memory ... %d MB\n', [AvailableMemory div 1024 div 1024]);
  WriteConsoleF('Memory per Core ... %d MB\n', [MemoryPerCpu div 1024 div 1024]);
  {$IFDEF DebugMemory}
    WriteDebug('System Memory ... %d MB\n', [AvailableMemory div 1024 div 1024]);
    WriteDebug('Memory per Core ... %d MB\n', [MemoryPerCpu div 1024 div 1024]);
  {$ENDIF}
  StartAddress := Pointer(ALLOC_MEMORY_START);
  for CPU := 0 to (CPU_COUNT-1) do
  begin
    MemoryAllocator := @MemoryAllocators[CPU];
    MemoryAllocator.StartAddress := StartAddress;
    MemoryAllocator.Size := MemoryPerCpu;
    MemoryAllocator.EndAddress := Pointer(PtrUInt(StartAddress) + MemoryAllocator.Size - 1);
    MemoryAllocator.FreeSize := MemoryAllocator.Size;
    WriteConsoleF('Core#%d, StartAddress: %h, EndAddress: %h\n',[CPU, PtrUInt(StartAddress), PtrUInt(MemoryAllocator.EndAddress)]);
    {$IFDEF DebugMemory}
      WriteDebug('Core#%d, StartAddress: %h, EndAddress: %h\n',[CPU, PtrUInt(StartAddress), PtrUInt(MemoryAllocator.EndAddress)]);
    {$ENDIF}
    InitializeDirectory(MemoryAllocator, StartAddress, MemoryAllocator.Size);
    InitBlockList(@MemoryAllocator.PoolHeap, 0);
    InitBlockList(@MemoryAllocator.PoolHeapChunk, 0);
    StartAddress := Pointer(PtrUInt(MemoryAllocator.EndAddress) + 1);
  end;
end;

procedure MemoryInit;
var
  MajorBlockSize: PtrUInt;
  SizeDiv8: Cardinal;
  SX: Byte;
  {$IFDEF DebugMemory}
   ID: LongInt;
   Buff: TMemoryRegion;
  {$ENDIF}
begin
  FillByte(MemoryAllocators, sizeof(MemoryAllocators), 0);
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
  {$IFDEF DebugMemory}
   // memory map
   ID := 1;
   WriteDebug('Memory Map\n',[]);
   while GetMemoryRegion(ID, @Buff) <> 0 do
   begin
     if Buff.Flag = MEM_RESERVED then
       WriteDebug('%h:%h, Flags: Reserved\n',[Buff.Base,Buff.Base + Buff.Length -1])
     else
       WriteDebug('%h:%h, Flags: Free\n',[Buff.Base,Buff.Base + Buff.Length -1]);
     Inc(ID);
   end;
  {$ENDIF}
  DistributeMemoryRegions; // Initialization of Directory for every Core
  ToroMemoryManager.GetMem := @ToroGetMem;
  ToroMemoryManager.FreeMem := @ToroFreeMem;
  ToroMemoryManager.AllocMem := @ToroAllocMem;
  ToroMemoryManager.ReAllocMem := @ToroReAllocMem;
  ToroMemoryManager.RelocateHeap := nil;
  ToroMemoryManager.InitThread := nil;
  SetMemoryManager(ToroMemoryManager);
end;

end.

