//
// This unit implements a generic ring buffer. The functions do not multicore.
//
// Copyright (c) 2003-2026 Matias Vara <matiasevara@torokernel.io>
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
unit RingBuffer;

{$I Toro.inc}

interface

type
  PRingBuffer = ^TRingBuffer;

  PBuf = ^TBuf;
  TBuf = array[0..0] of Pointer;

  TRingBuffer = record
    Size: LongInt;
    Buf: PBuf;
    Tail: LongInt;
    Head: LongInt;
    Mask: LongInt;
  end;

function RingCreate(Size: PtrUInt): PRingBuffer;
function RingPush(R: PRingBuffer; Item: Pointer): Boolean;
function RingPop(R: PRingBuffer): Pointer;

implementation

uses
  Memory;

function NextPowerOf2(Value: DWORD): DWORD;
begin
  if Value = 0 then
    Exit(1);

  Dec(Value);
  Value := Value or (Value shr 1);
  Value := Value or (Value shr 2);
  Value := Value or (Value shr 4);
  Value := Value or (Value shr 8);
  Value := Value or (Value shr 16);
  Inc(Value);

  Result := Value;
end;

function RingCreate(Size: PtrUInt): PRingBuffer;
var
  R: PRingBuffer;
  RealSize: LongInt;
begin
  RealSize := NextPowerOf2(Size);
  R := ToroGetMem(sizeof(TRingBuffer) + sizeof(Pointer) * RealSize);
  if R = Nil then
    Exit;
  R.Size := RealSize;
  R.Buf := Pointer(PtrUInt(R) + sizeof(TRingBuffer));
  R.Tail := 0;
  R.Head := 0;
  R.Mask := RealSize - 1;
end;

function RingPush(R: PRingBuffer; Item: Pointer): Boolean;
var
  Next: DWORD;
begin
  Result := False;
  Next := (R.Head + 1) and R.Mask;
  // full
  if Next = R.Tail then
    Exit;
  R.Buf[R.Head] := Item;
  // TODO: add memory barrier
  R.Head := Next;
  Result := True;
end;

function RingPop(R: PRingBuffer): Pointer;
begin
  Result := nil;
  if R.Tail = R.Head then
    Exit; // empty

  Result := R.Buf[R.Tail];
  // TODO: add memory barrier
  R.Tail := (R.Tail + 1) and R.Mask;
end;

end.
