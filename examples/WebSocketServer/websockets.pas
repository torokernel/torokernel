unit WebSockets;

{$mode delphi}
{$DEFINE HEAPNUMA}
{$DEFINE SKIP_FREE}
{$DEFINE DebugWebSockets}

interface

uses
  Memory, Network, SysUtils;

type
  VclString = string; // Required for explicit cast for E.Message := VclString(xxx);
  XChar = AnsiChar;
  DelphiString = AnsiString;
  PXChar = PAnsiChar;
  Int32 = LongInt;
  UInt32 = Cardinal;
  PUInt32 = ^UInt32;
  UInt64 = QWORD;
  TXBuffer64  = array[0..63] of XChar;
  TXBuffer128 = array[0..127] of XChar;
  TXBuffer256 = array[0..255] of XChar;
  TXBuffer1K  = array[0..1023] of XChar;

  XString = record // CPU32: 16 bytes, CPU64: 24 bytes ??? KW 20130824 it should be 20 bytes, 24 due to alignment ???
    UnsafeS: PXChar; // All operations should test on Capacity-1
    Offset: Int32; 	// Usage: S.UnsafeS[S.Offset]
    Length: Int32; // MUST BE Int32 and not pointer. XIntToStr can have additional parameter to retrieve length
    Capacity: Int32; // Capacity includes the trailing #0
//    class operator Equal(S1: XString; S2: XString): Boolean; overload;
//    class operator Equal(S1: XString; const S2: DelphiString): Boolean; overload;
    class operator Implicit(const S: DelphiString): XString; inline;
//    class operator NotEqual(S1: XString; S2: XString): Boolean; overload;
//    class operator NotEqual(S1: XString; const S2: DelphiString): Boolean; overload;
  end;

  TByteBuffer = array[0..MaxInt-1] of Byte;
  PByteBuffer = ^TByteBuffer;
  TXBuffer = record
    Buf: PByteBuffer;
    BufStatic: Boolean; // True when Buf is pointing on stack -> in this case, SetCapacity performs XAlloc
    Capacity: Int32;
    Heap: PXHeap;
    Position: Int32; // Start offset is 0. Only used for read operation. Position is not maintained during XBufferAppend and Co in order to improve performance
    Size: Int32;
    function AsString: XString;
  end;
  PXBuffer = ^TXBuffer;

  TXListArray = array[0..4096] of Pointer; // 4096 only to be able to access a member using debugger
  PXListArray = ^TXListArray;
  TXList = record
    Items: PXListArray;
    Count: Int32;
    Capacity: Int32;
    Heap: PXHeap;
  end;

  TSHA1Digest = array[0..19] of Byte;
  PSHA1Digest = ^TSHA1Digest;
  TSHA1 = record
    Context: array[0..4] of UInt32;
  	Digest: TSHA1Digest;
    HashBuffer: array[0..63] of Byte;
    Index: UInt32;
    LenHi, LenLo: UInt32;
    procedure Compress;
    procedure Final;
    procedure Init;
    procedure Update(PBuf: PByte; Size: UInt32); overload;
    procedure Update(const Value: XString); overload;
  end;

function _XChar(const S: XString; Index: Int32): XChar; inline;
function _PXChar(const S: XString): PXChar;
procedure _XString(out Result: XString; const S: DelphiString); overload; inline;
function _XString(const S: DelphiString): XString; overload; inline;
procedure _XStringFromVarOffset(out Result: XString; const Buffer: Pointer; const Offset, Len, Capacity: Int32);
procedure _XString64(out S: XString; var Buffer: TXBuffer64); inline;
procedure _XString128(out S: XString; var Buffer: TXBuffer128); inline;
procedure _XString256(out S: XString; out Buffer: TXBuffer256); inline;
function XBlank(const S: XString): Boolean; inline;
procedure XAppend(var S: XString; const AppendS: XString); overload;
function XCompare(const Left, Right: XString): Int32;
function XEqual(const S1, S2: XString): Boolean;
function XPosChar(const C: XChar; const S: XString; Offset: Int32): Int32;
function XPos(const SubStr, S: XString; Offset: Int32): Int32;
procedure XStringEncodeBASE64(const Source: XString; var Dest: XString; const IsURL, MultiLines, Padding: Boolean);
function _VclString(const Source: XString): VclString;
function Split(const Value: XString; SplitCh: XChar; out Left, Right: XString): Boolean;
function TextFetch(const Text: XString; var Index: Int32; out S: XString): Boolean;

procedure IntToXString(Value: Int32; var S: XString);
procedure IntToXStringAppend(Value: Int32; var S: XString; const FixedLength: Int32);
function XStringToIntDef(const S: XString; const Default: Int32): Int32;

procedure XBufferCreate(out Buffer: TXBuffer; Heap: PXHeap; const Capacity: Int32);
procedure XBufferFree(var Buffer: TXBuffer);
procedure XBufferFromVar(out Buffer: TXBuffer; const Buf: Pointer; const Capacity: Int32; Heap: PXHeap);
procedure XBufferFromXString(out Buffer: TXBuffer; const S: XString; Heap: PXHeap); inline;
procedure XBufferAppend(var Buffer: TXBuffer; const C: XChar); overload; inline;
procedure XBufferAppend(var Buffer: TXBuffer; const C1, C2: XChar); overload; inline;
procedure XBufferAppend(var Buffer: TXBuffer; const Buf; const Size: Int32); overload;
procedure XBufferAppend(var Buffer: TXBuffer; const S: XString); overload;
procedure XBufferAppend(var Buffer: TXBuffer; const Source: TXBuffer); overload;
procedure XBufferAppendFromPosition(var Buffer, Source: TXBuffer);
procedure XBufferAppendInt(var Buffer: TXBuffer; const Value: Int32);
procedure XBufferCheckCapacity(var Buffer: TXBuffer; const AppendSize: Int32);
procedure XBufferClear(var Buffer: TXBuffer);
function XBufferGetXStringIndex(var Buffer: TXBuffer; const Offset, Len: Int32): XString;
function XBufferRead(var Buffer: TXBuffer; out Buf; const Size: Int32): Int32;
procedure XBufferEncodeBASE64(var Source: TXBuffer; var Dest: TXBuffer; const IsURL, MultiLines, Padding: Boolean);
procedure XBufferSetCapacity(var Buffer: TXBuffer; const NewCapacity: Int32);

procedure XListCreate(var List: TXList; Heap: PXHeap; Capacity: Int32);
procedure XListFree(var List: TXList);
procedure XListAdd(var List: TXList; Item: Pointer);
procedure XListDelete(var List: TXList; Index: Int32);
procedure XListExpandCapacity(var List: TXList; NewItems: Int32);
function XListIndexOf(var List: TXList; Item: Pointer): Int32;
procedure XListRemove(var List: TXList; Item: Pointer);

type
  TXObject = class(TObject)
  protected
    FHeap: PXHeap;
  public
    constructor Create; virtual; // virtual in order to be able to use TXObjectClass.Create in TXObjPool
    class function NewInstance: TObject; override;
    procedure FreeInstance; override;
    property Heap: PXHeap read FHeap;
  end;
  TXObjectClass = class of TXObject;

function XObjCreate(ObjClass: TXObjectClass; Heap: PXHeap): Pointer;
function XObjAlloc(ObjClass: TXObjectClass; Heap: PXHeap): Pointer; // this function clear the memory

//------------------------------------------------------------------------------
// TWebSocket
//------------------------------------------------------------------------------
type
  TWebSocket = class;
  TWebSocketState = (wsNone, wsHandshake, wsReady);
  TWebSocket = class(TXObject)
  public
    BufferRead: TXBuffer;
    BufferReadPending: TXBuffer;
    Socket: PSocket;
    State: TWebSocketState;
    constructor Create; override;
    destructor Destroy; override;
    function Receive(var Buffer: TXBuffer): Integer;
    procedure Send(const Buffer: TXBuffer);
    procedure SendMessage(const Code: Byte; const Msg: XString);
  end;

procedure InitNetworkService(var Handler: TNetworkHandler; DoInit: TInitProc; DoAccept, DoReceive, DoClose, DoTimeOut: TSocketProc);
procedure WebSocketsCreate;
procedure WebSocketsFree;

var
  ListWebSockets: TXList;

const
  WEBSOCKET_PORT = 880;
  WEBSOCKET_TIMEOUT = 2*1024*1024*1024-1;

implementation

uses Console, Debug;

function SwapWord(a: Word): Word;
begin
  Result:= ((a and $FF) shl 8) or ((a and $FF00) shr 8);
end;

function SwapDWord(a: UInt32): UInt32;
begin
  Result:= ((a and $FF) shl 24) or ((a and $FF00) shl 8) or ((a and $FF0000) shr 8) or ((a and $FF000000) shr 24);
end;

function UInt16ToNetwork(const Value: Word): Word;
begin
  Result := SwapWord(Value);
end;

function UInt32ToNetwork(const Value: UInt32): UInt32;
begin
  Result := SwapDWord(Value);
end;

function NetworkToUInt16(const Value: Word): Word;
begin
  Result := SwapWord(Value);
end;

function NetworkToUInt32(const Value: UInt32): UInt32;
begin
  Result := SwapDWord(Value);
end;

function XAlloc(Heap: PXHeap; Size: PtrUInt): Pointer; // inline;
begin
{$IFDEF HEAPNUMA}
  if Heap <> nil then
    Result := XHeapAlloc(Heap, Size)
  else begin
    {$IFDEF TORO}
      Result := ToroGetMem(Size);
    {$ELSE}
      Result := GetMem(Size);
    {$ENDIF}
  end;
  {$IFNDEF TORO}
    if Result = nil then
      System.RunError(1); // reOutOfMemory
  {$ELSE}
    if Result = nil then
      RunError(1);
  {$ENDIF}
{$ELSE}
  GetMem(Result, Size);
{$ENDIF}
end;

function XAllocMem(Heap: PXHeap; Size: PtrUInt): Pointer;
begin
  Result := XAlloc(Heap, Size);
  if Result <> nil then
    FillChar(Result^, Size, 0);
end;

procedure XFree(Heap: PXHeap; P: Pointer); inline;
begin
{$IFDEF HEAPNUMA}
  if P = nil then
    Exit;
  {$IFDEF MEMPOISON}
    {$IFDEF CPU32}
      if PtrUInt(P) = $FFFFFFFF then
        raise Xcpt.Create('XFree $FFFFFFFF');
    {$ENDIF}
    {$IFDEF CPU64}
      if PtrUInt(P) = $FFFFFFFFFFFFFFFF then
        raise Xcpt.Create('XFree $FFFFFFFFFFFFFFFF');
    {$ENDIF}
  {$ENDIF}
  if IsPrivateHeap(P) > 0 then
    Exit;
  if Heap <> nil then
    XHeapFree(Heap, P) // occurs only for LargeBlocks allocated on a private heap
  else begin
    {$IFDEF TORO}
      ToroFreeMem(P);
    {$ELSE}
      NumaFreeMem(P);
    {$ENDIF}
  end;
{$ELSE}
  FreeMem(P);
{$ENDIF}
end;

function XRealloc(Heap: PXHeap; P: Pointer; OldSize, NewSize: Int32): Pointer; inline;
begin
{$IFDEF HEAPNUMA}
  if Heap <> nil then
    Result := XHeapRealloc(Heap, P, NewSize)
  else
    Result := NumaReAllocMem(P, NewSize)
{$ELSE}
  ReallocMem(P, NewSize);
  Result := P;
{$ENDIF}
end;

//------------------------------------------------------------------------------
// XString
//------------------------------------------------------------------------------

function _XChar(const S: XString; Index: Int32): XChar; inline;
begin
  Result := XChar(S.UnsafeS[S.Offset+Index-1]);
end;

function _PXChar(const S: XString): PXChar;
begin
  if S.Length = 0 then // KW 20110813 was previously S.UnsafeS = nil
  begin
    Result := nil; // was nil, was '' and back to nil, TODO: check the asm code of this line
    Exit; // nil is a better option since _PXChar is used for APIs calls, and '' is not nil (ie: ExecuteCmd @CurrentDir)
  end;
  Result := @S.UnsafeS[S.Offset];
  if S.UnsafeS[S.Offset+S.Length] = #0 then // protection when this is a string const which does not allow to set the trailing #0
    Exit;
  {$IFNDEF RELEASE}
    if S.Length+1 > S.Capacity then
      WriteDebug('_PXChar - Cannot set trailing #0 char: S.Length[%d]+1 > S.Capacity[%d]', [S.Length, S.Capacity]);
  {$ENDIF}
  S.UnsafeS[S.Offset+S.Length] := #0;
end;

type
  PStrRec = ^StrRec;
  {$IFDEF FPC}
    StrRec = packed record
      CodePage: Word;
      ElementSize: Word;
      {$ifdef CPU64} Dummy: UInt32; {$endif CPU64} // align fields
      refCnt: SizeInt;
      length: SizeInt;
    end;
  {$ELSE}
    StrRec = packed record
      refCnt: Int32;
      length: Int32;
    end;
  {$ENDIF}

procedure _XString(out Result: XString; const S: DelphiString); inline;
begin
  Result.UnsafeS := Pointer(S); // avoid call to LStrToPChar
  Result.Offset := 0; // Usage will be S.UnsafeS[S.Offset]
//  Result.Length := Length(S);
  {$IFDEF MEMSAFE}
    if Pointer(S) = nil then
    begin
      Result.Length := 0
      Result.Capacity := 0;
    end else begin
      {$IFDEF DCC}
        Result.Length := PStrRec(PtrUInt(Pointer(S))-SizeOf(StrRec)).length;
      {$ENDIF}
      {$IFDEF FPC}
        Result.Length := PStrRec(Pointer(S)-SizeOf(StrRec)).length;
      {$ENDIF}
      Result.Capacity := Result.Length+1; // +1 for the trailing #0
    end;
    Exit;
  {$ENDIF}
  {$IFDEF MEMPOISON}
    if Pointer(S) = nil then
      raise Xcpt.Create('Blank string should be replaced with BlankXString constant');
    {$IFDEF DCC}
      Result.Length := PStrRec(PtrUInt(Pointer(S))-SizeOf(StrRec)).length;
    {$ENDIF}
    {$IFDEF FPC}
      Result.Length := PStrRec(Pointer(S)-SizeOf(StrRec)).length;
    {$ENDIF}
    Result.Capacity := -1;
    Exit;
  {$ENDIF} // This should trigger AV since this member should not be used
  {$IFDEF DCC}
    Result.Length := PStrRec(PtrUInt(Pointer(S))-SizeOf(StrRec)).length;
  {$ENDIF}
  {$IFDEF FPC}
    Result.Length := PStrRec(Pointer(S)-SizeOf(StrRec)).length;
  {$ENDIF}
end;

function _XString(const S: DelphiString): XString; inline;
begin
  _XString(Result, S);
end;

procedure _XString(out Result: XString; const S: XString; const Index, Len: Int32); inline;
begin
  Result.UnsafeS := S.UnsafeS;
  Result.Offset := S.Offset+Index-1;
  Result.Length := Len;
  Result.Capacity := S.Capacity-Index;
end;

class operator XString.Implicit(const S: DelphiString): XString;
begin
//  Result := _XString(S);
  _XString(Result, S); // 4x times faster
end;

// @Offset is interpreted as Byte since it is the Offset of the Buffer which is considered ByteBuffer
// @Capacity is interpreted as Byte
procedure _XStringFromVarOffset(out Result: XString; const Buffer: Pointer; const Offset, Len, Capacity: Int32);
begin
  Result.UnsafeS := Buffer;
  Result.Offset := Offset;
  Result.Length := Len;
  Result.Capacity := Capacity;
end;

procedure _XString64(out S: XString; var Buffer: TXBuffer64); inline;
begin
  S.UnsafeS := @Buffer;
  S.Offset := 0;
  S.Length := 0;
  S.Capacity := SizeOf(Buffer);
end;

procedure _XString128(out S: XString; var Buffer: TXBuffer128); inline;
begin
  S.UnsafeS := @Buffer;
  S.Offset := 0;
  S.Length := 0;
  S.Capacity := SizeOf(Buffer);
end;

procedure _XString256(out S: XString; out Buffer: TXBuffer256); inline;
begin
  S.UnsafeS := @Buffer;
  S.Offset := 0;
  S.Length := 0;
  S.Capacity := SizeOf(Buffer);
end;

procedure _XStringEnd(const S: XString; Index: Int32; out Result: XString); inline;
begin
//  _XString(Result, S, Index, S.Length-Index+1);
  if Index > 0 then
    Dec(Index)
  else
    Index := 0;
//	Result.UnsafeS := @S.UnsafeS[S.Offset+Index];
//  Result.Offset := 0;
	Result.UnsafeS := S.UnsafeS;
  Result.Offset := S.Offset+Index;
  Result.Length := S.Length-Index;
  Result.Capacity := S.Capacity-Index;
end;

function XBlank(const S: XString): Boolean; inline;
begin
  Result := S.Length <= 0;
end;

procedure XAppend(var S: XString; const AppendS: XString);
begin
  if AppendS.Length = 0 then
    Exit;
{$IFDEF XSTRING_RANGECHECK}
  if S.Length+AppendS.Length > S.Capacity then
    raise Xcpt.CreateFmt('XAppend - S.Length[%d]+AppendS.Length[%d] exceeds S.Capacity[%d].', [S.Length, AppendS.Length, S.Capacity]);
{$ENDIF}
  Move(AppendS.UnsafeS[AppendS.Offset], S.UnsafeS[S.Offset+S.Length], AppendS.Length);
  Inc(S.Length, AppendS.Length);
end;

function XCompare(const Left, Right: XString): Int32;
var
  I, Index: Integer;
  Len: Int32;
  PLeft, PRight: PCardinal;
  PCLeft, PCRight: PXChar;
begin
  Len := Left.Length;
  if Right.Length < Len then
    Len := Right.Length;
  PLeft := PCardinal(@Left.UnsafeS[Left.Offset]);
  PRight := PCardinal(@Right.UnsafeS[Right.Offset]);
  Index := Len div 4;
  for I := 1 to Index do
  begin
    Result := PLeft^ - PRight^;
    if Result <> 0 then
      Break; // KW 20110814 !!! DO NOT Exit -> We must compare char by char
    Inc(PLeft);
    Inc(PRight);
    Dec(Len, 4);
  end;
  PCLeft := PXChar(PLeft);
  PCRight := PXChar(PRight);
  while Len > 0 do
  begin
    Result := Ord(PCLeft^) - Ord(PCRight^);
    if Result <> 0 then
      Exit;
    Dec(Len);
    Inc(PCLeft);
    Inc(PCRight);
  end;
  Result := Left.Length - Right.Length;
end;

function XEqual(const S1, S2: XString): Boolean;
begin
  if S1.Length <> S2.Length then
    Result := False
  else if not XBlank(S1) then
  begin
    Result := XCompare(S1, S2) = 0
  end else
    Result := True; // Both length are 0
end;

// @Dest[Source.Length+35%] MUST BE large enough to avoid realloc otherwise Encode is failing
// @MultiLines=True @Complement=True if you need standard formatting
procedure XStringEncodeBASE64(const Source: XString; var Dest: XString; const IsURL, MultiLines, Padding: Boolean);
var
  DestBuffer: TXBuffer;
  SourceBuffer: TXBuffer;
begin
  Dest.Length := 0;
  XBufferFromXString(SourceBuffer, Source, nil);
  XBufferFromXString(DestBuffer, Dest, nil);
  XBufferEncodeBase64(SourceBuffer, DestBuffer, IsURL, MultiLines, Padding);
  Dest.Length := DestBuffer.Size;
end;

function _DelphiStringEx(S: XString): DelphiString;
var
  P: PStrRec;
  P2: PXChar;
begin
  Pointer(Result) := nil;
  if S.Length <= 0 then
    Exit;
  P := XAlloc(nil, S.Length+SizeOf(StrRec)+1);
  Pointer(Result) := Pointer(PtrUInt(P) + SizeOf(StrRec));
  P2 := Pointer(PtrUInt(P) + SizeOf(StrRec));
  {$IFDEF FPC}
    P.Codepage := 0;
    P.ElementSize := 1;
  {$ENDIF}
  P.length := S.Length;
  P.refcnt := 1;
  Move(S.UnsafeS[S.Offset], P2^, S.Length);
  P2[S.Length] := #0; // !!! Check if this line does not trigger UniqueStringA
                      // -> if this is the case, convert to PByte(Result)[] := 0
end;

// !!! This function allocates memory -> it is slow
function _VclString(const Source: XString): VclString;
begin
  Result := _DelphiStringEx(Source);
end;

// S index starts at 1
// Result starts at 1
// Result=0 if not found
function XPosChar(const C: XChar; const S: XString; Offset: Int32): Int32;
var
  Len: Int32;
  P: PXChar;
begin
  Result := Offset;
  if Result <= 0 then
    Result := 1; // Protection against range error
  P := @S.UnsafeS[S.Offset+Result-1];
  Len := S.Length;
  while Result <= Len do
  begin
    if XChar(P^) = C then
      Exit;
    Inc(Result);
    Inc(P);
  end;
  Result := 0;
end;

// S index starts at 1
// S index starts at 1
// Result starts at 1
function XPos(const SubStr, S: XString; Offset: Int32): Int32;
var
  Len, LenSubStr: Int32;
  P, P2, PSubStr, PSubStr2: PXChar;
begin
  if XBlank(SubStr) or XBlank(S) then
  begin
    Result := 0;
    Exit;
  end;
  if Offset > S.Length then
  begin
    Result := 0;
    Exit;
  end;
  if Offset = 0 then
    Result := 1 // KW 20050102 Protection against range error
  else
    Result := Offset;
//  Len := S.Length - SubStr.Length + 1;
  Len := S.Length - SubStr.Length + 1 - Result + 1; // KW 20100819 added "- Result + 1"
  P := @S.UnsafeS[S.Offset+Result-1];
  PSubStr := @SubStr.UnsafeS[SubStr.Offset];
  while Len > 0 do
  begin
    if P^ = PSubStr^ then
    begin
      LenSubStr := SubStr.Length-1;
      P2 := P;
      Inc(P2);
      PSubStr2 := PSubStr;
      Inc(PSubStr2);
      while (LenSubStr > 0) and (P2^ = PSubStr2^) do
      begin
        Inc(P2);
        Inc(PSubStr2);
        Dec(LenSubStr);
      end;
      if LenSubStr = 0 then
        Exit;
    end;
    Inc(P);
    Inc(Result);
    Dec(Len);
  end;
  Result := 0;
end;

procedure XTrim(var S: XString);
var
  P: PXChar;
begin
  if S.UnsafeS = nil then
    Exit;
  P := @S.UnsafeS[S.Offset];
  while (S.Length > 0) and (P^ <= ' ') do
  begin
    Inc(P);
    Inc(S.Offset);
    Dec(S.Length);
  end;
  P := @S.UnsafeS[S.Offset+S.Length-1];
  while (S.Length > 0) and (P^ <= ' ') do
  begin
    Dec(P);
    Dec(S.Length);
  end;
end;

function Split(const Value: XString; SplitCh: XChar; out Left, Right: XString): Boolean;
var
  Index: Integer;
  Source: XString;
begin
  Index := XPosChar(SplitCh, Value, 1);
  if Index = 0 then
  begin
    Result := False;
    Left := Value;
    Right.Length := 0;
  end else begin
    Result := True;
    Source := Value; // KW 20180415 if @Left is @Value then @Right will be invalid
    _XString(Left, Source, 1, Index-1);
    _XStringEnd(Source, Index+1, Right);
  end;
end;

// Usage: Index := 1; while DelimiterTextFetch(Text, ';', Index, S) do Work with S
function DelimiterTextFetch(const Text: XString; const Delimiter: XChar; var Index: Int32; out S: XString): Boolean;
var
  Offset: Int32;
begin
  if Index > Text.Length then // KW 20110528 was ">=" but is incorrect to fetch last number for 192.168.1.1
  begin
    _XStringEnd(Text, Text.Length+1, S); // meaning blank string pointing at the end of Text
    Result := False;
    Exit;
  end;
  Offset := Index;
  if Offset <= 0 then
    Offset := 1;
  Index := XPosChar(Delimiter, Text, Offset);
  if Index = 0 then
    Index := Text.Length+1;
  _XString(S, Text, Offset, Index-Offset);
  Inc(Index);
  Result := True;
end;

function DelimiterTextFetchNameValue(const Text: XString; const Delimiter: XChar; var Index: Int32; var Name, Value: XString): Boolean;
var
  S: XString;
begin
  Result := DelimiterTextFetch(Text, Delimiter, Index, S);
  if not Result then
    Exit;
  Split(S, XChar('='), Name, Value);
end;


procedure IntToXString(Value: Int32; var S: XString);
begin
  S.Length := 0;
  IntToXStringAppend(Value, S, 0);
end;

// This function is shared with IntToXString, DateToXString and TimeToXString
procedure IntToXStringAppend(Value: Int32; var S: XString; const FixedLength: Int32);
const
  BUFFER_LENGTH = 32;
var
  Buffer: array[0..BUFFER_LENGTH] of XChar;
  IMod: Int32;
  Len: Int32;
  Negative: Boolean;
  Index: Int32;
begin
  Index := BUFFER_LENGTH; // At the end of the operation we will Move the whole buffer to the left most part
  Len := 0;
  Negative := Value < 0;
  if Negative then
    Value := -Value;
//	while (Index >= 0) and (Value <> 0) do
  repeat
    IMod := Value mod 10;
    Buffer[Index] := XChar(Ord('0')+IMod); // !!! Check that Ord('0') is compiled as a constant
    Dec(Index);
    Inc(Len);
    Value := Value div 10;
  until (Index < 0) or (Value = 0);
  while (Index >= 0) and (Len < FixedLength) do
  begin
    Buffer[Index] := XChar('0');
    Dec(Index);
    Inc(Len);
    if (Index = 0) and Negative then
      Break;
  end;
  if Negative then
  begin
    Buffer[Index] := XChar('-');
    Dec(Index);
    Inc(Len);
  end;
  if S.Length+Len > S.Capacity then
    raise Exception.Create('IntToXStringAppend');
  Move(Buffer[Index+1], S.UnsafeS[S.Offset+S.Length], Len);
  S.Length := S.Length+Len;
end;

// TODO: debug at least one time
// @Index=1
function HexToUInt32Def(const S: XString; const Index: Int32; const Default: UInt32): UInt32;
const
  Convert: array['0'..'f'] of SmallInt =
    ( 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,-1,-1,-1,-1,-1,-1,
     -1,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,
     -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
     -1,10,11,12,13,14,15);
var
  Len: Int32;
  P: PXChar;
  Value: Byte;
begin
  P:= @S.UnsafeS[S.Offset+Index-1];
  Len := S.Length-Index+1;
  if P^ = '$' then
  begin
    Inc(P);
    Dec(Len);
  end;
  Result := 0;
  while Len > 0 do
  begin
    if Result > (High(Result) div 16) then
    begin
      Result := Default; // raise Xcpt.Create('Invalid Hex value');
      Exit;
    end;
    Value := Byte(Convert[P^]);
    if Value = 255 then
    begin
      Result := Default; // raise Xcpt.Create('Invalid Hex value');
      Exit;
    end;
    Result := (Result shl 4) or Value;
    Inc(P);
    Dec(Len);
  end
end;

// Usage: Index := 1; while TextFetch(Text, Index, S) do Work with S
function TextFetch(const Text: XString; var Index: Int32; out S: XString): Boolean;
var
  Offset: Int32;
begin
  if Index <= 0 then
    Index := 1;
  if Index > Text.Length then // KW 20100501 changed >= to >
  begin
    Result := False;
    Exit;
  end;
  Offset := Index;
  Index := XPosChar(XChar(#10), Text, Offset);
  if Index = 0 then
    Index := Text.Length+1;
  if _XChar(Text, Index-1) = XChar(#13) then
    _XString(S, Text, Offset, Index-Offset-1)
  else
    _XString(S, Text, Offset, Index-Offset);
  Inc(Index);
  Result := True;
end;

function XStringToIntDef(const S: XString; const Default: Int32): Int32;
var
  C: XChar;
  I: Int32;
  Negative: Boolean;
	SBuffer: PXChar;
begin
  if XBlank(S) then
  begin
		Result := Default;
  	Exit;
  end;
	SBuffer := @(PXChar(S.UnsafeS)[S.Offset]);
  I := 0;
  Result := 0;
  Negative := False;
  while (I < S.Length) and (SBuffer[I] = ' ') do
  	Inc(I);
  if I >= S.Length then
  begin
		Result := Default;
  	Exit;
  end;
  C := XChar(SBuffer[I]);
  case C of
    XChar('$'), XChar('x'), XChar('X'): begin
          Result := HexToUInt32Def(S, I+1, Default);
          Exit;
        end;
    XChar('0'): begin
          if (I < S.Length) and ((XChar(SBuffer[I+1]) = XChar('x')) or (XChar(SBuffer[I+1]) = XChar('X'))) then
          begin
            Result := HexToUInt32Def(S, I+2, Default);
            Exit;
          end;
        end;
    XChar('-'): begin
          Negative := True;
          Inc(I);
        end;
    XChar('+'): Inc(I);
  end;
  while I < S.Length do
  begin
    if Result > (High(Result) div 10) then
    begin
      Result := Default;
      Exit;
    end;
    C := XChar(SBuffer[I]);
    if (C < XChar('0')) or (C > XChar('9')) then
    begin
      Result := Default;
      Exit;
    end;
    Result := Result * 10 + Ord(C) - Ord('0');
    Inc(I);
  end;
  if Negative then
    Result := -Result;
end;

//------------------------------------------------------------------------------
// TXBuffer
//------------------------------------------------------------------------------

procedure XBufferCreate(out Buffer: TXBuffer; Heap: PXHeap; const Capacity: Int32);
begin
  Buffer.Heap := Heap;
  if Capacity > 0 then
  begin
    Buffer.Buf := XAlloc(Heap, Capacity)
  end else
    Buffer.Buf := nil;
  Buffer.BufStatic := False;
//  Buffer.Position := 0;
  Buffer.Size := 0;
  Buffer.Capacity := Capacity;
end;

procedure XBufferFree(var Buffer: TXBuffer);
begin
  {$IFDEF SKIP_FREE} if Buffer.Heap <> nil then Exit; {$ENDIF}
  if (Buffer.Buf <> nil) and not Buffer.BufStatic then
    XFree(Buffer.Heap, Buffer.Buf);
  Buffer.Buf := nil;
//  Buffer.Position := 0;
  Buffer.Size := 0;
  Buffer.Capacity := 0;
  Buffer.Heap := nil;
end;

procedure XBufferFromVar(out Buffer: TXBuffer; const Buf: Pointer; const Capacity: Int32; Heap: PXHeap);
begin
  Buffer.Buf := Buf;
  Buffer.BufStatic := True;
  Buffer.Heap := Heap; // in-case Capacity is exceeded, then XAlloc will occur using this Heap
//  Buffer.Position := 0;
  Buffer.Size := 0;
  Buffer.Capacity := Capacity;
end;

procedure XBufferFromXString(out Buffer: TXBuffer; const S: XString; Heap: PXHeap);
begin
  Buffer.Buf := @S.UnsafeS[S.Offset];
  Buffer.BufStatic := True;
  Buffer.Heap := Heap; // in-case Capacity is exceeded, then XAlloc will occur using this Heap
//  Buffer.Position := 0;
  Buffer.Size := S.Length;
  Buffer.Capacity := S.Capacity;
end;

procedure XBufferAppend(var Buffer: TXBuffer; const C: XChar);
begin
  Buffer.Buf[Buffer.Size] := Byte(C);
  Inc(Buffer.Size);
end;

procedure XBufferAppend(var Buffer: TXBuffer; const C1, C2: XChar);
begin
  Buffer.Buf[Buffer.Size] := Byte(C1);
  Buffer.Buf[Buffer.Size+1] := Byte(C2);
  Inc(Buffer.Size, 2);
end;

procedure XBufferAppend(var Buffer: TXBuffer; const Buf; const Size: Int32);
begin
	if Size = 0 then
  	Exit;
	if Buffer.Size+Size > Buffer.Capacity then
    XBufferCheckCapacity(Buffer, Size);
  Move(Buf, Buffer.Buf[Buffer.Size], Size);
  Inc(Buffer.Size, Size);
//  Buffer.Position := Buffer.Size;
end;

procedure XBufferAppend(var Buffer: TXBuffer; const S: XString);
var
	Size: Int32;
begin
  Size := S.Length;
  if Size <= 0 then
  	Exit;
	if Buffer.Size+Size > Buffer.Capacity then
    XBufferCheckCapacity(Buffer, Size);
  Move(S.UnsafeS[S.Offset], Buffer.Buf[Buffer.Size], Size);
  Inc(Buffer.Size, Size);
//  Buffer.Position := Buffer.Size;
end;

procedure XBufferAppend(var Buffer: TXBuffer; const Source: TXBuffer);
begin
	if Source.Size = 0 then
  	Exit;
	if Buffer.Size+Source.Size > Buffer.Capacity then
    XBufferCheckCapacity(Buffer, Source.Size);
  Move(Source.Buf^, Buffer.Buf[Buffer.Size], Source.Size);
  Inc(Buffer.Size, Source.Size);
//  Buffer.Position := Buffer.Size;
end;

procedure XBufferAppendFromPosition(var Buffer, Source: TXBuffer);
begin
  XBufferAppend(Buffer, Source.Buf[Source.Position], Source.Size-Source.Position);
end;

// This function convert Int32 into the final buffer as string
procedure XBufferAppendInt(var Buffer: TXBuffer; const Value: Int32);
var
  S: XString;
begin
	if Buffer.Size+32 > Buffer.Capacity then
    XBufferCheckCapacity(Buffer, 32);
  _XStringFromVarOffset(S, Buffer.Buf, Buffer.Size, 0, 32);
  IntToXString(Value, S);
  Buffer.Size := Buffer.Size+S.Length;
//  Buffer.Position := Buffer.Size;
end;

procedure XBufferCheckCapacity(var Buffer: TXBuffer; const AppendSize: Int32);
var
	NewCapacity: Int32;
  P: PByteBuffer;
begin
	if Buffer.Size+AppendSize <= Buffer.Capacity then
    Exit;
  if Buffer.Size = 0 then
  begin // avoid to Move previous content
    XBufferSetCapacity(Buffer, AppendSize);
    Exit;
  end;
  NewCapacity := Buffer.Capacity + AppendSize;
  if NewCapacity < Buffer.Capacity+(Buffer.Capacity div 4) then
    NewCapacity := Buffer.Capacity+(Buffer.Capacity div 4);
  if Buffer.BufStatic then
  begin
    P := XAlloc(Buffer.Heap, NewCapacity);
    Move(Buffer.Buf[0], P^, Buffer.Size);
    Buffer.Buf := P;
    Buffer.BufStatic := False;
  end else begin
    Buffer.Buf := XRealloc(Buffer.Heap, Buffer.Buf, Buffer.Capacity, NewCapacity);
  end;
  Buffer.Capacity := NewCapacity;
  if Buffer.Size > NewCapacity then
    Buffer.Size := NewCapacity; // TODO: Debug this line, it looks more like a problem at caller site
end;

procedure XBufferClear(var Buffer: TXBuffer);
begin
  Buffer.Position := 0;
  Buffer.Size := 0;
end;

// Offset starts at 0
function XBufferGetXStringIndex(var Buffer: TXBuffer; const Offset, Len: Int32): XString;
begin
  Result.UnsafeS := PXChar(@Buffer.Buf[Offset]);
  Result.Offset := 0;
  Result.Length := Len;
  Result.Capacity := Len; // or Buffer.Capacity-Offset // but certainly not: Buffer.Capacity-Offset-Len;
end;

function XBufferRead(var Buffer: TXBuffer; out Buf; const Size: Int32): Int32;
begin
  if Size > Buffer.Size-Buffer.Position then
    Result := Buffer.Size-Buffer.Position
  else
    Result := Size;
  Move(Buffer.Buf[Buffer.Position], Buf, Result);
  Inc(Buffer.Position, Result);
end;

procedure XBufferSetCapacity(var Buffer: TXBuffer; const NewCapacity: Int32);
begin
  if NewCapacity <= Buffer.Capacity then
    Exit;
  if Buffer.BufStatic then
  begin
    Buffer.Buf := XAlloc(Buffer.Heap, NewCapacity);
    Buffer.BufStatic := False;
  end else
  begin
    if Buffer.Buf <> nil then
      XFree(Buffer.Heap, Buffer.Buf); // KW 20151029 this was a potential memory leak
    Buffer.Buf := XAlloc(Buffer.Heap, NewCapacity);
  end;
  Buffer.Capacity := NewCapacity;
end;

function TXBuffer.AsString: XString;
begin
//  if (Buffer.Buf <> nil) and (Buffer.Size < Buffer.Capacity) then // KW 20160923 corrupting the underlying TXBuffer content
//    Buffer.Buf[Buffer.Size] := 0;
  Result.UnsafeS := PXChar(Self.Buf);
  Result.Offset := 0;
  Result.Length := Self.Size;
  Result.Capacity := Self.Capacity;
end;

function GetBase64EncodedSize(const SourceSize: Integer; const MultiLines: Boolean): Integer;
var
  Lines: Integer;
begin
  Result := (SourceSize div 3) * 4;
  if SourceSize mod 3 > 0 then
    Inc(Result, 4);
  if MultiLines then
  begin
    Lines := Result div 76;
    Inc(Result, Lines*2); // #13#10 for each lines
  end;
end;

// @MultiLines=True @Padding=True if you need standard formatting
// @MultiLines=False @Padding=False if you need single line no trailing '='
// @IsURL=True
procedure XBufferEncodeBASE64(var Source: TXBuffer; var Dest: TXBuffer; const IsURL, MultiLines, Padding: Boolean);
const
  FCodingTable: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  FCodingTableURL: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  procedure XBufferEncode64_1(var DestBuf: PByteBuffer; const AIn1: Byte; const IsURL: Boolean); inline;
  begin
    if IsURL then
    begin
      DestBuf[0] := Ord(FCodingTableURL[((AIn1 shr 2) and 63) + 1]);
      DestBuf[1] := Ord(FCodingTableURL[((AIn1 shl 4) and 63) + 1]);
    end else begin
      DestBuf[0] := Ord(FCodingTable[((AIn1 shr 2) and 63) + 1]);
      DestBuf[1] := Ord(FCodingTable[((AIn1 shl 4) and 63) + 1]);
    end;
    DestBuf := Pointer(PtrUInt(DestBuf)+2);
  end;

  procedure XBufferEncode64_2(var DestBuf: PByteBuffer; const AIn1, AIn2: Byte; const IsURL: Boolean); inline;
  begin
    if IsURL then
    begin
      DestBuf[0] := Ord(FCodingTableURL[((AIn1 shr 2) and 63) + 1]);
      DestBuf[1] := Ord(FCodingTableURL[(((AIn1 shl 4) or (AIn2 shr 4)) and 63) + 1]);
      DestBuf[2] := Ord(FCodingTableURL[((AIn2 shl 2) and 63) + 1]);
    end else begin
      DestBuf[0] := Ord(FCodingTable[((AIn1 shr 2) and 63) + 1]);
      DestBuf[1] := Ord(FCodingTable[(((AIn1 shl 4) or (AIn2 shr 4)) and 63) + 1]);
      DestBuf[2] := Ord(FCodingTable[((AIn2 shl 2) and 63) + 1]);
    end;
    DestBuf := Pointer(PtrUInt(DestBuf)+3);
  end;

  procedure XBufferEncode64_3(var DestBuf: PByteBuffer; const AIn1, AIn2, AIn3: Byte; const IsURL: Boolean); inline;
  begin
    if IsURL then
    begin
      DestBuf[0] := Ord(FCodingTableURL[((AIn1 shr 2) and 63) + 1]);
      DestBuf[1] := Ord(FCodingTableURL[(((AIn1 shl 4) or (AIn2 shr 4)) and 63) + 1]);
      DestBuf[2] := Ord(FCodingTableURL[(((AIn2 shl 2) or (AIn3 shr 6)) and 63) + 1]);
      DestBuf[3] := Ord(FCodingTableURL[(Ord(AIn3) and 63) + 1]);
    end else begin
      DestBuf[0] := Ord(FCodingTable[((AIn1 shr 2) and 63) + 1]);
      DestBuf[1] := Ord(FCodingTable[(((AIn1 shl 4) or (AIn2 shr 4)) and 63) + 1]);
      DestBuf[2] := Ord(FCodingTable[(((AIn2 shl 2) or (AIn3 shr 6)) and 63) + 1]);
      DestBuf[3] := Ord(FCodingTable[(Ord(AIn3) and 63) + 1]);
    end;
    DestBuf := Pointer(PtrUInt(DestBuf)+4);
  end;

var
  BufSize, BufSize3: Integer;
  Ch1, Ch2, Ch3: Byte;
  DestBuf, SourceBuf: PByteBuffer;
  DestCapacity, DestSize: Integer;
  Index, IndexCRLF : Integer;
begin
  BufSize := Source.Size;
  if BufSize = 0 then
    Exit;
  DestCapacity := GetBase64EncodedSize(BufSize, MultiLines);
  DestSize := 0;
  XBufferSetCapacity(Dest, DestCapacity);
  SourceBuf := Source.Buf;
  DestBuf := Dest.Buf;
  IndexCRLF := 0;
  Index := 0;
  BufSize3 := (BufSize div 3)*3;
  while Index < BufSize3 do
  begin // Process the buffer up to the trailing 2 chars
    Ch1 := SourceBuf[0];
    Ch2 := SourceBuf[1];
    Ch3 := SourceBuf[2];
    SourceBuf := Pointer(PtrUInt(SourceBuf)+3);
    Inc(Index, 3);
    XBufferEncode64_3(DestBuf, Ch1, Ch2, Ch3, IsURL);
    Inc(DestSize, 4);
    if MultiLines then
    begin
      if (IndexCRLF = 18) and (Index < BufSize3) then // KW 20170405 BufSize -> BufSize3
      begin
        DestBuf[0] := Ord(#13);
        DestBuf[1] := Ord(#10);
        DestBuf := Pointer(PtrUInt(DestBuf)+2);
        Inc(DestSize, 2);
        IndexCRLF := 0;
      end else
        Inc(IndexCRLF);
    end;
  end;
  if MultiLines and (IndexCRLF = 19) and (Index < BufSize) then  // KW 20170405 IndexCRLF=18 -> 19
  begin
    DestBuf[0] := Ord(#13);
    DestBuf[1] := Ord(#10);
    DestBuf := Pointer(PtrUInt(DestBuf)+2);
    Inc(DestSize, 2);
  end;
  if Index = BufSize-2 then // Last remaining 2 chars
  begin
    Ch1 := SourceBuf[0];
    Ch2 := SourceBuf[1];
    XBufferEncode64_2(DestBuf, Ch1, Ch2, IsURL);
    Inc(DestSize, 3);
    if Padding then
    begin
      DestBuf[0] := Ord('=');
      Inc(DestSize);
    end;
  end else if Index = BufSize-1 then // Last remaining char
  begin
    Ch1 := Source.Buf[Index];
    XBufferEncode64_1(DestBuf, Ch1, IsURL);
    Inc(DestSize, 2);
    if Padding then
    begin
      DestBuf[0] := Ord('=');
      DestBuf[1] := Ord('=');
      Inc(DestSize, 2);
    end;
  end;
  Dest.Size := DestSize;
end;

// -----------------------------------------------------------------------------
// TXList
// -----------------------------------------------------------------------------

procedure XListCreate(var List: TXList; Heap: PXHeap; Capacity: Int32);
begin
  List.Count := 0;
  if Capacity > 0 then
    List.Items := XAlloc(Heap, Capacity*SizeOf(Pointer))
  else
    List.Items := nil;
  List.Capacity := Capacity;
  List.Heap := Heap;
end;

procedure XListFree(var List: TXList);
begin
  if List.Items = nil then
    Exit;
  XFree(List.Heap, List.Items);
  List.Items := nil;
  List.Capacity := 0;
  List.Count := 0;
  List.Heap := nil;
end;

procedure XListAdd(var List: TXList; Item: Pointer);
begin
  if List.Count >= List.Capacity then
    XListExpandCapacity(List, 1);
  List.Items[List.Count] := Item;
  Inc(List.Count);
end;

procedure XListDelete(var List: TXList; Index: Int32);
var
  Count: Integer;
//  P: PPointer; // TODO: try to optimize, bug detected when using PPointer to copy items
begin
{$IFDEF DEBUG_CHECK}
  if (Index < 0) or (Index >= List.Count) then
    raise Xcpt.CreateFmt('XListDelete - List index out of bounds (%d)', [Index]);
{$ENDIF}
	if Index < List.Count-1 then
  begin
  	if List.Count-Index-1 > 8 then
			Move(List.Items[Index+1], List.Items[Index], (List.Count-Index-1)*SizeOf(Pointer)) // KW 20120724 List.Count-Index-1 TODO: debug at least 1 time
    else begin
      Count := List.Count-Index-1;
      while Count > 0 do
      begin
        List.Items[Index] := List.Items[Index+1];
        Inc(Index);
        Dec(Count);
      end;
    end;
  end;
  Dec(List.Count);
end;

procedure XListExpandCapacity(var List: TXList; NewItems: Int32);
var
  NewCapacity: Int32;
begin
  if NewItems < 16 then
    NewItems := 16;
  if List.Capacity = 0 then
    NewCapacity := NewItems
  else
    NewCapacity := List.Capacity + NewItems + List.Capacity div 4; // +25%
  List.Items := XRealloc(List.Heap, List.Items, List.Capacity*SizeOf(Pointer), NewCapacity*SizeOf(Pointer));
  List.Capacity := NewCapacity;
end;

function XListIndexOf(var List: TXList; Item: Pointer): Int32;
begin
  Result := 0;
  while (Result < List.Count) and (List.Items[Result] <> Item) do
    Inc(Result);
  if Result = List.Count then
    Result := -1;
end;

procedure XListRemove(var List: TXList; Item: Pointer);
var
	Index: Int32;
begin
  Index := XListIndexOf(List, Item);
  if Index >= 0 then
    XListDelete(List, Index);
end;

// -----------------------------------------------------------------------------
// TXObject
// -----------------------------------------------------------------------------

function XObjCreate(ObjClass: TXObjectClass; Heap: PXHeap): Pointer;
var
  Obj: TXObject;
  ObjSize: LongInt;
begin
  ObjSize := ObjClass.InstanceSize;
  Result := XAlloc(Heap, ObjSize);
  PPointer(Result)^ := Pointer(ObjClass);
  Obj := Result;
  Obj.FHeap := Heap;
  Obj.Create;
end;

// Forces to fill memory with #0
function XObjAlloc(ObjClass: TXObjectClass; Heap: PXHeap): Pointer;
var
  Obj: TXObject;
  ObjSize: LongInt;
begin
  ObjSize := ObjClass.InstanceSize;
  Result := XAlloc(Heap, ObjSize);
  FillChar(Result^, ObjSize, 0);
  PPointer(Result)^ := Pointer(ObjClass);
  Obj := Result;
  Obj.FHeap := Heap;
  Obj.Create;
end;

constructor TXObject.Create;
begin
  inherited;
end;

// !!! WARNING: TXObject created on PrivateHeap or ScratchHeap are not purging their native delphi members such as dynamic arrays, interfaces, or string
procedure TXObject.FreeInstance;
begin
  {$IFDEF SKIP_FREE} if FHeap = nil then {$ENDIF}
    XFree(nil, Self);
end;

//{$IFNDEF AUTOREFCOUNT}
class function TXObject.NewInstance: TObject;
var
  ObjSize: Integer;
begin
	// At this point we could passthru the ClassName to XAlloc for stats/tracking (under DEFINE control)
  ObjSize := Self.InstanceSize;
  Result := XAlloc(nil, ObjSize);
  {$IFDEF AUTOREFCOUNT} FillChar(Pointer(Result)^, ObjSize, 0); {$ENDIF}
  {$IFDEF MEMSAFE}
    FillChar(Pointer(Result)^, ObjSize, 0);
  {$ENDIF}
  {$IFDEF MEMPOISON}
    FillChar(Pointer(Result)^, ObjSize, $FF);
  {$ENDIF}
  {$IFDEF AUTOREFCOUNT} TXObject(Result).FRefCount := 2; {$ENDIF}
  TXObject(Result).FHeap := nil;
  PPointer(Result)^ := Pointer(Self); // !!! Check that this code do the same as the code in InitInstance
end;
//{$ENDIF}


//------------------------------------------------------------------------------
// SHA1
//------------------------------------------------------------------------------

procedure TSHA1.Init;
begin
  Self.LenHi:= 0;
  Self.LenLo:= 0;
  Self.Index:= 0;
  FillChar(Self.HashBuffer, Sizeof(Self.HashBuffer), 0);
  Self.Context[0]:= $67452301;
  Self.Context[1]:= $EFCDAB89;
  Self.Context[2]:= $98BADCFE;
  Self.Context[3]:= $10325476;
  Self.Context[4]:= $C3D2E1F0;
end;

{. $R-}{. $Q-}

procedure TSHA1.Compress;
var
  A, B, C, D, E: UInt32;
  W: array[0..79] of UInt32;
  i: UInt32;
begin
  Index := 0;
  Move(HashBuffer, W, Sizeof(HashBuffer));
  for I := 0 to 15 do
    W[I] := SwapDWord(W[I]);
  for I := 16 to 79 do
    W[I]:= ((W[I-3] xor W[I-8] xor W[I-14] xor W[I-16]) shl 1) or ((W[I-3] xor W[I-8] xor W[I-14] xor W[I-16]) shr 31);
  A := Context[0]; B := Context[1]; C := Context[2]; D := Context[3]; E := Context[4];

  Inc(E,((A shl 5) or (A shr 27)) + (D xor (B and (C xor D))) + $5A827999 + W[ 0]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (C xor (A and (B xor C))) + $5A827999 + W[ 1]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (B xor (E and (A xor B))) + $5A827999 + W[ 2]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (A xor (D and (E xor A))) + $5A827999 + W[ 3]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (E xor (C and (D xor E))) + $5A827999 + W[ 4]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + (D xor (B and (C xor D))) + $5A827999 + W[ 5]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (C xor (A and (B xor C))) + $5A827999 + W[ 6]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (B xor (E and (A xor B))) + $5A827999 + W[ 7]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (A xor (D and (E xor A))) + $5A827999 + W[ 8]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (E xor (C and (D xor E))) + $5A827999 + W[ 9]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + (D xor (B and (C xor D))) + $5A827999 + W[10]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (C xor (A and (B xor C))) + $5A827999 + W[11]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (B xor (E and (A xor B))) + $5A827999 + W[12]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (A xor (D and (E xor A))) + $5A827999 + W[13]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (E xor (C and (D xor E))) + $5A827999 + W[14]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + (D xor (B and (C xor D))) + $5A827999 + W[15]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (C xor (A and (B xor C))) + $5A827999 + W[16]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (B xor (E and (A xor B))) + $5A827999 + W[17]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (A xor (D and (E xor A))) + $5A827999 + W[18]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (E xor (C and (D xor E))) + $5A827999 + W[19]); C:= (C shl 30) or (C shr 2);

  Inc(E,((A shl 5) or (A shr 27)) + (B xor C xor D) + $6ED9EBA1 + W[20]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (A xor B xor C) + $6ED9EBA1 + W[21]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (E xor A xor B) + $6ED9EBA1 + W[22]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (D xor E xor A) + $6ED9EBA1 + W[23]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (C xor D xor E) + $6ED9EBA1 + W[24]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + (B xor C xor D) + $6ED9EBA1 + W[25]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (A xor B xor C) + $6ED9EBA1 + W[26]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (E xor A xor B) + $6ED9EBA1 + W[27]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (D xor E xor A) + $6ED9EBA1 + W[28]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (C xor D xor E) + $6ED9EBA1 + W[29]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + (B xor C xor D) + $6ED9EBA1 + W[30]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (A xor B xor C) + $6ED9EBA1 + W[31]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (E xor A xor B) + $6ED9EBA1 + W[32]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (D xor E xor A) + $6ED9EBA1 + W[33]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (C xor D xor E) + $6ED9EBA1 + W[34]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + (B xor C xor D) + $6ED9EBA1 + W[35]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (A xor B xor C) + $6ED9EBA1 + W[36]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (E xor A xor B) + $6ED9EBA1 + W[37]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (D xor E xor A) + $6ED9EBA1 + W[38]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (C xor D xor E) + $6ED9EBA1 + W[39]); C:= (C shl 30) or (C shr 2);

  Inc(E,((A shl 5) or (A shr 27)) + ((B and C) or (D and (B or C))) + $8F1BBCDC + W[40]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + ((A and B) or (C and (A or B))) + $8F1BBCDC + W[41]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + ((E and A) or (B and (E or A))) + $8F1BBCDC + W[42]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + ((D and E) or (A and (D or E))) + $8F1BBCDC + W[43]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + ((C and D) or (E and (C or D))) + $8F1BBCDC + W[44]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + ((B and C) or (D and (B or C))) + $8F1BBCDC + W[45]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + ((A and B) or (C and (A or B))) + $8F1BBCDC + W[46]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + ((E and A) or (B and (E or A))) + $8F1BBCDC + W[47]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + ((D and E) or (A and (D or E))) + $8F1BBCDC + W[48]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + ((C and D) or (E and (C or D))) + $8F1BBCDC + W[49]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + ((B and C) or (D and (B or C))) + $8F1BBCDC + W[50]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + ((A and B) or (C and (A or B))) + $8F1BBCDC + W[51]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + ((E and A) or (B and (E or A))) + $8F1BBCDC + W[52]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + ((D and E) or (A and (D or E))) + $8F1BBCDC + W[53]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + ((C and D) or (E and (C or D))) + $8F1BBCDC + W[54]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + ((B and C) or (D and (B or C))) + $8F1BBCDC + W[55]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + ((A and B) or (C and (A or B))) + $8F1BBCDC + W[56]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + ((E and A) or (B and (E or A))) + $8F1BBCDC + W[57]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + ((D and E) or (A and (D or E))) + $8F1BBCDC + W[58]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + ((C and D) or (E and (C or D))) + $8F1BBCDC + W[59]); C:= (C shl 30) or (C shr 2);

  Inc(E,((A shl 5) or (A shr 27)) + (B xor C xor D) + $CA62C1D6 + W[60]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (A xor B xor C) + $CA62C1D6 + W[61]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (E xor A xor B) + $CA62C1D6 + W[62]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (D xor E xor A) + $CA62C1D6 + W[63]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (C xor D xor E) + $CA62C1D6 + W[64]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + (B xor C xor D) + $CA62C1D6 + W[65]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (A xor B xor C) + $CA62C1D6 + W[66]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (E xor A xor B) + $CA62C1D6 + W[67]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (D xor E xor A) + $CA62C1D6 + W[68]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (C xor D xor E) + $CA62C1D6 + W[69]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + (B xor C xor D) + $CA62C1D6 + W[70]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (A xor B xor C) + $CA62C1D6 + W[71]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (E xor A xor B) + $CA62C1D6 + W[72]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (D xor E xor A) + $CA62C1D6 + W[73]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (C xor D xor E) + $CA62C1D6 + W[74]); C:= (C shl 30) or (C shr 2);
  Inc(E,((A shl 5) or (A shr 27)) + (B xor C xor D) + $CA62C1D6 + W[75]); B:= (B shl 30) or (B shr 2);
  Inc(D,((E shl 5) or (E shr 27)) + (A xor B xor C) + $CA62C1D6 + W[76]); A:= (A shl 30) or (A shr 2);
  Inc(C,((D shl 5) or (D shr 27)) + (E xor A xor B) + $CA62C1D6 + W[77]); E:= (E shl 30) or (E shr 2);
  Inc(B,((C shl 5) or (C shr 27)) + (D xor E xor A) + $CA62C1D6 + W[78]); D:= (D shl 30) or (D shr 2);
  Inc(A,((B shl 5) or (B shr 27)) + (C xor D xor E) + $CA62C1D6 + W[79]); C:= (C shl 30) or (C shr 2);

  Inc(Context[0], A);
  Inc(Context[1], B);
  Inc(Context[2], C);
  Inc(Context[3], D);
  Inc(Context[4], E);
  FillChar(HashBuffer, Sizeof(HashBuffer), 0);
end;

procedure TSHA1.Update(const Value: XString);
begin
  Update(@Value.UnsafeS[Value.Offset], Value.Length);
end;

procedure TSHA1.Update(PBuf: PByte; Size: UInt32);
begin
  Inc(LenHi, Size shr 29);
  Inc(LenLo, Size*8);
  if LenLo < (Size*8) then
    Inc(LenHi);
  while Size > 0 do
  begin
    if (Sizeof(HashBuffer)-Index) <= UInt32(Size) then
    begin
      Move(PBuf^, HashBuffer[Index], Sizeof(HashBuffer)-Index);
      Dec(Size, Sizeof(HashBuffer)-Index);
      Inc(PBuf, Sizeof(HashBuffer)-Index);
      Compress;
    end else
    begin
      Move(PBuf^, HashBuffer[Index], Size);
      Inc(Index, Size);
      Size := 0;
    end;
  end;
end;

procedure TSHA1.Final;
begin
  HashBuffer[Index]:= $80;
  if Index >= 56 then
    Compress;
  PUInt32(@HashBuffer[56])^ := SwapDWORD(LenHi);
  PUInt32(@HashBuffer[60])^ := SwapDWORD(LenLo);
  Compress;
  Context[0] := SwapDWord(Context[0]);
  Context[1] := SwapDWord(Context[1]);
  Context[2] := SwapDWord(Context[2]);
  Context[3] := SwapDWord(Context[3]);
  Context[4] := SwapDWord(Context[4]);
  Move(Context, Digest, Sizeof(Context));
end;

// @Result[64] 40 should be enough
procedure SHA1Base64(const Value: XString; var Result: XString);
var
  S: XString;
  SHA1: TSHA1;
begin
  SHA1.Init;
  SHA1.Update(Value);
  SHA1.Final;
  _XStringFromVarOffset(S, @SHA1.Digest[0], 0, SizeOf(SHA1.Digest), SizeOf(SHA1.Digest));
  XStringEncodeBase64(S, Result, False, False, True);
end;

//------------------------------------------------------------------------------
// TWebSocket
//------------------------------------------------------------------------------

constructor TWebSocket.Create;
begin
  inherited;
  XBufferCreate(Self.BufferRead, Self.Heap, 1024);
  XBufferCreate(Self.BufferReadPending, Self.Heap, 1024);
end;

destructor TWebSocket.Destroy;
begin
  XBufferFree(Self.BufferRead);
  XBufferFree(Self.BufferReadPending);
  inherited;
end;

function TWebSocket.Receive(var Buffer: TXBuffer): Integer;
var
  ReceivedBytes: Int32;
begin
  Result := 0;
  while True do
  begin
    ReceivedBytes := SysSocketRecv(Self.Socket, @Buffer.Buf[Buffer.Size], Buffer.Capacity-Buffer.Size, 0);
    if ReceivedBytes = 0 then
      Break;
    Inc(Result, ReceivedBytes);
    Inc(Buffer.Size, ReceivedBytes);
  end;
end;

procedure TWebSocket.Send(const Buffer: TXBuffer);
begin
  SysSocketSend(Self.Socket, @Buffer.Buf[0], Buffer.Size, 0);
end;

// @Code=1 to send text message
procedure TWebSocket.SendMessage(const Code: Byte; const Msg: XString);
var
  Buffer: TXBuffer;
  Buf1K: TXBuffer1K;
  Length8: Byte;
  Length16: Word;
  Length64: UInt64;
  OpCode: Byte;
begin
  OpCode := $80 or Code; // Text message
  XBufferFromVar(Buffer, @Buf1K, SizeOf(Buf1K), nil);
  XBufferAppend(Buffer, OpCode, SizeOf(OpCode));
  if Msg.Length <= 125 then
  begin
    Length8 := Msg.Length;
    XBufferAppend(Buffer, Length8, SizeOf(Length8));
  end else if Msg.Length <= 64*1024 then
  begin
    Length8 := 126;
    XBufferAppend(Buffer, Length8, SizeOf(Length8));
    Length16 := UInt16ToNetwork(Msg.Length);
    XBufferAppend(Buffer, Length16, SizeOf(Length16));
  end else
  begin
    Length8 := 127;
    XBufferAppend(Buffer, Length8, SizeOf(Length8));
    Length64 := UInt32ToNetwork(Msg.Length);
    XBufferAppend(Buffer, Length64, SizeOf(Length64));
  end;
  XBufferAppend(Buffer, Msg);
  {$IFDEF DebugWebSockets} WriteDebug('SendMessage - Socket #%h Size: %d\n', [PtrUInt(Self.Socket), Buffer.Size]); {$ENDIF}
  Send(Buffer);
end;

var
  WebSockets: PSocket;

procedure InitNetworkService(var Handler: TNetworkHandler; DoInit: TInitProc; DoAccept, DoReceive, DoClose, DoTimeOut: TSocketProc);
begin
  Handler.DoInit := DoInit;
  Handler.DoAccept := DoAccept;
  Handler.DoReceive := DoReceive;
  Handler.DoClose := DoClose;
  Handler.DoTimeOut := DoTimeOut;
end;

procedure WebSocketsInit;
begin
  WebSockets := SysSocket(SOCKET_STREAM);
  WebSockets.SourcePort := WEBSOCKET_PORT;
  SysSocketListen(WebSockets, 100);
end;

function WebSocketsAccept(Socket: PSocket): LongInt;
var
  WebSocket: TWebSocket;
begin
  {$IFDEF DebugWebSockets} WriteDebug('WebSocketsAccept...', []); {$ENDIF}
  WebSocket := XObjCreate(TWebSocket, nil);
  WebSocket.Socket := Socket;
  Socket.UserDefined := WebSocket;
  WebSocket.State := wsHandshake;
  XListAdd(ListWebSockets, WebSocket);
  WriteConsoleF('WebSocketsAccept - ListWebSockets.Count: %d\n', [ListWebSockets.Count]);
  SysSocketSelect(Socket, WEBSOCKET_TIMEOUT);
  {$IFDEF DebugWebSockets} WriteDebug('WebSocketsAccept - ListWebSockets.Count: %d\n', [ListWebSockets.Count]); {$ENDIF}
  Result := 0;
end;

procedure CloseWebSocket(Socket: PSocket);
var
  WebSocket: TWebSocket;
begin
  {$IFDEF DebugWebSockets} WriteDebug('CloseWebSocket: Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
  WebSocket := Socket.UserDefined;
  XListRemove(ListWebSockets, WebSocket);
  {$IFDEF DebugWebSockets} WriteDebug('CloseWebSocket - ListWebSockets.Count: %d\n', [ListWebSockets.Count]); {$ENDIF}
  WebSocket.Free;
  Socket.UserDefined := nil;
  {$IFDEF DebugWebSockets} WriteDebug('CloseWebSocket - SysSocketClose...\n', []); {$ENDIF}
  SysSocketClose(Socket);
  WriteConsoleF('CloseWebSocket - ListWebSockets.Count: %d\n', [ListWebSockets.Count]);
end;

function WebSocketsClose(Socket: PSocket): LongInt;
begin
  {$IFDEF DebugWebSockets} WriteDebug('WebSocketsClose: Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
  CloseWebSocket(Socket);
  Result := 0;
end;

type
  TSmileys = array[1..3] of UInt32;
var
  Smileys: TSmileys;

procedure WebSocketsBroadcast(const S: XString);
var
  I: Integer;
  WebSocket: TWebSocket;
begin
  WriteConsoleF('WebSocketsBroadcast - ListWebSockets.Count: %d\n', [ListWebSockets.Count]);
  for I := 0 to ListWebSockets.Count-1 do
  begin
    WebSocket := ListWebSockets.Items[I];
    WebSocket.SendMessage(1, S);
    WriteConsoleF('%d\n', [I]);
  end;
  WriteConsoleF('WebSocketsBroadcast - Done\n', []);
end;

procedure DoMessageReceived(WebSocket: TWebSocket; const Msg: XString);
var
  I: Integer;
  SmileyIndex: Integer;
  S: XString;
  SBuf: TXBuffer256;
begin
  {$IFDEF DebugWebSockets} WriteDebug('DoMessageReceived...\n', []); {$ENDIF}
  SmileyIndex := XStringToIntDef(Msg, -1); // 0 means initial refresh
  if (SmileyIndex < 0) or (SmileyIndex > 3) then
  begin
    WriteConsoleF('Invalid index: ', []);
    WriteConsoleF(_VclString(Msg), []);
    WriteConsoleF('\n', []);
    Exit;
  end;
{  if Self.SmileysDate <> ServerDate then
  begin // Reset counter everyday
    FillChar(Self.Smileys, SizeOf(Smileys), 0);
    Self.SmileysDate := ServerDate;
  end;
}
  if SmileyIndex <> 0 then
    Inc(Smileys[SmileyIndex]);
  _XString256(S, SBuf);
  XAppend(S, '{'#13#10'  "Action": "Update"');
  for I := 1 to 3 do
  begin
    XAppend(S, ','#13#10'  "Counter');
    IntToXStringAppend(I, S, 0);
    XAppend(S, '": "');
    IntToXStringAppend(Smileys[I], S, 0);
    XAppend(S, '"');
  end;
  XAppend(S, #13#10'}');
  if SmileyIndex = 0 then
    WebSocket.SendMessage(1, S)
  else
    WebSocketsBroadcast(S);
  {$IFDEF DebugWebSockets} WriteDebug('DoMessageReceived Done.\n', []); {$ENDIF}
end;


type
{
TFrameHeader = packed record
    OpCode: Byte;
    PayloadLength: Byte;
    case Byte of
      0: (LengthW: Word);
      1: (Length: UInt64);
  end;
}
//PFrameHeader = ^TFrameHeader;
  TUInt32Array = array[0..1024] of UInt32;
  PUInt32Array = ^TUInt32Array;

procedure DecodePayload(Buffer: TXBuffer; Mask: UInt32; const Length: Int32);
var
  I, Count: Int32;
  P: PUInt32Array;
  PB: PByteBuffer;
begin
  P := @Buffer.Buf[Buffer.Position];
  PB := Pointer(P);
  Count := Length div 4;
  for I := 0 to Count-1 do
    P[I] := P[I] xor Mask;
  for I := Count*4 to Length-1 do
  begin // up to the last remaining 3 bytes
    PB[I] := PB[I] xor Mask;
    Mask := Mask shr 8;
  end;
end;

function WebSocketsReceive(Socket: PSocket): LongInt;
const
  SALT: XString = (UnsafeS: '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'; Offset: 0; Length: 36; Capacity: 37);
  _CRLFCRLF: XString = (UnsafeS: #13#10#13#10; Offset: 0; Length: 4; Capacity: 5);

  procedure GetHeader(const Headers, HeaderName: XString; var HeaderValue: XString);
  var
    Index: Int32;
    Line, Name: XString;
  begin
    Index := 1;
    while TextFetch(Headers, Index, Line) do
    begin
      Split(Line, XChar(':'), Name, HeaderValue);
      if XEqual(Name, HeaderName) then
      begin
        XTrim(Headervalue);
        Exit;
      end;
    end;
    HeaderValue.Length := 0;
  end;

  procedure ReceiveHandshake(WebSocket: TWebSocket);
  var
    Content: XString;
    Digest: XString;
    DigestBuf: TXBuffer64;
    Handshake: XString;
    HandshakeBuf: TXBuffer128;
    Headers: XString;
    IndexContent: Int32;
    Response: TXBuffer;
    ResponseBuf: TXBuffer1K;
    SKey: XString;
  begin
    {$IFDEF DebugWebSockets} WriteDebug('ReceiveHandshake\n',[]); {$ENDIF}
    WebSocket.Receive(WebSocket.BufferRead);
    {$IFDEF DebugWebSockets} WriteDebug('WebSocket.Receive OK\n',[]); {$ENDIF}
    Headers := WebSocket.BufferRead.AsString;
    {$IFDEF DebugWebSockets}
      WriteDebug('ReceiveHandshake Headers: ', []);
      WriteDebug(_VclString(Headers), []);
      WriteDebug('\n', []);
    {$ENDIF}
    IndexContent := XPos(_CRLFCRLF, Headers, 0);
    if IndexContent = 0 then
    begin
      {$IFDEF DebugWebSockets} WriteDebug('IndexContent = 0\n',[]); {$ENDIF}
      SysSocketSelect(Socket, WEBSOCKET_TIMEOUT); // Incomplete Read
      Exit;
    end;
    _XStringEnd(Headers, IndexContent+4, Content);
    Headers.Length := IndexContent-1;
    XBufferFromVar(Response, @ResponseBuf, SizeOf(ResponseBuf), nil);
    try
      GetHeader(Headers, 'Sec-WebSocket-Key', SKey);
      {$IFDEF DebugWebSockets}
        WriteDebug('Sec-WebSocket-Key: ', []);
        WriteDebug(_VclString(SKey), []);
        WriteDebug('\n', []);
      {$ENDIF}
      _XString128(Handshake, HandshakeBuf);
      XAppend(Handshake, SKey);
      XAppend(Handshake, SALT);
      _XString64(Digest, DigestBuf);
      SHA1Base64(Handshake, Digest);
      XBufferAppend(Response, 'HTTP/1.1'); // HTTP/1.1
      XBufferAppend(Response, ' 101 Switching Protocols'#13#10);
      XBufferAppend(Response, 'Upgrade: websocket'#13#10);
      XBufferAppend(Response, 'Connection: Upgrade'#13#10);
      XBufferAppend(Response, 'Sec-WebSocket-Accept: ');
      XBufferAppend(Response, Digest);
      XBufferAppend(Response, #13, #10);
//        XBufferAppend(Response, 'Sec-WebSocket-Origin: ');
//        XBufferAppend(Response, Headers.Values2['Origin']);
//        XBufferAppend(Response, #13, #10);
      XBufferAppend(Response, #13, #10);
      WebSocket.Send(Response);
      WebSocket.State := wsReady;
      XBufferClear(WebSocket.BufferRead);
    finally
      XBufferFree(Response);
    end;
  end;

  procedure SendPong(WebSocket: TWebSocket; const Msg: XString);
  var
    MsgPong: XString;
  begin
    MsgPong := Msg; // reply pong with payload provided by ping
    WebSocket.SendMessage(10, MsgPong);
  end;

  procedure ReceiveMessage(WebSocket: TWebSocket);
  var
    FIN: Byte;
    LastPosition: Int32;
    Length: Int32;
    Length8: Byte;
    Length16: Word;
    Length64: UInt64;
    Masked: Byte;
    Mask: UInt32;
    Msg: XString;
    OpCode: Byte;
  begin
    {$IFDEF DebugWebSockets} WriteDebug('ReceiveMessage - Socket #%h\n', [PtrUInt(WebSocket.Socket)]); {$ENDIF}
    if WebSocket.BufferReadPending.Size > 0 then
    begin
      {$IFDEF DebugWebSockets} WriteDebug('Append BufferReadPending Size: %d\n', [WebSocket.BufferReadPending.Size]); {$ENDIF}
      XBufferAppend(WebSocket.BufferRead, WebSocket.BufferReadPending);
      XBufferClear(WebSocket.BufferReadPending);
    end;
    WebSocket.Receive(WebSocket.BufferRead);
    {$IFDEF DebugWebSockets} WriteDebug('BufferRead Size: %d\n', [WebSocket.BufferRead.Size]); {$ENDIF}
    if WebSocket.BufferRead.Size = 0 then
    begin
      SysSocketSelect(Socket, WEBSOCKET_TIMEOUT); // Incomplete Read
      Exit;
    end;
    WebSocket.BufferRead.Position := 0;
    try
      while WebSocket.BufferRead.Position < WebSocket.BufferRead.Size do
      begin // process multiple messages queued in BufferMsgRead
        {$IFDEF DebugWebSockets} WriteDebug('BufferRead Position: %d / Size: %d\n', [WebSocket.BufferRead.Position, WebSocket.BufferRead.Size]); {$ENDIF}
        LastPosition := WebSocket.BufferRead.Position;
        XBufferRead(WebSocket.BufferRead, OpCode, SizeOf(OpCode));
        {$IFDEF DebugWebSockets} WriteDebug('OpCode: %d\n', [OpCode]); {$ENDIF}
        FIN := OpCode and $80; // 1=lastmessage
        OpCode := OpCode and $F; // 0=Continuation 1=Text 2=Binary
        XBufferRead(WebSocket.BufferRead, Length8, SizeOf(Length8));
        Masked := Length8 and $80;
        if Masked = 0 then
        begin // Invalid Masked bit -> Disconnect client
          {$IFDEF DebugWebSockets} WriteDebug('Invalid Masked bit -> Disconnect client\n', []); {$ENDIF}
          CloseWebSocket(WebSocket.Socket);
          Exit;
        end;
        Length8 := Length8 and $7F;
        WriteDebug('Length8: %d\n', [Length8]);
        if Length8 = 126 then
        begin
          XBufferRead(WebSocket.BufferRead, Length16, SizeOf(Length16));
          Length := Length16;
        end else if Length8 = 127 then
        begin
          XBufferRead(WebSocket.BufferRead, Length64, SizeOf(Length64));
          Length := Length64;
        end else
          Length := Length8;
        if WebSocket.BufferRead.Size < WebSocket.BufferRead.Position+Length then
        begin
          {$IFDEF DebugWebSockets} WriteDebug('Incomplete Read: %d < %d+%d\n', [WebSocket.BufferRead.Size, WebSocket.BufferRead.Position, Length]); {$ENDIF}
          WebSocket.BufferRead.Position := LastPosition;
          XBufferAppendFromPosition(WebSocket.BufferReadPending, WebSocket.BufferRead);
          SysSocketSelect(Socket, WEBSOCKET_TIMEOUT); // Incomplete Read
          Exit;
        end;
        XBufferRead(WebSocket.BufferRead, Mask, SizeOf(Mask));
        DecodePayload(WebSocket.BufferRead, Mask, Length);
        if OpCode = 0 then
        begin // TODO: concatenate Payload and wait for next payload
          {$IFDEF DebugWebSockets} WriteDebug('ReceiveMessage - OpCode=0 -> Exit\n', []); {$ENDIF}
          SysSocketSelect(Socket, WEBSOCKET_TIMEOUT); // Incomplete read
          Exit;
        end else if FIN <> $80 then
        begin // TODO: concatenate Payload and wait for next payload
          {$IFDEF DebugWebSockets} WriteDebug('ReceiveMessage - FIN!=$80 (sould concat payload) -> Exit\n', []); {$ENDIF}
          SysSocketSelect(Socket, WEBSOCKET_TIMEOUT); // Incomplete read
          Exit;
        end;
        if OpCode = 8 then
        begin // ConnectionClose
          {$IFDEF DebugWebSockets} WriteDebug('ReceiveMessage - OpCode=8 -> ConnectionClose\n', []); {$ENDIF}
          CloseWebSocket(WebSocket.Socket);
          Exit;
        end;
        Msg := XBufferGetXStringIndex(WebSocket.BufferRead, WebSocket.BufferRead.Position, Length);
        Inc(WebSocket.BufferRead.Position, Length);
        if OpCode = 9 then
        begin // Ping
          {$IFDEF DebugWebSockets} WriteDebug('ReceiveMessage - OpCode=9 -> Ping respond with Pong\n', []); {$ENDIF}
          SendPong(WebSocket, Msg);
          SysSocketSelect(Socket, WEBSOCKET_TIMEOUT); // DISP_WAITING
        end else if OpCode = 10 then
        begin // Server may receive a pong -> simply ignore
          WriteConsoleF('ReceiveMessage - OpCode=10 -> Pong received\n', []);
          SysSocketSelect(Socket, WEBSOCKET_TIMEOUT); // DISP_WAITING
          Continue;
        end else
        begin
          {$IFDEF DebugWebSockets} WriteDebug('ReceiveMessage - OpCode=9 -> Ping respond with Pong\n', []); {$ENDIF}
          WriteConsoleF('WebSocketsReceive - DoMessageReceived ', []);
          WriteConsoleF(_VclString(Msg), []);
          WriteConsoleF('\n', []);
          DoMessageReceived(WebSocket, Msg);
          SysSocketSelect(Socket, WEBSOCKET_TIMEOUT); // DISP_WAITING
        end;
      end;
    finally
      XBufferClear(WebSocket.BufferRead);
    end;
  end;

var
  WebSocket: TWebSocket;
begin
  Result := 0;
  WebSocket := Socket.UserDefined;
  if WebSocket.State = wsHandshake then
    ReceiveHandshake(WebSocket)
  else
    ReceiveMessage(WebSocket);
end;

function WebSocketsTimeOut(Socket: PSocket): LongInt;
begin
  {$IFDEF DebugWebSockets} WriteDebug('WebSocketsTimeOut: Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
  CloseWebSocket(Socket);
  Result := 0;
end;

var
  WebSocketsHandler: TNetworkHandler;

procedure WebSocketsCreate;
begin
  if ListWebSockets.Items <> nil then
    Exit;
  XListCreate(ListWebSockets, nil, 128);
  InitNetworkService(WebSocketsHandler, WebSocketsInit, WebSocketsAccept, WebSocketsReceive, WebSocketsClose, WebSocketsTimeOut);
  SysRegisterNetworkService(@WebSocketsHandler);
  WriteConsoleF('\t /VWebSockets/n: listening on port %d ...\n', [WEBSOCKET_PORT]);
end;

procedure WebSocketsFree;
begin
  XListFree(ListWebSockets);
end;

finalization
  WebSocketsFree;

end.

