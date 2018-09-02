{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
    All Rights Reserved     
    
    System unit for Toro.
    
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

unit System;

interface

{$DEFINE FPC_IS_SYSTEM}
{$inline on}
{$macro on}
{$asmmode intel}
{$I Toro.inc}

{$I-,Q-,H-,R-,V-}
{$mode objfpc}

{ Using inlining for small system functions/wrappers }
{$inline on}
{$ifdef COMPPROCINLINEFIXED}
{$define SYSTEMINLINE}
{$endif COMPPROCINLINEFIXED}

{ needed for insert,delete,readln }
{$P+}
{ stack checking always disabled
  for system unit. This is because
  the startup code might not
  have been called yet when we
  get a stack error, this will
  cause big crashes
}
{$S-}

{****************************************************************************
                         Global Types and Constants
****************************************************************************}

type
  { The compiler has all integer types defined internally. Here we define only aliases }
  DWORD    = LongWord;
  Cardinal = LongWord;
  Integer  = SmallInt;


  {$define DEFAULT_DOUBLE}
  ValReal = Double;

  { map comp to int64, but this doesn't mean we compile the comp support in! }
  {$ifndef Linux}
   Comp = Int64;
  {$endif Linux}

  PComp = ^Comp;

  {$define SUPPORT_SINGLE}
  {$define SUPPORT_DOUBLE}

  SizeInt = Int64;
  SizeUInt = QWord;
  PtrInt = Int64;
  PtrUInt = QWord;
  ValSInt = Int64;
  ValUInt = QWord;

{ Zero - terminated strings }
  PChar               = ^Char;
  PPChar              = ^PChar;

  { AnsiChar is equivalent of Char, so we need
    to use type renamings }
  TAnsiChar           = Char;
  AnsiChar            = Char;
  PAnsiChar           = PChar;
  PPAnsiChar          = PPChar;

  RawByteString = AnsiString;
  TSystemCodePage = Word;
  
  
  UTF8String          = type ansistring;
  PUTF8String         = ^UTF8String;

  HRESULT             = type Longint;
  TDateTime           = type Int64;
  Error               = type Longint;

  PSingle             = ^Single;
  PDouble             = ^Double;
  PCurrency           = ^Currency;
  PExtended           = ^Extended;

  PSmallInt           = ^Smallint;
  PShortInt           = ^Shortint;
  PInteger            = ^Integer;
  PByte               = ^Byte;
  PWord               = ^word;
  PDWord              = ^DWord;
  PLongWord           = ^LongWord;
  PLongint            = ^Longint;
  PCardinal           = ^Cardinal;
  PQWord              = ^QWord;
  PInt64              = ^Int64;
  PPtrInt             = ^PtrInt;
  PSizeInt            = ^SizeInt;

  PPointer            = ^Pointer;
  PPPointer           = ^PPointer;

  PBoolean            = ^Boolean;
  PWordBool           = ^WordBool;
  PLongBool           = ^LongBool;

  PShortString        = ^ShortString;
  PAnsiString         = ^AnsiString;

  PDate               = ^TDateTime;
  PError              = ^Error;
  PVariant            = ^Variant;
  POleVariant         = ^OleVariant;

  TTextLineBreakStyle = (tlbsLF,tlbsCRLF,tlbsCR);

  LARGE_INTEGER = record
    case byte of
      0: (LowPart : DWORD;
          HighPart : DWORD);
      1: (QuadPart : QWORD);
  end;

   TSystemTime = record
      wYear, wMonth, wDay, wDayOfWeek : word;
      wHour, wMinute, wSecond, wMilliSecond: word;
   end ;

  TFileTime = record
    dwLowDateTime,
    dwHighDateTime : DWORD;
  end;

{ procedure type }
  TProcedure  = Procedure;

  FILEREC = record end;
  TEXTREC = record end;

type
  THandle = QWord;
  TThreadID = THandle;
  
  PRTLCriticalSection = ^TRTLCriticalSection;
  TRTLCriticalSection = record
 		Short: Boolean;
 		Flag: QWORD;
    lock_tail: Pointer; // pointer on the Thread
  end;

const
{ Maximum value of the biggest signed and unsigned integer type available}
  MaxSIntValue = High(ValSInt);
  MaxUIntValue = High(ValUInt);

{ max. values for longint and int}
  maxLongint  = $7fffffff;
  maxSmallint = 32767;

  maxint   = maxsmallint;

type
  IntegerArray  = array[0..$effffff] of Integer;
  PIntegerArray = ^IntegerArray;
  PointerArray = array [0..512*1024*1024 - 2] of Pointer;
  PPointerArray = ^PointerArray;

  TBoundArray = array of SizeInt;

  TPCharArray = packed array[0..(MaxLongint div SizeOf(PChar))-1] of PChar;
  PPCharArray = ^TPCharArray;

const
{ max level in dumping on error }
  Max_Frame_Dump : Word = 8;

{ Exit Procedure handling consts and types  }
  ExitProc : pointer = nil;
  Erroraddr: pointer = nil;
  Errorcode: Word    = 0;

  { Indicates if there was an error }
  StackError : boolean = FALSE;
  InitProc : Pointer = nil;

var
  ExitCode: Word; public name 'operatingsystem_result';
  RandSeed: Cardinal;
  { Threading support }
  fpc_threadvar_relocate_proc: pointer; public name 'FPC_THREADVAR_RELOCATE';
  emptyintf: pointer; public name 'FPC_EMPTYINTF';

ThreadVar
  ThreadID: TThreadID;
  InOutRes: Word;
  { Stack checking }
  StackTop,
  StackBottom: Pointer;
  StackLength: SizeUInt;


const
{ Internal functions }
   fpc_in_lo_word           = 1;
   fpc_in_hi_word           = 2;
   fpc_in_lo_long           = 3;
   fpc_in_hi_long           = 4;
   fpc_in_ord_x             = 5;
   fpc_in_length_string     = 6;
   fpc_in_chr_byte          = 7;
   fpc_in_write_x           = 14;
   fpc_in_writeln_x         = 15;
   fpc_in_read_x            = 16;
   fpc_in_readln_x          = 17;
   fpc_in_concat_x          = 18;
   fpc_in_assigned_x        = 19;
   fpc_in_str_x_string      = 20;
   fpc_in_ofs_x             = 21;
   fpc_in_sizeof_x          = 22;
   fpc_in_typeof_x          = 23;
   fpc_in_val_x             = 24;
   fpc_in_reset_x           = 25;
   fpc_in_rewrite_x         = 26;
   fpc_in_low_x             = 27;
   fpc_in_high_x            = 28;
   fpc_in_seg_x             = 29;
   fpc_in_pred_x            = 30;
   fpc_in_succ_x            = 31;
   fpc_in_reset_typedfile   = 32;
   fpc_in_rewrite_typedfile = 33;
   fpc_in_settextbuf_file_x = 34;
   fpc_in_inc_x             = 35;
   fpc_in_dec_x             = 36;
   fpc_in_include_x_y       = 37;
   fpc_in_exclude_x_y       = 38;
   fpc_in_break             = 39;
   fpc_in_continue          = 40;
   fpc_in_assert_x_y        = 41;
   fpc_in_addr_x            = 42;
   fpc_in_typeinfo_x        = 43;
   fpc_in_setlength_x       = 44;
   fpc_in_finalize_x        = 45;
   fpc_in_new_x             = 46;
   fpc_in_dispose_x         = 47;
   fpc_in_exit              = 48;
   fpc_in_copy_x            = 49;
   fpc_in_initialize_x      = 50;
   fpc_in_leave             = 51; {macpas}
   fpc_in_cycle             = 52; {macpas}

{ Internal constant functions }
   fpc_in_const_sqr        = 100;
   fpc_in_const_abs        = 101;
   fpc_in_const_odd        = 102;
   fpc_in_const_ptr        = 103;
   fpc_in_const_swap_word  = 104;
   fpc_in_const_swap_long  = 105;
   fpc_in_lo_qword         = 106;
   fpc_in_hi_qword         = 107;
   fpc_in_const_swap_qword = 108;
   fpc_in_prefetch_var     = 109;

{ FPU functions }
   fpc_in_trunc_real       = 120;
   fpc_in_round_real       = 121;
   fpc_in_frac_real        = 122;
   fpc_in_int_real         = 123;
   fpc_in_exp_real         = 124;
   fpc_in_cos_real         = 125;
   fpc_in_pi_real          = 126;
   fpc_in_abs_real         = 127;
   fpc_in_sqr_real         = 128;
   fpc_in_sqrt_real        = 129;
   fpc_in_arctan_real      = 130;
   fpc_in_ln_real          = 131;
   fpc_in_sin_real         = 132;

{ MMX functions }
{ these contants are used by the mmx unit }

   { MMX }
   fpc_in_mmx_pcmpeqb      = 200;
   fpc_in_mmx_pcmpeqw      = 201;
   fpc_in_mmx_pcmpeqd      = 202;
   fpc_in_mmx_pcmpgtb      = 203;
   fpc_in_mmx_pcmpgtw      = 204;
   fpc_in_mmx_pcmpgtd      = 205;

   { 3DNow }

   { SSE }



{****************************************************************************
                        Processor specific routines
****************************************************************************}

Procedure Move(const source;var dest;count:SizeInt);{$ifdef INLINEGENERICS}inline;{$endif}
Procedure FillChar(Var x;count:SizeInt;Value:Boolean);{$ifdef SYSTEMINLINE}inline;{$endif}
Procedure FillChar(Var x;count:SizeInt;Value:Char);{$ifdef SYSTEMINLINE}inline;{$endif}
Procedure FillChar(Var x;count:SizeInt;Value:Byte);{$ifdef INLINEGENERICS}inline;{$endif}
procedure FillByte(var x;count:SizeInt;value:byte);{$ifdef INLINEGENERICS}inline;{$endif}
Procedure FillWord(Var x;count:SizeInt;Value:Word);
procedure FillDWord(var x;count:SizeInt;value:DWord);
function  IndexChar(const buf;len:SizeInt;b:char):SizeInt;
function  IndexByte(const buf;len:SizeInt;b:byte):SizeInt;{$ifdef INLINEGENERICS}inline;{$endif}
function  Indexword(const buf;len:SizeInt;b:word):SizeInt;
function  IndexDWord(const buf;len:SizeInt;b:DWord):SizeInt;
function  CompareChar(const buf1,buf2;len:SizeInt):SizeInt;
function  CompareByte(const buf1,buf2;len:SizeInt):SizeInt;{$ifdef INLINEGENERICS}inline;{$endif}
function  CompareWord(const buf1,buf2;len:SizeInt):SizeInt;
function  CompareDWord(const buf1,buf2;len:SizeInt):SizeInt;
procedure MoveChar0(const buf1;var buf2;len:SizeInt);
function  IndexChar0(const buf;len:SizeInt;b:char):SizeInt;
function  CompareChar0(const buf1,buf2;len:SizeInt):SizeInt;{$ifdef INLINEGENERICS}inline;{$endif}
procedure prefetch(const mem);[internproc:fpc_in_prefetch_var];


{****************************************************************************
                          Math Routines
****************************************************************************}

Function  lo(B: Byte):Byte;{$ifdef SYSTEMINLINE}inline;{$endif}
Function  hi(b : Byte) : Byte;{$ifdef SYSTEMINLINE}inline;{$endif}
Function  lo(i : Integer) : byte;  [INTERNPROC: fpc_in_lo_Word];
Function  lo(w : Word) : byte;     [INTERNPROC: fpc_in_lo_Word];
Function  lo(l : Longint) : Word;  [INTERNPROC: fpc_in_lo_long];
Function  lo(l : DWord) : Word;    [INTERNPROC: fpc_in_lo_long];
Function  lo(i : Int64) : DWord;   [INTERNPROC: fpc_in_lo_qword];
Function  lo(q : QWord) : DWord;   [INTERNPROC: fpc_in_lo_qword];
Function  hi(i : Integer) : byte;  [INTERNPROC: fpc_in_hi_Word];
Function  hi(w : Word) : byte;     [INTERNPROC: fpc_in_hi_Word];
Function  hi(l : Longint) : Word;  [INTERNPROC: fpc_in_hi_long];
Function  hi(l : DWord) : Word;    [INTERNPROC: fpc_in_hi_long];
Function  hi(i : Int64) : DWord;   [INTERNPROC: fpc_in_hi_qword];
Function  hi(q : QWord) : DWord;   [INTERNPROC: fpc_in_hi_qword];

Function swap (X : Word) : Word;{$ifdef SYSTEMINLINE}inline;{$endif}[internconst:fpc_in_const_swap_word];
Function Swap (X : Integer) : Integer;{$ifdef SYSTEMINLINE}inline;{$endif}[internconst:fpc_in_const_swap_word];
Function swap (X : Longint) : Longint;{$ifdef SYSTEMINLINE}inline;{$endif}[internconst:fpc_in_const_swap_long];
Function Swap (X : Cardinal) : Cardinal;{$ifdef SYSTEMINLINE}inline;{$endif}[internconst:fpc_in_const_swap_long];
Function Swap (X : QWord) : QWord;{$ifdef SYSTEMINLINE}inline;{$endif}[internconst:fpc_in_const_swap_qword];
Function swap (X : Int64) : Int64;{$ifdef SYSTEMINLINE}inline;{$endif}[internconst:fpc_in_const_swap_qword];

Function Align (Addr : PtrUInt; Alignment : PtrUInt) : PtrUInt;{$ifdef SYSTEMINLINE}inline;{$endif}
Function Align (Addr : Pointer; Alignment : PtrUInt) : Pointer;{$ifdef SYSTEMINLINE}inline;{$endif}

Function abs(l:Longint):Longint;[internconst:fpc_in_const_abs];{$ifdef SYSTEMINLINE}inline;{$endif}
Function abs(l:Int64):Int64;[internconst:fpc_in_const_abs];{$ifdef SYSTEMINLINE}inline;{$endif}
Function sqr(l:Longint):Longint;[internconst:fpc_in_const_sqr];{$ifdef SYSTEMINLINE}inline;{$endif}
Function sqr(l:Int64):Int64;[internconst:fpc_in_const_sqr];{$ifdef SYSTEMINLINE}inline;{$endif}
Function sqr(l:QWord):QWord;[internconst:fpc_in_const_sqr];{$ifdef SYSTEMINLINE}inline;{$endif}
Function odd(l:Longint):Boolean;[internconst:fpc_in_const_odd];{$ifdef SYSTEMINLINE}inline;{$endif}
Function odd(l:Longword):Boolean;[internconst:fpc_in_const_odd];{$ifdef SYSTEMINLINE}inline;{$endif}
Function odd(l:Int64):Boolean;[internconst:fpc_in_const_odd];{$ifdef SYSTEMINLINE}inline;{$endif}
Function odd(l:QWord):Boolean;[internconst:fpc_in_const_odd];{$ifdef SYSTEMINLINE}inline;{$endif}

{****************************************************************************
                      PChar and String Handling
****************************************************************************}

function strpas(p:pchar):shortstring;external name 'FPC_PCHAR_TO_SHORTSTR';
function strlen(p:pchar):longint;external name 'FPC_PCHAR_LENGTH';

{ Shortstring functions }
Function  Pos(const substr:shortstring;const s:shortstring):SizeInt;
Function  Pos(C:Char;const s:shortstring):SizeInt;
Function  Pos (Const Substr : ShortString; Const Source : AnsiString) : SizeInt;
//Procedure SetString (Var S : Shortstring; Buf : PChar; Len : SizeInt);
//Procedure SetString (Var S : AnsiString; Buf : PChar; Len : SizeInt);
Function  upCase(const s:shortstring):shortstring;
Function  lowerCase(const s:shortstring):shortstring; overload;
Function  Space(b:byte):shortstring;
Function  hexStr(Val:Longint;cnt:byte):shortstring;
Function  OctStr(Val:Longint;cnt:byte):shortstring;
Function  binStr(Val:Longint;cnt:byte):shortstring;
Function  hexStr(Val:int64;cnt:byte):shortstring;
Function  OctStr(Val:int64;cnt:byte):shortstring;
Function  binStr(Val:int64;cnt:byte):shortstring;
Function  hexStr(Val:Pointer):shortstring;
procedure InttoStr(Value: PtrUInt; buff: pchar);
procedure StrConcat(left, right, dst: pchar);
function StrCmp(p1, p2: pchar; Len: LongInt): Boolean;

{ Char functions }
Function chr(b : byte) : Char;      [INTERNPROC: fpc_in_chr_byte];
Function  upCase(c:Char):Char;
Function  lowerCase(c:Char):Char; overload;
function  pos(const substr : shortstring;c:char): SizeInt;


{****************************************************************************
                             AnsiString Handling
****************************************************************************}

Procedure UniqueString(Var S : AnsiString);external name 'FPC_ANSISTR_UNIQUE';
Function  Pos (Const Substr : AnsiString; Const Source : AnsiString) : SizeInt;
Function  Pos (c : Char; Const s : AnsiString) : SizeInt;
Procedure Insert (Const Source : AnsiString; Var S : AnsiString; Index : SizeInt);
Procedure Delete (Var S : AnsiString; Index,Size: SizeInt);
Function  StringOfChar(c : char;l : SizeInt) : AnsiString;
function  upcase(const s : ansistring) : ansistring;
function  lowercase(const s : ansistring) : ansistring;

{*****************************************************************************
                             Miscellaneous
*****************************************************************************}

{ os independent calls to allow backtraces }
function get_caller_addr(framebp:pointer):pointer;{$ifdef SYSTEMINLINE}inline;{$endif}
function get_caller_frame(framebp:pointer):pointer;{$ifdef SYSTEMINLINE}inline;{$endif}

Function IOResult: Word; {$ifdef SYSTEMINLINE}inline;{$endif}
Function Sptr: Pointer; {$ifdef SYSTEMINLINE}inline;{$endif}[internconst:fpc_in_const_ptr];
Function GetProcessID: SizeUInt;
Function GetThreadID: TThreadID; {$ifdef SYSTEMINLINE} inline; {$endif}


{*****************************************************************************
                          Init / Exit / ExitProc
*****************************************************************************}

Function  Paramcount:Longint;
Function  ParamStr(l:Longint):string;
Procedure Dump_Stack(var f : string; bp:pointer);
Procedure RunError(w:Word);
Procedure RunError;{$ifdef SYSTEMINLINE}inline;{$endif}
Procedure halt(errnum:byte);
Procedure AddExitProc(Proc:TProcedure);
Procedure System_exit; external name 'SYSTEMEXIT';

{ Need to be exported for threads unit }
Procedure SysInitExceptions;
procedure SysInitStdIO;

{*****************************************************************************
                         Abstract/Assert/Error Handling
*****************************************************************************}

procedure AbstractError;external name 'FPC_ABSTRACTERROR';
Function  SysBackTraceStr(Addr:Pointer): ShortString;
Procedure SysAssert(Const Msg,FName:ShortString;LineNo:Longint;ErrorAddr:Pointer);

{ Error handlers }
Type
  TBackTraceStrFunc = Function (Addr: Pointer): ShortString;
  TErrorProc = Procedure (ErrNo : Longint; Address,Frame : Pointer);
  TAbstractErrorProc = Procedure;
  TAssertErrorProc = Procedure(const msg,fname:ShortString;lineno:longint;erroraddr:pointer);



const
  BackTraceStrFunc  : TBackTraceStrFunc = @SysBackTraceStr;
  ErrorProc         : TErrorProc = nil;
  AbstractErrorProc : TAbstractErrorProc = nil;
  AssertErrorProc   : TAssertErrorProc = @SysAssert;


{*****************************************************************************
                          SetJmp/LongJmp
*****************************************************************************}


Type
  jmp_buf = packed record
    rbx,rbp,r12,r13,r14,r15,rsp,rip : qword; 
   end;
  PJmp_buf = ^jmp_buf;

Function fpc_setjmp (Var S : Jmp_buf) : longint; compilerproc;
Procedure fpc_longjmp (Var S : Jmp_buf; value : longint); compilerproc;



{*****************************************************************************
                            Basic Types/constants
*****************************************************************************}

const
   vmtInstanceSize         = 0;
   vmtParent               = sizeof(SizeInt)*2;
   { These were negative value's, but are now positive, else classes
     couldn't be used with shared linking which copies only all data from
     the .global directive and not the data before the directive (PFV) }
   vmtClassName            = vmtParent+sizeof(pointer);
   vmtDynamicTable         = vmtParent+sizeof(pointer)*2;
   vmtMethodTable          = vmtParent+sizeof(pointer)*3;
   vmtFieldTable           = vmtParent+sizeof(pointer)*4;
   vmtTypeInfo             = vmtParent+sizeof(pointer)*5;
   vmtInitTable            = vmtParent+sizeof(pointer)*6;
   vmtAutoTable            = vmtParent+sizeof(pointer)*7;
   vmtIntfTable            = vmtParent+sizeof(pointer)*8;
   vmtMsgStrPtr            = vmtParent+sizeof(pointer)*9;
   { methods }
   vmtMethodStart          = vmtParent+sizeof(pointer)*10;
   vmtDestroy              = vmtMethodStart;
   vmtNewInstance          = vmtMethodStart+sizeof(pointer);
   vmtFreeInstance         = vmtMethodStart+sizeof(pointer)*2;
   vmtSafeCallException    = vmtMethodStart+sizeof(pointer)*3;
   vmtDefaultHandler       = vmtMethodStart+sizeof(pointer)*4;
   vmtAfterConstruction    = vmtMethodStart+sizeof(pointer)*5;
   vmtBeforeDestruction    = vmtMethodStart+sizeof(pointer)*6;
   vmtDefaultHandlerStr    = vmtMethodStart+sizeof(pointer)*7;

   { IInterface }
   S_OK          = 0;
   S_FALSE       = 1;
   E_NOINTERFACE = hresult($80004002);
   E_UNEXPECTED  = hresult($8000FFFF);
   E_NOTIMPL     = hresult($80004001);

 type
   TextFile = Text;

   { now the let's declare the base classes for the class object }
   { model                                                       }
   TObject = class;
   TClass  = class of tobject;
   PClass  = ^tclass;


   { to access the message table from outside }
   TMsgStrTable = record
      name : pshortstring;
      method : pointer;
   end;

   PMsgStrTable = ^TMsgStrTable;

   TStringMessageTable = record
      count : dword;
      msgstrtable : array[0..0] of tmsgstrtable;
   end;

   pstringmessagetable = ^tstringmessagetable;

   PGuid = ^TGuid;
   TGuid = packed record
      case integer of
         1 : (
              Data1 : DWord;
              Data2 : word;
              Data3 : word;
              Data4 : array[0..7] of byte;
             );
         2 : (
              D1 : DWord;
              D2 : word;
              D3 : word;
              D4 : array[0..7] of byte;
             );
   end;

   pinterfaceentry = ^tinterfaceentry;
   tinterfaceentry = packed record
     IID: pguid; { if assigned(IID) then Com else Corba}
     VTable: Pointer;
     IOffset: DWord;
     IIDStr: pshortstring; { never nil. Com: upper(GuidToString(IID^)) }
   end;

   pinterfacetable = ^tinterfacetable;
   tinterfacetable = packed record
     EntryCount: Word;
     Entries: array[0..0] of tinterfaceentry;
   end;

   TMethod = record
     Code, Data : Pointer;
   end;

   TObject = class
   public
      { please don't change the order of virtual methods, because
        their vmt offsets are used by some assembler code which uses
        hard coded addresses      (FK)                                 }
      constructor Create;
      { the virtual procedures must be in THAT order }
      destructor Destroy;virtual;
      class function newinstance : tobject;virtual;
      procedure FreeInstance;virtual;
      function SafeCallException(exceptobject : tobject;
        exceptaddr : pointer) : longint;virtual;
      procedure DefaultHandler(var message);virtual;

      procedure Free;
      class function InitInstance(instance : pointer) : tobject;
      procedure CleanupInstance;
      class function ClassType : tclass;{$ifdef SYSTEMINLINE}inline;{$endif}
      class function ClassInfo : pointer;
      class function ClassName : shortstring;
      class function ClassNameIs(const name : string) : boolean;
      class function ClassParent : tclass;{$ifdef SYSTEMINLINE}inline;{$endif}
      class function InstanceSize : SizeInt;{$ifdef SYSTEMINLINE}inline;{$endif}
      class function InheritsFrom(aclass : tclass) : boolean;
      class function StringMessageTable : pstringmessagetable;
      { message handling routines }
      procedure Dispatch(var message);
      procedure DispatchStr(var message);

      class function MethodAddress(const name : shortstring) : pointer;
      class function MethodName(address : pointer) : shortstring;
      function FieldAddress(const name : shortstring) : pointer;

      { new since Delphi 4 }
      procedure AfterConstruction;virtual;
      procedure BeforeDestruction;virtual;

      { new for gtk, default handler for text based messages }
      procedure DefaultHandlerStr(var message);virtual;

      { interface functions }
      function GetInterface(const iid : tguid; out obj) : boolean;
      function GetInterfaceByStr(const iidstr : string; out obj) : boolean;
      class function GetInterfaceEntry(const iid : tguid) : pinterfaceentry;
      class function GetInterfaceEntryByStr(const iidstr : string) : pinterfaceentry;
      class function GetInterfaceTable : pinterfacetable;

      function Equals(Obj: TObject) : boolean;virtual;
      function GetHashCode: PtrInt;virtual;
      function ToString: {$ifdef FPC_HAS_FEATURE_ANSISTRINGS}ansistring{$else FPC_HAS_FEATURE_ANSISTRINGS}shortstring{$endif FPC_HAS_FEATURE_ANSISTRINGS};virtual;
   end;

   IUnknown = interface
     ['{00000000-0000-0000-C000-000000000046}']
     function QueryInterface(const iid : tguid;out obj) : longint;stdcall;
     function _AddRef : longint;stdcall;
     function _Release : longint;stdcall;
   end;
   IInterface = IUnknown;

   {$M+}
   {$M-}

   TExceptProc = Procedure (Obj : TObject; Addr : Pointer; FrameCount:Longint; Frame: PPointer);

   { Exception object stack }
   PExceptObject = ^TExceptObject;
   TExceptObject = record
     FObject    : TObject;
     Addr       : pointer;
     Next       : PExceptObject;
     refcount   : Longint;
     Framecount : Longint;
     Frames     : PPointer;
   end;

Const
   ExceptProc : TExceptProc = Nil;
   RaiseProc : TExceptProc = Nil;
   RaiseMaxFrameCount : Longint = 16;

Function RaiseList : PExceptObject;

{ @abstract(increase exception reference count)
  When leaving an except block, the exception object is normally
  freed automatically. To avoid this, call this function.
  If within the exception object you decide that you don't need
  the exception after all, call @link(ReleaseExceptionObject).
  Otherwise, if the reference count is > 0, the exception object
  goes into your "property" and you need to free it manually.
  The effect of this function is countered by re-raising an exception
  via "raise;", this zeroes the reference count again.
  Calling this method is only valid within an except block.
  @return(pointer to the exception object) }
function AcquireExceptionObject: Pointer;

{ @abstract(decrease exception reference count)
  After calling @link(AcquireExceptionObject) you can call this method
  to decrease the exception reference count again.
  If the reference count is > 0, the exception object
  goes into your "property" and you need to free it manually.
  Calling this method is only valid within an except block. }
procedure ReleaseExceptionObject;

{*****************************************************************************
                              Array of const support
*****************************************************************************}

const
  vtInteger    = 0;
  vtBoolean    = 1;
  vtChar       = 2;
  vtExtended   = 3;
  vtString     = 4;
  vtPointer    = 5;
  vtPChar      = 6;
  vtObject     = 7;
  vtClass      = 8;
  vtWideChar   = 9;
  vtPWideChar  = 10;
  vtAnsiString = 11;
  vtCurrency   = 12;
  vtVariant    = 13;
  vtInterface  = 14;
  vtWideString = 15;
  vtInt64      = 16;
  vtQWord      = 17;

type
  PVarRec = ^TVarRec;
  TVarRec = record
     case VType : Ptrint of
       vtInteger    : (VInteger: Longint);
       vtBoolean    : (VBoolean: Boolean);
       vtChar       : (VChar: Char);
       vtWideChar   : (VWideChar: WideChar);
       vtExtended   : (VExtended: PExtended);
       vtString     : (VString: PShortString);
       vtPointer    : (VPointer: Pointer);
       vtPChar      : (VPChar: PChar);
       vtObject     : (VObject: TObject);
       vtClass      : (VClass: TClass);
//           vtPWideChar  : (VPWideChar: PWideChar);
       vtAnsiString : (VAnsiString: Pointer);
       vtCurrency   : (VCurrency: PCurrency);
       vtVariant    : (VVariant: PVariant);
       vtInterface  : (VInterface: Pointer);
       vtWideString : (VWideString: Pointer);
       vtInt64      : (VInt64: PInt64);
       vtQWord      : (VQWord: PQWord);
   end;

const
   varempty = 0;
   varnull = 1;
   varsmallint = 2;
   varinteger = 3;
{$ifndef FPUNONE}
   varsingle = 4;
   vardouble = 5;
   vardate = 7;
{$endif}
   varcurrency = 6;
   varolestr = 8;
   vardispatch = 9;
   varerror = 10;
   varboolean = 11;
   varvariant = 12;
   varunknown = 13;
   vardecimal = 14;
   varshortint = 16;
   varbyte = 17;
   varword = 18;
   varlongword = 19;
   varint64 = 20;
   varqword = 21;

   varrecord = 36;

   { The following values never appear as TVarData.VType, but are used in
     TCallDesc.Args[] as aliases for compiler-specific types.
     (since it provides only 1 byte per element, actual values won't fit)
     The choice of values is pretty much arbitrary. }

   varstrarg = $48;         { maps to varstring }
   varustrarg = $49;        { maps to varustring }

   { Compiler-specific variant types (not known to COM) are kept in
    'pseudo-custom' range of $100-$10E. Real custom types start with $10F. }

   varstring = $100;
   varany = $101;
   varustring = $102;
   vartypemask = $fff;
   vararray = $2000;
   varbyref = $4000;

   varword64 = varqword;
   varuint64 = varqword; // Delphi alias

type
   tvartype = word;

   pvararrayboundarray = ^tvararrayboundarray;
   pvararraycoorarray = ^tvararraycoorarray;
   pvararraybound = ^tvararraybound;
   pvararray = ^tvararray;

   tvararraybound = record
     elementcount,lowbound  : longint;
   end;

   tvararrayboundarray = array[0..0] of tvararraybound;
   tvararraycoorarray = array[0..0] of Longint;

   tvararray = record
      dimcount,flags : word;
      elementsize : longint;
      lockcount : longint;
      data : pointer;
      bounds : tvararrayboundarray;
   end;


   tvarop = (opadd,opsubtract,opmultiply,opdivide,opintdivide,opmodulus,
             opshiftleft,opshiftright,opand,opor,opxor,opcompare,opnegate,
             opnot,opcmpeq,opcmpne,opcmplt,opcmple,opcmpgt,opcmpge,oppower);

   tvardata = packed record
      vtype : tvartype;
      case integer of
         0:(res1 : word;
            case integer of
               0:
                 (res2,res3 : word;
                  case word of
                     varsmallint : (vsmallint : smallint);
                     varinteger : (vinteger : longint);
{$ifndef FPUNONE}
                     varsingle : (vsingle : single);
                     vardouble : (vdouble : double);
                     vardate : (vdate : tdatetime);
{$endif}
                     varcurrency : (vcurrency : currency);
                     //varolestr : (volestr : pwidechar);
                     vardispatch : (vdispatch : pointer);
                     varerror : (verror : hresult);
                     varboolean : (vboolean : wordbool);
                     varunknown : (vunknown : pointer);
                     // vardecimal : ( : );
                     varshortint : (vshortint : shortint);
                     varbyte : (vbyte : byte);
                     varword : (vword : word);
                     varlongword : (vlongword : dword);
                     varint64 : (vint64 : int64);
                     varqword : (vqword : qword);
                     varword64 : (vword64 : qword);
                     varstring : (vstring : pointer);
                     varany :  (vany : pointer);
                     vararray : (varray : pvararray);
                     varbyref : (vpointer : pointer);
                     { unused so far, only to fill up space }
                     varrecord : (vrecord : pointer;precinfo : pointer);
                );
               1:
                 (vlongs : array[0..2] of longint);
           );
         1:(vwords : array[0..6] of word);
         2:(vbytes : array[0..13] of byte);
      end;
   pvardata = ^tvardata;

   pcalldesc = ^tcalldesc;
   tcalldesc = packed record
      calltype,argcount,namedargcount : byte;
      argtypes : array[0..255] of byte;
   end;

   pdispdesc = ^tdispdesc;
   tdispdesc = packed record
      dispid : longint;
      { not used by fpc }
      restype : byte;
      calldesc : tcalldesc;
   end;

   tvariantmanager = record
      vartoint : function(const v : variant) : longint;
      vartoint64 : function(const v : variant) : int64;
      vartoword64 : function(const v : variant) : qword;
      vartobool : function(const v : variant) : boolean;
{$ifndef FPUNONE}
      vartoreal : function(const v : variant) : extended;
      vartotdatetime : function(const v : variant) : tdatetime;
{$endif}
      vartocurr : function(const v : variant) : currency;
      vartopstr : procedure(var s ;const v : variant);
      vartolstr : procedure(var s : ansistring;const v : variant);
      vartowstr : procedure(var s : widestring;const v : variant);
      vartointf : procedure(var intf : iinterface;const v : variant);
      //vartodisp : procedure(var disp : idispatch;const v : variant);
      vartodynarray : procedure(var dynarr : pointer;const v : variant;
         typeinfo : pointer);

      varfrombool : procedure(var dest : variant;const source : Boolean);
      varfromint : procedure(var dest : variant;const source,Range : longint);
      varfromint64 : procedure(var dest : variant;const source : int64);
      varfromword64 : procedure(var dest : variant;const source : qword);
{$ifndef FPUNONE}
      varfromreal : procedure(var dest : variant;const source : extended);
      varfromtdatetime : procedure(var dest : Variant;const source : TDateTime);
{$endif}
      varfromcurr : procedure(var dest : Variant;const source : Currency);
      varfrompstr: procedure(var dest : variant; const source : ShortString);
      varfromlstr: procedure(var dest : variant; const source : ansistring);
      varfromwstr: procedure(var dest : variant; const source : WideString);
      varfromintf: procedure(var dest : variant;const source : iinterface);
      //varfromdisp: procedure(var dest : variant;const source : idispatch);
      varfromdynarray: procedure(var dest : variant;const source : pointer; typeinfo: pointer);
      olevarfrompstr: procedure(var dest : olevariant; const source : shortstring);
      olevarfromlstr: procedure(var dest : olevariant; const source : ansistring);
      olevarfromvar: procedure(var dest : olevariant; const source : variant);
      olevarfromint: procedure(var dest : olevariant; const source : longint;const range : shortint);

      { operators }
      varop : procedure(var left : variant;const right : variant;opcode : tvarop);
      cmpop : function(const left,right : variant;const opcode : tvarop) : boolean;
      varneg : procedure(var v : variant);
      varnot : procedure(var v : variant);

      { misc }
      varinit : procedure(var v : variant);
      varclear : procedure(var v : variant);
      varaddref : procedure(var v : variant);
      varcopy : procedure(var dest : variant;const source : variant);
      varcast : procedure(var dest : variant;const source : variant;vartype : longint);
      varcastole : procedure(var dest : variant; const source : variant;vartype : longint);

      dispinvoke: procedure(dest : pvardata;var source : tvardata;
        calldesc : pcalldesc;params : pointer);cdecl;

      vararrayredim : procedure(var a : variant;highbound : SizeInt);
      vararrayget : function(const a : variant;indexcount : SizeInt;indices : plongint) : variant;cdecl;
      vararrayput: procedure(var a : variant; const value : variant;
        indexcount : SizeInt;indices : plongint);cdecl;
      writevariant : function(var t : text;const v : variant;width : longint) : Pointer;
      write0Variant : function(var t : text;const v : Variant) : Pointer;
   end;
   pvariantmanager = ^tvariantmanager;

procedure GetVariantManager(var VarMgr: TVariantManager);
procedure SetVariantManager(const VarMgr: TVariantManager);
function IsVariantManagerSet: Boolean;

const
  VarClearProc :  procedure(var v : TVarData) = nil;
  VarAddRefProc : procedure(var v : TVarData) = nil;
  VarCopyProc :   procedure(var d : TVarData;const s : TVarData) = nil;
  VarToLStrProc : procedure(var d : AnsiString;const s : TVarData) = nil;

var
   VarDispProc : pointer;
   DispCallByIDProc : pointer;
   Null,Unassigned : Variant;

{**********************************************************************
                       to Variant assignments
 **********************************************************************}

{ Integer }
operator :=(const source : byte) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : shortint) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : word) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : smallint) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : dword) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : longint) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : qword) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : int64) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

{ Boolean }
operator :=(const source : boolean) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : wordbool) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : longbool) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

{ Chars }
operator :=(const source : char) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
//operator :=(const source : widechar) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

{ Strings }
operator :=(const source : shortstring) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : ansistring) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
//operator :=(const source : widestring) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

{ Floats }
{$ifdef SUPPORT_SINGLE}
operator :=(const source : single) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
{$endif SUPPORT_SINGLE}
{$ifdef SUPPORT_DOUBLE}
operator :=(const source : double) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
{$endif SUPPORT_DOUBLE}

{ Misc. }
operator :=(const source : currency) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : tdatetime) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : error) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

{**********************************************************************
                       from Variant assignments
 **********************************************************************}

{ Integer }
operator :=(const source : variant) dest : byte;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : shortint;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : word;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : smallint;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : dword;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : longint;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : qword;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : int64;{$ifdef SYSTEMINLINE}inline;{$endif}

{ Boolean }
operator :=(const source : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : wordbool;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : longbool;{$ifdef SYSTEMINLINE}inline;{$endif}

{ Chars }
operator :=(const source : variant) dest : char;{$ifdef SYSTEMINLINE}inline;{$endif}
//operator :=(const source : variant) dest : widechar;{$ifdef SYSTEMINLINE}inline;{$endif}

{ Strings }
operator :=(const source : variant) dest : shortstring;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : ansistring;{$ifdef SYSTEMINLINE}inline;{$endif}
//operator :=(const source : variant) dest : widestring;{$ifdef SYSTEMINLINE}inline;{$endif}

{ Floats }
{$ifdef SUPPORT_SINGLE}
operator :=(const source : variant) dest : single;{$ifdef SYSTEMINLINE}inline;{$endif}
{$endif SUPPORT_SINGLE}
{$ifdef SUPPORT_DOUBLE}
operator :=(const source : variant) dest : double;{$ifdef SYSTEMINLINE}inline;{$endif}
{$endif SUPPORT_DOUBLE}

{ Misc. }
operator :=(const source : variant) dest : currency;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : tdatetime;{$ifdef SYSTEMINLINE}inline;{$endif}
operator :=(const source : variant) dest : error;{$ifdef SYSTEMINLINE}inline;{$endif}

{**********************************************************************
                         Operators
 **********************************************************************}

operator or(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator and(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator xor(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator not(const op : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator shl(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator shr(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator +(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator -(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator *(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator /(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator **(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator div(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator mod(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator -(const op : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
operator =(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
operator <(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
operator >(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
operator >=(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
operator <=(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}

{ variant helpers }
procedure VarArrayRedim(var A: Variant; HighBound: SizeInt);
procedure VarCast(var dest : variant;const source : variant;vartype : longint);

{**********************************************************************
                        from OLEVariant assignments
 **********************************************************************}

{ some dummy types necessary to have generic resulttypes for certain compilerprocs }
type
  { normally the array shall be maxlongint big, but that will confuse
    the debugger }
  fpc_big_chararray = array[0..1023] of char;
//  fpc_big_widechararray = array[0..1023] of widechar;
  fpc_small_set = longint;
  fpc_normal_set = array[0..7] of longint;


{ Required to solve overloading problem with call from assembler (PFV) }
Function fpc_getmem(size: ptrint): pointer; compilerproc;
Procedure fpc_freemem(p: pointer); compilerproc;

procedure fpc_Shortstr_SetLength(var s:shortstring;len:SizeInt); compilerproc;
{$ifndef FPC_STRTOSHORTSTRINGPROC}
function fpc_shortstr_to_shortstr(len:longint;const sstr:shortstring): shortstring;compilerproc;
{$else FPC_STRTOSHORTSTRINGPROC}
procedure fpc_shortstr_to_shortstr(out res:shortstring; const sstr: shortstring);compilerproc;
{$endif FPC_STRTOSHORTSTRINGPROC}
 procedure fpc_shortstr_concat(var dests:shortstring;const s1,s2:shortstring);compilerproc;
procedure fpc_shortstr_append_shortstr(var s1:shortstring;const s2:shortstring); compilerproc;
function fpc_shortstr_compare(const left,right:shortstring) : longint; compilerproc;
 function fpc_shortstr_compare_equal(const left,right:shortstring) : longint; compilerproc;
{$ifndef FPC_STRTOSHORTSTRINGPROC}
function fpc_pchar_to_shortstr(p:pchar):shortstring;compilerproc;
{$else FPC_STRTOSHORTSTRINGPROC}
procedure fpc_pchar_to_shortstr(out res : shortstring;p:pchar);compilerproc;
{$endif FPC_STRTOSHORTSTRINGPROC}
function fpc_pchar_length(p:pchar):longint; compilerproc;

function fpc_chararray_to_shortstr(const arr: array of char):shortstring; compilerproc;
function fpc_shortstr_to_chararray(arraysize: longint; const src: ShortString): fpc_big_chararray; compilerproc;

Function  fpc_shortstr_Copy(const s:shortstring;index:SizeInt;count:SizeInt):shortstring;compilerproc;
Function  fpc_ansistr_Copy (Const S : AnsiString; Index,Size : SizeInt) : AnsiString;compilerproc;
function  fpc_char_copy(c:char;index : SizeInt;count : SizeInt): shortstring;compilerproc;


{ Str() support }
procedure fpc_shortstr_SInt(v : valSInt;len : SizeInt;out s : shortstring); compilerproc;
procedure fpc_shortstr_uint(v : valuint;len : SizeInt;var s : shortstring); compilerproc;
procedure fpc_chararray_sint(v : valsint;len : SizeInt;var a : array of char); compilerproc;
procedure fpc_chararray_uint(v : valuint;len : SizeInt;var a : array of char); compilerproc;
//procedure fpc_ansistr_qword(v : qword;len : SizeInt;var s : ansistring); compilerproc;
//procedure fpc_ansistr_int64(v : int64;len : SizeInt;var s : ansistring); compilerproc;

{ Val() support }
Function fpc_Val_Real_ShortStr(const s : shortstring; var code : ValSInt): ValReal; compilerproc;
Function fpc_Val_SInt_ShortStr(DestSize: SizeInt; Const S: ShortString; var Code: ValSInt): ValSInt; compilerproc;
Function fpc_Val_UInt_Shortstr(Const S: ShortString; var Code: ValSInt): ValUInt; compilerproc;

Procedure fpc_AnsiStr_Decr_Ref (Var S : Pointer); compilerproc;
Procedure fpc_AnsiStr_Incr_Ref (S : Pointer); compilerproc;
//Procedure fpc_AnsiStr_Assign (Var S1 : Pointer;S2 : Pointer); compilerproc;
Procedure fpc_AnsiStr_Assign (Var DestS : Pointer;S2 : Pointer); compilerproc;
Procedure fpc_AnsiStr_Concat (Var DestS : Ansistring;const S1,S2 : AnsiString); compilerproc;
procedure fpc_AnsiStr_Concat_multi (var DestS:ansistring;const sarr:array of Ansistring); compilerproc;
Procedure fpc_ansistr_append_char(Var S : AnsiString;c : char); compilerproc;
Procedure fpc_ansistr_append_shortstring(Var S : AnsiString;Str : ShortString); compilerproc;
Procedure fpc_ansistr_append_ansistring(Var S : AnsiString;Str : AnsiString); compilerproc;
{$ifdef EXTRAANSISHORT}
Procedure fpc_AnsiStr_ShortStr_Concat (Var S1: AnsiString; Var S2 : ShortString); compilerproc;
{$endif EXTRAANSISHORT}
function fpc_AnsiStr_To_ShortStr (high_of_res: SizeInt;const S2 : Ansistring): shortstring; compilerproc;
Function fpc_ShortStr_To_AnsiStr (Const S2 : ShortString): ansistring; compilerproc;
Function fpc_Char_To_AnsiStr(const c : Char): AnsiString; compilerproc;
Function fpc_PChar_To_AnsiStr(const p : pchar): ansistring; compilerproc;
Function fpc_CharArray_To_AnsiStr(const arr: array of char): ansistring; compilerproc;
function fpc_ansistr_to_chararray(arraysize: SizeInt; const src: ansistring): fpc_big_chararray; compilerproc;
Function fpc_AnsiStr_Compare(const S1, S2: AnsiString): SizeInt; compilerproc;
Function fpc_AnsiStr_Compare_equal(const S1,S2 : AnsiString): SizeInt; compilerproc;
Procedure fpc_AnsiStr_CheckZero(p : pointer); compilerproc;
Procedure fpc_AnsiStr_CheckRange(len,index : SizeInt); compilerproc;
Procedure fpc_AnsiStr_SetLength (Var S : RawByteString; l : SizeInt{$ifdef FPC_HAS_CPSTRING};cp : TSystemCodePage{$endif FPC_HAS_CPSTRING}); compilerproc;

//Procedure fpc_AnsiStr_SetLength (Var S : AnsiString; l : SizeInt); compilerproc;
{$ifdef EXTRAANSISHORT}
Function fpc_AnsiStr_ShortStr_Compare (Var S1 : Pointer; Var S2 : ShortString): SizeInt; compilerproc;
{$endif EXTRAANSISHORT}
{ pointer argument because otherwise when calling this, we get }
{ an endless loop since a 'var s: ansistring' must be made     }
{ unique as well                                               }
Function fpc_ansistr_Unique(Var S : Pointer): Pointer; compilerproc;

procedure fpc_variant_copy(d,s : pointer);compilerproc;
//procedure fpc_vararray_get(var d : variant;const s : variant;indices : plongint;len : sizeint);compilerproc;
procedure fpc_vararray_put(var d : variant;const s : variant;indices : plongint;len : sizeint);compilerproc;

function fpc_div_qword(n,z : qword) : qword; compilerproc;
function fpc_mod_qword(n,z : qword) : qword; compilerproc;
function fpc_div_int64(n,z : int64) : int64; compilerproc;
function fpc_mod_int64(n,z : int64) : int64; compilerproc;
function fpc_mul_qword(f1,f2 : qword;checkoverflow : longbool) : qword; compilerproc;
function fpc_mul_int64(f1,f2 : int64;checkoverflow : longbool) : int64; compilerproc;

function fpc_round_real(d : ValReal) : int64;compilerproc;
function fpc_trunc_real(d : ValReal) : int64;compilerproc;

{$ifdef FPC_INCLUDE_SOFTWARE_SHIFT_INT64}
function fpc_shl_qword(value,shift : qword) : qword; compilerproc;
function fpc_shr_qword(value,shift : qword) : qword; compilerproc;
function fpc_shl_int64(value,shift : int64) : int64; compilerproc;
function fpc_shr_int64(value,shift : int64) : int64; compilerproc;
{$endif  FPC_INCLUDE_SOFTWARE_SHIFT_INT64}

function fpc_do_is(aclass : tclass;aobject : tobject) : boolean; compilerproc;
function fpc_do_as(aclass : tclass;aobject : tobject): tobject; compilerproc;
procedure fpc_intf_decr_ref(var i: pointer); compilerproc;
procedure fpc_intf_incr_ref(i: pointer); compilerproc;
procedure fpc_intf_assign(var D: pointer; const S: pointer); compilerproc;
function  fpc_intf_as(const S: pointer; const iid: TGUID): pointer; compilerproc;
function fpc_class_as_intf(const S: pointer; const iid: TGUID): pointer; compilerproc;

Function fpc_PushExceptAddr (Ft: Longint;_buf,_newaddr : pointer): PJmp_buf ; compilerproc;
Procedure fpc_PushExceptObj (Obj : TObject; AnAddr,AFrame : Pointer); compilerproc;
Function fpc_Raiseexception (Obj : TObject; AnAddr,AFrame : Pointer) : TObject; compilerproc;
Procedure fpc_PopAddrStack; compilerproc;
function fpc_PopObjectStack : TObject; compilerproc;
function fpc_PopSecondObjectStack : TObject; compilerproc;
Procedure fpc_ReRaise; compilerproc;
Function fpc_Catches(Objtype : TClass) : TObject; compilerproc;

function fpc_help_constructor(_self:pointer;var _vmt:pointer;_vmt_pos:cardinal):pointer;compilerproc;
procedure fpc_help_destructor(_self,_vmt:pointer;vmt_pos:cardinal);compilerproc;
procedure fpc_help_fail(_self:pointer;var _vmt:pointer;vmt_pos:cardinal);compilerproc;

{$ifdef dummy}
Procedure fpc_DestroyException(o : TObject); compilerproc;
procedure fpc_check_object(obj:pointer); compilerproc;
procedure fpc_check_object_ext(vmt,expvmt:pointer);compilerproc;
{$endif dummy}

Procedure fpc_Initialize (Data,TypeInfo : pointer); compilerproc;
Procedure fpc_finalize (Data,TypeInfo: Pointer); compilerproc;
Procedure fpc_Addref (Data,TypeInfo : Pointer); compilerproc;
Procedure fpc_DecRef (Data,TypeInfo : Pointer);  compilerproc;
procedure fpc_finalize_array(data,typeinfo : pointer;count,size : longint); compilerproc;

function fpc_set_load_small(l: fpc_small_set): fpc_normal_set; compilerproc;
function fpc_set_create_element(b : byte): fpc_normal_set; compilerproc;
function fpc_set_set_byte(const source: fpc_normal_set; b : byte): fpc_normal_set; compilerproc;
function fpc_set_unset_byte(const source: fpc_normal_set; b : byte): fpc_normal_set; compilerproc;
function fpc_set_set_range(const orgset: fpc_normal_set; l,h : byte): fpc_normal_set; compilerproc;
function fpc_set_in_byte(const p: fpc_normal_set; b: byte): boolean; compilerproc;
function fpc_set_add_sets(const set1,set2: fpc_normal_set): fpc_normal_set; compilerproc;
function fpc_set_mul_sets(const set1,set2: fpc_normal_set): fpc_normal_set; compilerproc;
function fpc_set_sub_sets(const set1,set2: fpc_normal_set): fpc_normal_set; compilerproc;
function fpc_set_symdif_sets(const set1,set2: fpc_normal_set): fpc_normal_set; compilerproc;
function fpc_set_comp_sets(const set1,set2: fpc_normal_set): boolean; compilerproc;
function fpc_set_contains_sets(const set1,set2: fpc_normal_set): boolean; compilerproc;

{$ifdef LARGESETS}
procedure fpc_largeset_set_word(p : pointer;b : word); compilerproc;
procedure fpc_largeset_in_word(p : pointer;b : word); compilerproc;
procedure fpc_largeset_add_sets(set1,set2,dest : pointer;size : longint); compilerproc;
procedure fpc_largeset_sets(set1,set2,dest : pointer;size : longint); compilerproc;
procedure fpc_largeset_sub_sets(set1,set2,dest : pointer;size : longint); compilerproc;
procedure fpc_largeset_symdif_sets(set1,set2,dest : pointer;size : longint); compilerproc;
procedure fpc_largeset_comp_sets(set1,set2 : pointer;size : longint); compilerproc;
procedure fpc_largeset_contains_sets(set1,set2 : pointer; size: longint); compilerproc;
{$endif LARGESETS}

procedure fpc_rangeerror; compilerproc;
procedure fpc_divbyzero; compilerproc;
procedure fpc_overflow; compilerproc;
procedure fpc_iocheck; compilerproc;

procedure fpc_InitializeUnits; compilerproc;
procedure fpc_AbstractErrorIntern;compilerproc;
procedure fpc_assert(Const Msg,FName:Shortstring;LineNo:Longint;ErrorAddr:Pointer); compilerproc;


{$ifdef FPC_INCLUDE_SOFTWARE_INT64_TO_DOUBLE}
function fpc_int64_to_double(i: int64): double; compilerproc;
function fpc_qword_to_double(q: qword): double; compilerproc;
{$endif FPC_INCLUDE_SOFTWARE_INT64_TO_DOUBLE}


{*****************************************************************************
                               Heap
*****************************************************************************}


{ Memorymanager }
type
  PMemoryManager = ^TMemoryManager;
  TMemoryManager = record
    NeedLock            : boolean;
    Getmem              : function(Size:ptrint):Pointer;
    Freemem             : function(p:pointer):ptrint;
    FreememSize         : function(p:pointer;Size:ptrint):ptrint;
    AllocMem            : function(Size:ptrint):Pointer;
    //ReAllocMem          : function(var P: Pointer; OldSize, NewSize: PtrInt): Pointer;
	  ReAllocMem          : Function(var p:pointer;Size:ptruint):Pointer;
    MemSize             : function(p:pointer):ptrint;
  end;

procedure GetMemoryManager(var MemMgr: TMemoryManager);
procedure SetMemoryManager(const MemMgr: TMemoryManager);
function  IsMemoryManagerSet: Boolean;

{ Default MemoryManager functions }
Function  SysGetmem(Size:ptrint): Pointer;
Function  SysFreeMem(P: Pointer): PtrInt;
Function  SysFreememSize(p:pointer;Size:ptrint):ptrint;
Function  SysAllocMem(Size: PtrInt): Pointer;
function SysMemSize(p: pointer): ptrint;
//function SysReAllocMem(var P: Pointer; OldSize, NewSize: PtrInt): Pointer;
Function  SysReAllocMem(var p:pointer;size:ptruint):Pointer;

{ Tp7 functions }
Procedure GetMem(Var p:pointer;Size:ptrint);
Procedure FreeMem(P: Pointer; Size: PtrInt);


{ Delphi functions }
function GetMem(Size: PtrInt): Pointer;
function FreeMem(P: Pointer): PtrInt;
function ReAllocMem(var P: Pointer; NewSize: PtrUInt): Pointer;


{*****************************************************************************
                          Thread support
*****************************************************************************}

const
{$ifdef mswindows}
  { on windows, use stack size of starting process }
  DefaultStackSize = 0;
{$else mswindows}
  { including 16384 margin for stackchecking }
  DefaultStackSize = 32768;
{$endif mswindows}

type
  PEventState = pointer;
  PRTLEvent   = pointer;   // Windows=thandle, other=pointer to record.
  TThreadFunc = function(parameter : pointer) : ptrint;
  trtlmethod  = procedure of object;

  // Function prototypes for TThreadManager Record.
  TBeginThreadHandler = function (sa : Pointer;stacksize : PtrUInt; ThreadFunction : tthreadfunc;p : pointer;creationFlags : dword; var ThreadId : TThreadID) : TThreadID;
  TEndThreadHandler = procedure (ExitCode: DWord);
  // Used for Suspend/Resume/Kill
  TThreadHandler = function (threadHandle: TThreadID) : dword;
  TThreadSwitchHandler = procedure;
  TWaitForThreadTerminateHandler = function (threadHandle: TThreadID; TimeoutMs : longint) : dword;  {0=no timeout}
  TThreadSetPriorityHandler = function (threadHandle: TThreadID; Prio: longint): boolean;            {-15..+15, 0=normal}
  TThreadGetPriorityHandler = function (threadHandle: TThreadID): longint;
  TGetCurrentThreadIdHandler = function: TThreadID;
  TCriticalSectionHandler = procedure (var cs);
  TInitThreadVarHandler = procedure (var offset : dword;size : dword);
  TRelocateThreadVarHandler = function (offset : dword) : pointer;
  TAllocateThreadVarsHandler = procedure;
  TReleaseThreadVarsHandler = procedure;
  TBasicEventHandler        = procedure(state:peventstate);
  TBasicEventWaitForHandler = function (timeout:cardinal;state:peventstate):longint;
  TBasicEventCreateHandler  = function (EventAttributes :Pointer;  AManualReset,InitialState : Boolean;const Name:ansistring):pEventState;
  TRTLEventHandler          = procedure(AEvent:PRTLEvent);
  TRTLEventHandlerTimeout   = procedure(AEvent:PRTLEvent;timeout : longint);
  TRTLCreateEventHandler    = function:PRTLEvent;
  TRTLEventSyncHandler      = procedure (m:trtlmethod;p:tprocedure);

  // TThreadManager interface.
  TThreadManager = Record
    InitManager            : Function : Boolean;
    DoneManager            : Function : Boolean;
    BeginThread            : TBeginThreadHandler;
    EndThread              : TEndThreadHandler;
    SuspendThread          : TThreadHandler;
    ResumeThread           : TThreadHandler;
    KillThread             : TThreadHandler;
    ThreadSwitch           : TThreadSwitchHandler;
    WaitForThreadTerminate : TWaitForThreadTerminateHandler;
    ThreadSetPriority      : TThreadSetPriorityHandler;
    ThreadGetPriority      : TThreadGetPriorityHandler;
    GetCurrentThreadId     : TGetCurrentThreadIdHandler;
    InitCriticalSection    : TCriticalSectionHandler;
    DoneCriticalSection    : TCriticalSectionHandler;
    EnterCriticalSection   : TCriticalSectionHandler;
    LeaveCriticalSection   : TCriticalSectionHandler;
    InitThreadVar          : TInitThreadVarHandler;
    RelocateThreadVar      : TRelocateThreadVarHandler;
    AllocateThreadVars     : TAllocateThreadVarsHandler;
    ReleaseThreadVars      : TReleaseThreadVarsHandler;
    BasicEventCreate       : TBasicEventCreateHandler;      // left in for a while.
    BasicEventDestroy      : TBasicEventHandler;            // we might need BasicEvent
    BasicEventResetEvent   : TBasicEventHandler;            // for a real TEvent
    BasicEventSetEvent     : TBasicEventHandler;
    BasiceventWaitFOr      : TBasicEventWaitForHandler;
    RTLEventCreate         : TRTLCreateEventHandler;
    RTLEventDestroy        : TRTLEventHandler;
    RTLEventSetEvent       : TRTLEventHandler;
    RTLEventResetEvent     : TRTLEventHandler;
    RTLEventStartWait      : TRTLEventHandler;
    RTLEventWaitFor        : TRTLEventHandler;
    RTLEventSync           : TRTLEventSyncHandler;
    RTLEventWaitForTimeout : TRTLEventHandlerTimeout;
  end;

{*****************************************************************************
                         Thread Handler routines
*****************************************************************************}

Function GetThreadManager(Var TM : TThreadManager) : Boolean;
Function SetThreadManager(Const NewTM : TThreadManager; Var OldTM : TThreadManager) : Boolean;
Function SetThreadManager(Const NewTM : TThreadManager) : Boolean;
// Needs to be exported, so the manager can call it.
procedure InitThreadVars(RelocProc : Pointer);
procedure InitThread(stklen:cardinal);

procedure fpc_variant_clear (var v : tvardata);compilerproc;
{-------------------------------------------------------------------------------
                         Multithread Handling
-------------------------------------------------------------------------------}

function BeginThread(sa: Pointer; stacksize: dword; ThreadFunction: tthreadfunc; p: pointer; creationFlags: dword; var ThreadId: TThreadID): TThreadID;

// add some simplified forms which make life and porting easier
function BeginThread(ThreadFunction : tthreadfunc) : TThreadID;
function BeginThread(ThreadFunction : tthreadfunc;p : pointer) : TThreadID;
function BeginThread(ThreadFunction : tthreadfunc;p : pointer; var ThreadId : TThreadID) : TThreadID;

procedure EndThread(ExitCode : DWord);
procedure EndThread;

{some thread support functions}
function  SuspendThread (threadHandle : TThreadID) : dword;
function  ResumeThread  (threadHandle : TThreadID) : dword;
procedure ThreadSwitch;                                                                {give time to other threads}
function  KillThread (threadHandle : TThreadID) : dword;
function  WaitForThreadTerminate (threadHandle : TThreadID; TimeoutMs : longint) : dword;  {0=no timeout}
function  ThreadSetPriority (threadHandle : TThreadID; Prio: longint): boolean;            {-15..+15, 0=normal}
function  ThreadGetPriority (threadHandle : TThreadID): longint;
function  GetCurrentThreadId : TThreadID;


function InterLockedCompareExchange(var Target: longint; NewValue, Comperand : longint): longint; assembler;

{ this allows to do a lot of things in MT safe way }
{ it is also used to make the heap management      }
{ thread safe                                      }
procedure InitCriticalSection(var cs : TRTLCriticalSection);
procedure DoneCriticalsection(var cs : TRTLCriticalSection);
procedure EnterCriticalsection(var cs : TRTLCriticalSection);
procedure LeaveCriticalsection(var cs : TRTLCriticalSection);

function  BasicEventCreate(EventAttributes : Pointer; AManualReset,InitialState : Boolean;const Name : ansistring):pEventState;
procedure basiceventdestroy(state:peventstate);
procedure basiceventResetEvent(state:peventstate);
procedure basiceventSetEvent(state:peventstate);
function  basiceventWaitFor(Timeout : Cardinal;state:peventstate) : longint;

function  RTLEventCreate :PRTLEvent;
procedure RTLeventdestroy(state:pRTLEvent);
procedure RTLeventSetEvent(state:pRTLEvent);
procedure RTLeventResetEvent(state:pRTLEvent);
procedure RTLeventStartWait(state:pRTLEvent);
procedure RTLeventWaitFor(state:pRTLEvent);
procedure RTLeventWaitFor(state:pRTLEvent;timeout : longint);
procedure RTLeventsync(m:trtlmethod;p:tprocedure);

{*****************************************************************************
                          Resources support
*****************************************************************************}

const 
  LineEnding = #10;
  LFNSupport = True;
  DirectorySeparator = '/';
  DriveSeparator = ':';
  PathSeparator = ':';
 
  maxExitCode = 255;
  MaxPathLen = 256; 

const
  UnusedHandle    = -1;
  StdInputHandle  = 0;
  StdOutputHandle = 1;
  StdErrorHandle  = 2;

  FileNameCaseSensitive : boolean = True;
  CtrlZMarksEOF: boolean = False; 

  sLineBreak = LineEnding;
  DefaultTextLineBreakStyle : TTextLineBreakStyle = tlbsLF;

   
{ only for compatibility }
var
	argc: LongInt;
  argv: PPChar;
  envp: PPChar;
  DefaultSystemCodePage: TSystemCodePage;
// this calls are not implement in thread manager

implementation


{****************************************************************************
                                Local types
****************************************************************************}

Procedure HandleError (Errno : Longint); forward;
Procedure HandleErrorFrame (Errno : longint;frame : Pointer); forward;

const
  STACK_MARGIN = 16384;    { Stack size margin for stack checking }

{ For Error Handling.}
  ErrorBase : Pointer = nil;

{ Used by the ansistrings and maybe also other things in the future }
var
  emptychar: char; public name 'FPC_EMPTYCHAR';
//  initialstklen: SizeUint; external name '__stklen';


{****************************************************************************
                    Include processor specific routines
****************************************************************************}

{$ifdef CPUX86_64}
  {$ifdef SYSPROCDEFINED}
    {$Error Can't determine processor type !}
  {$endif}
  {
    This file is part of the Free Pascal run time library.
    Copyright (c) 2002 by Florian Klaempfl.
    Member of the Free Pascal development team

    Parts of this code are derived from the x86-64 linux port
    Copyright 2002 Andi Kleen

    Processor dependent implementation for the system unit for
    the x86-64 architecture

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$asmmode GAS}

{****************************************************************************
                               Primitives
****************************************************************************}

{$define FPC_SYSTEM_HAS_SPTR}
Function Sptr : Pointer;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
        movq    %rsp,%rax
end;

{$IFNDEF INTERNAL_BACKTRACE}
{$define FPC_SYSTEM_HAS_GET_FRAME}
function get_frame:pointer;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
        movq    %rbp,%rax
end;
{$ENDIF not INTERNAL_BACKTRACE}


{$define FPC_SYSTEM_HAS_GET_CALLER_ADDR}
function get_caller_addr(framebp:pointer):pointer;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
{$ifdef win64}
        orq     %rcx,%rcx
        jz      .Lg_a_null
        movq    8(%rcx),%rax
{$else win64}
        { %rdi = framebp }
        orq     %rdi,%rdi
        jz      .Lg_a_null
        movq    8(%rdi),%rax
{$endif win64}
.Lg_a_null:
end;


{$define FPC_SYSTEM_HAS_GET_CALLER_FRAME}
function get_caller_frame(framebp:pointer):pointer;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
{$ifdef win64}
        orq     %rcx,%rcx
        jz      .Lg_a_null
        movq    (%rcx),%rax
{$else win64}
        { %rdi = framebp }
        orq     %rdi,%rdi
        jz      .Lg_a_null
        movq    (%rdi),%rax
{$endif win64}
.Lg_a_null:
end;

(*
{$define FPC_SYSTEM_HAS_MOVE}
procedure Move(const source;var dest;count:longint);[public, alias: 'FPC_MOVE'];assembler;
  asm
     { rdi destination
       rsi source
       rdx count
     }
     pushq %rbx
     prefetcht0 (%rsi)  // for more hopefully the hw prefetch will kick in
     movq %rdi,%rax

     movl %edi,%ecx
     andl $7,%ecx
     jnz  .Lbad_alignment
.Lafter_bad_alignment:
     movq %rdx,%rcx
     movl $64,%ebx
     shrq $6,%rcx
     jz .Lhandle_tail

.Lloop_64:
     { no prefetch because we assume the hw prefetcher does it already
       and we have no specific temporal hint to give. XXX or give a nta
       hint for the source? }
     movq (%rsi),%r11
     movq 8(%rsi),%r8
     movq 2*8(%rsi),%r9
     movq 3*8(%rsi),%r10
     movnti %r11,(%rdi)
     movnti %r8,1*8(%rdi)
     movnti %r9,2*8(%rdi)
     movnti %r10,3*8(%rdi)

     movq 4*8(%rsi),%r11
     movq 5*8(%rsi),%r8
     movq 6*8(%rsi),%r9
     movq 7*8(%rsi),%r10
     movnti %r11,4*8(%rdi)
     movnti %r8,5*8(%rdi)
     movnti %r9,6*8(%rdi)
     movnti %r10,7*8(%rdi)

     addq %rbx,%rsi
     addq %rbx,%rdi
     loop .Lloop_64

.Lhandle_tail:
     movl %edx,%ecx
     andl $63,%ecx
     shrl $3,%ecx
     jz   .Lhandle_7
     movl $8,%ebx
.Lloop_8:
     movq (%rsi),%r8
     movnti %r8,(%rdi)
     addq %rbx,%rdi
     addq %rbx,%rsi
     loop .Lloop_8

.Lhandle_7:
     movl %edx,%ecx
     andl $7,%ecx
     jz .Lende
.Lloop_1:
     movb (%rsi),%r8b
     movb %r8b,(%rdi)
     incq %rdi
     incq %rsi
     loop .Lloop_1

     jmp .Lende

     { align destination }
     { This is simpleminded. For bigger blocks it may make sense to align
        src and dst to their aligned subset and handle the rest separately }
.Lbad_alignment:
     movl $8,%r9d
     subl %ecx,%r9d
     movl %r9d,%ecx
     subq %r9,%rdx
     js   .Lsmall_alignment
     jz   .Lsmall_alignment
.Lalign_1:
     movb (%rsi),%r8b
     movb %r8b,(%rdi)
     incq %rdi
     incq %rsi
     loop .Lalign_1
     jmp .Lafter_bad_alignment
.Lsmall_alignment:
     addq %r9,%rdx
     jmp .Lhandle_7

.Lende:
     sfence
     popq %rbx
  end;
*)

(*
{$define FPC_SYSTEM_HAS_FILLCHAR}
Procedure FillChar(var x;count:longint;value:byte);assembler;
  asm
    { rdi   destination
      rsi   value (char)
      rdx   count (bytes)
    }
    movq %rdi,%r10
    movq %rdx,%r11

    { expand byte value  }
    movzbl %sil,%ecx
    movabs $0x0101010101010101,%rax
    mul    %rcx         { with rax, clobbers rdx }

    { align dst }
    movl  %edi,%r9d
    andl  $7,%r9d
    jnz  .Lbad_alignment
.Lafter_bad_alignment:

     movq %r11,%rcx
     movl $64,%r8d
     shrq $6,%rcx
     jz  .Lhandle_tail

.Lloop_64:
     movnti  %rax,(%rdi)
     movnti  %rax,8(%rdi)
     movnti  %rax,16(%rdi)
     movnti  %rax,24(%rdi)
     movnti  %rax,32(%rdi)
     movnti  %rax,40(%rdi)
     movnti  %rax,48(%rdi)
     movnti  %rax,56(%rdi)
     addq    %r8,%rdi
     loop    .Lloop_64

     { Handle tail in loops. The loops should be faster than hard
        to predict jump tables. }
.Lhandle_tail:
     movl       %r11d,%ecx
     andl    $56,%ecx
     jz     .Lhandle_7
     shrl       $3,%ecx
.Lloop_8:
     movnti  %rax,(%rdi)
     addq    $8,%rdi
     loop    .Lloop_8
.Lhandle_7:
     movl       %r11d,%ecx
     andl       $7,%ecx
     jz      .Lende
.Lloop_1:
     movb       %al,(%rdi)
     addq       $1,%rdi
     loop       .Lloop_1

     jmp .Lende

.Lbad_alignment:
     cmpq $7,%r11
     jbe .Lhandle_7
     movnti %rax,(%rdi) //  unaligned store
     movq $8,%r8
     subq %r9,%r8
     addq %r8,%rdi
     subq %r8,%r11
     jmp .Lafter_bad_alignment

.Lende:
     movq       %r10,%rax
  end;
*)


{$define FPC_SYSTEM_HAS_DECLOCKED_LONGINT}
{ does a thread save inc/dec }
function declocked(var l : longint) : boolean;assembler;
  asm
     lock
     decl       (%rcx)
.Ldeclockedend:
     setzb      %al
  end;


{$define FPC_SYSTEM_HAS_DECLOCKED_INT64}
function declocked(var l : int64) : boolean;assembler;
  asm
.Ldeclockedend:
     setzb      %al
  end;


{$define FPC_SYSTEM_HAS_INCLOCKED_LONGINT}
procedure inclocked(var l : longint);assembler;

  asm
     lock
     incl       (%rcx)
.Linclockedend:
  end;


{$define FPC_SYSTEM_HAS_INCLOCKED_INT64}
procedure inclocked(var l : int64);assembler;

  asm
     lock
     incq       (%rcx)
     jmp        .Linclockedend
.Linclockedend:
  end;


function InterLockedDecrement (var Target: longint) : longint; assembler;
asm
{$ifdef win64}
        movq    %rcx,%rax
{$else win64}
        movq    %rdi,%rax
{$endif win64}
        movl    $-1,%edx
        xchgq   %rdx,%rax
        lock
        xaddl   %eax, (%rdx)
        decl    %eax
end;


function InterLockedIncrement (var Target: longint) : longint; assembler;
asm
{$ifdef win64}
        movq    %rcx,%rax
{$else win64}
        movq    %rdi,%rax
{$endif win64}
        movl    $1,%edx
        xchgq   %rdx,%rax
        lock
        xaddl   %eax, (%rdx)
        incl    %eax
end;


function InterLockedExchange (var Target: longint;Source : longint) : longint; assembler;
asm
{$ifdef win64}
        xchgl   (%rcx),%edx
        movl    %edx,%eax
{$else win64}
        xchgl   (%rdi),%esi
        movl    %esi,%eax
{$endif win64}
end;


function InterLockedExchangeAdd (var Target: longint;Source : longint) : longint; assembler;
asm
{$ifdef win64}
        xchgq   %rcx,%rdx
        lock
        xaddl   %ecx, (%rdx)
        movl    %ecx,%eax
{$else win64}
        xchgq   %rdi,%rsi
        lock
        xaddl   %edi, (%rsi)
        movl    %edi,%eax
{$endif win64}
end;


function InterLockedCompareExchange(var Target: longint; NewValue, Comperand : longint): longint; assembler;
asm
{$ifdef win64}
        movl            %edx,%eax
        lock
        cmpxchgl        %r8d,(%rcx)
{$else win64}
        movl            %esi,%eax
        lock
        cmpxchgl        %edx,(%rdi)
{$endif win64}
end;


function InterLockedDecrement64 (var Target: int64) : int64; assembler;
asm
{$ifdef win64}
        movq    %rcx,%rax
{$else win64}
        movq    %rdi,%rax
{$endif win64}
        movq    $-1,%rdx
        xchgq   %rdx,%rax
        lock
        xaddq   %rax, (%rdx)
        decq    %rax
end;


function InterLockedIncrement64 (var Target: int64) : int64; assembler;
asm
{$ifdef win64}
        movq    %rcx,%rax
{$else win64}
        movq    %rdi,%rax
{$endif win64}
        movq    $1,%rdx
        xchgq   %rdx,%rax
        lock
        xaddq   %rax, (%rdx)
        incq    %rax
end;


function InterLockedExchange64 (var Target: int64;Source : int64) : int64; assembler;
asm
{$ifdef win64}
        xchgq   (%rcx),%rdx
        movq    %rdx,%rax
{$else win64}
        xchgq   (%rdi),%rsi
        movq    %rsi,%rax
{$endif win64}
end;


function InterLockedExchangeAdd64 (var Target: int64;Source : int64) : int64; assembler;
asm
{$ifdef win64}
        xchgq   %rcx,%rdx
        lock
        xaddq   %rcx, (%rdx)
        movq    %rcx,%rax
{$else win64}
        xchgq   %rdi,%rsi
        lock
        xaddq   %rdi, (%rsi)
        movq    %rdi,%rax
{$endif win64}
end;


//function InterLockedCompareExchange64(var Target: int64; NewValue, Comperand : int64): int64; assembler;
//asm
//{$ifdef win64}
//        movq            %rdx,%rax
//        lock
//        cmpxchgq        %r8d,(%rcx)
//{$else win64}
//        movq            %rsi,%rax
//        lock
//        cmpxchgq        %rdx,(%rdi)
//{$endif win64}
//end;


{****************************************************************************
                                  FPU
****************************************************************************}

const
  { Internal constants for use in system unit }
  FPU_Invalid = 1;
  FPU_Denormal = 2;
  FPU_DivisionByZero = 4;
  FPU_Overflow = 8;
  FPU_Underflow = $10;
  FPU_StackUnderflow = $20;
  FPU_StackOverflow = $40;
  FPU_ExceptionMask = $ff;

  MM_MaskInvalidOp = %0000000010000000;
  MM_MaskDenorm    = %0000000100000000;
  MM_MaskDivZero   = %0000001000000000;
  MM_MaskOverflow  = %0000010000000000;
  MM_MaskUnderflow = %0000100000000000;
  MM_MaskPrecision = %0001000000000000;

  {$define SYSPROCDEFINED}
{$endif CPUX86_64}

procedure fillchar(var x;count : SizeInt;value : boolean);{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  fillchar(x,count,byte(value));
end;

procedure fillchar(var x;count : SizeInt;value : char);{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  fillchar(x,count,byte(value));
end;


{****************************************************************************
                               Primitives
****************************************************************************}
type
  pstring = ^shortstring;

{$ifndef FPC_SYSTEM_HAS_MOVE}
procedure Move(const source;var dest;count:SizeInt);[public, alias: 'FPC_MOVE'];
type
  bytearray    = array [0..high(sizeint)-1] of byte;
var
  i:longint;
begin
  if count <= 0 then exit;
  Dec(count);
  if @source<@dest then
    begin
      for i:=count downto 0 do
        bytearray(dest)[i]:=bytearray(source)[i];
    end
  else
    begin
      for i:=0 to count do
        bytearray(dest)[i]:=bytearray(source)[i];
    end;
end;
{$endif not FPC_SYSTEM_HAS_MOVE}


{$ifndef FPC_SYSTEM_HAS_FILLCHAR}
Procedure FillChar(var x;count:SizeInt;value:byte);
type
  longintarray = array [0..high(sizeint) div 4-1] of longint;
  bytearray    = array [0..high(sizeint)-1] of byte;
var
  i,v : longint;
begin
  if count <= 0 then exit;
  v := 0;
  { aligned? }
  if (PtrUInt(@x) mod sizeof(PtrUInt))<>0 then
    begin
      for i:=0 to count-1 do
        bytearray(x)[i]:=value;
    end
  else
    begin
      v:=(value shl 8) or (value and $FF);
      v:=(v shl 16) or (v and $ffff);
      for i:=0 to (count div 4)-1 do
        longintarray(x)[i]:=v;
      for i:=(count div 4)*4 to count-1 do
        bytearray(x)[i]:=value;
    end;
end;
{$endif FPC_SYSTEM_HAS_FILLCHAR}


{$ifndef FPC_SYSTEM_HAS_FILLBYTE}
procedure FillByte (var x;count : SizeInt;value : byte );
begin
  FillChar (X,Count,CHR(VALUE));
end;
{$endif not FPC_SYSTEM_HAS_FILLBYTE}


{$ifndef FPC_SYSTEM_HAS_FILLWORD}
procedure fillword(var x;count : SizeInt;value : word);
type
  longintarray = array [0..high(sizeint) div 4-1] of longint;
  wordarray    = array [0..high(sizeint) div 2-1] of word;
var
  i,v : longint;
begin
  if Count <= 0 then exit;
  { aligned? }
  if (PtrUInt(@x) mod sizeof(PtrUInt))<>0 then
    begin
      for i:=0 to count-1 do
        wordarray(x)[i]:=value;
    end
  else
    begin
      v:=value*$10000+value;
      for i:=0 to (count div 2) -1 do
        longintarray(x)[i]:=v;
      for i:=(count div 2)*2 to count-1 do
        wordarray(x)[i]:=value;
    end;
end;
{$endif not FPC_SYSTEM_HAS_FILLWORD}


{$ifndef FPC_SYSTEM_HAS_FILLDWORD}
procedure FillDWord(var x;count : SizeInt;value : DWord);
type
  longintarray = array [0..high(sizeint) div 4-1] of longint;
begin
  if count <= 0 then exit;
  while Count<>0 do
   begin
     { range checking must be disabled here }
     longintarray(x)[count-1]:=longint(value);
     Dec(count);
   end;
end;
{$endif FPC_SYSTEM_HAS_FILLDWORD}


{$ifndef FPC_SYSTEM_HAS_INDEXCHAR}
function IndexChar(Const buf;len:SizeInt;b:char):SizeInt;
begin
  IndexChar:=IndexByte(Buf,Len,byte(B));
end;
{$endif not FPC_SYSTEM_HAS_INDEXCHAR}


{$ifndef FPC_SYSTEM_HAS_INDEXBYTE}
function IndexByte(Const buf;len:SizeInt;b:byte):SizeInt;
type
  bytearray    = array [0..high(sizeint)-1] of byte;
var
  I : longint;
begin
  I:=0;
  { simulate assembler implementations behaviour, which is expected }
  { fpc_pchar_to_ansistr in astrings.inc                            }
  if (len < 0) then
    len := high(longint);
  while (I<Len) and (bytearray(buf)[I]<>b) do
   inc(I);
  if (i=Len) then
   i:=-1;                      {Can't use 0, since it is a possible value}
  IndexByte:=I;
end;
{$endif not FPC_SYSTEM_HAS_INDEXBYTE}


{$ifndef FPC_SYSTEM_HAS_INDEXWORD}
function Indexword(Const buf;len:SizeInt;b:word):SizeInt;
type
  wordarray    = array [0..high(sizeint) div 2-1] of word;
var
  I : longint;
begin
  I:=0;
  if (len < 0) then
    len := high(longint);
  while (I<Len) and (wordarray(buf)[I]<>b) do
   inc(I);
  if (i=Len) then
   i:=-1;           {Can't use 0, since it is a possible value for index}
  Indexword:=I;
end;
{$endif not FPC_SYSTEM_HAS_INDEXWORD}


{$ifndef FPC_SYSTEM_HAS_INDEXDWORD}
function IndexDWord(Const buf;len:SizeInt;b:DWord):SizeInt;
type
  dwordarray = array [0..high(sizeint) div 4-1] of dword;
var
  I : longint;
begin
  I:=0;
  if (len < 0) then
    len := high(longint);
  while (I<Len) and (dwordarray(buf)[I]<>b) do
    inc(I);
  if (i=Len) then
   i:=-1;           {Can't use 0, since it is a possible value for index}
  IndexDWord:=I;
end;
{$endif not FPC_SYSTEM_HAS_INDEXDWORD}


{$ifndef FPC_SYSTEM_HAS_COMPARECHAR}
function CompareChar(Const buf1,buf2;len:SizeInt):SizeInt;
begin
  CompareChar:=CompareByte(buf1,buf2,len);
end;
{$endif not FPC_SYSTEM_HAS_COMPARECHAR}


{$ifndef FPC_SYSTEM_HAS_COMPAREBYTE}
function CompareByte(Const buf1,buf2;len:SizeInt):SizeInt;
type
  bytearray = array [0..high(sizeint)-1] of byte;
var
  I : longint;
begin
  I:=0;
  if (Len<>0) and (@Buf1<>@Buf2) then
   begin
     while (bytearray(Buf1)[I]=bytearray(Buf2)[I]) and (I<Len) do
      inc(I);
     if I=Len then  {No difference}
      I:=0
     else
      begin
        I:=bytearray(Buf1)[I]-bytearray(Buf2)[I];
        if I>0 then
         I:=1
        else
         if I<0 then
          I:=-1;
      end;
   end;
  CompareByte:=I;
end;
{$endif not FPC_SYSTEM_HAS_COMPAREBYTE}


{$ifndef FPC_SYSTEM_HAS_COMPAREWORD}
function CompareWord(Const buf1,buf2;len:SizeInt):SizeInt;
type
  wordarray = array [0..high(sizeint) div 2-1] of word;
var
  I : longint;
begin
  I:=0;
  if (Len<>0) and (@Buf1<>@Buf2) then
   begin
     while (wordarray(Buf1)[I]=wordarray(Buf2)[I]) and (I<Len) do
      inc(I);
     if I=Len then  {No difference}
      I:=0
     else
      begin
        I:=wordarray(Buf1)[I]-wordarray(Buf2)[I];
        if I>0 then
         I:=1
        else
         if I<0 then
          I:=-1;
      end;
   end;
  CompareWord:=I;
end;
{$endif not FPC_SYSTEM_HAS_COMPAREWORD}


{$ifndef FPC_SYSTEM_HAS_COMPAREDWORD}
function CompareDWord(Const buf1,buf2;len:SizeInt):SizeInt;
type
  longintarray = array [0..high(sizeint) div 4-1] of longint;
var
  I : longint;
begin
  I:=0;
  if (Len<>0) and (@Buf1<>@Buf2) then
   begin
     while (longintarray(Buf1)[I]=longintarray(Buf2)[I]) and (I<Len) do
      inc(I);
     if I=Len then  {No difference}
      I:=0
     else
      begin
        I:=longintarray(Buf1)[I]-longintarray(Buf2)[I];
        if I>0 then
         I:=1
        else
         if I<0 then
          I:=-1;
      end;
   end;
  CompareDWord:=I;
end;
{$endif ndef FPC_SYSTEM_HAS_COMPAREDWORD}


{$ifndef FPC_SYSTEM_HAS_MOVECHAR0}
procedure MoveChar0(Const buf1;var buf2;len:SizeInt);
var
  I : longint;
begin
  if Len = 0 then exit;
  I:=IndexByte(Buf1,Len,0);
  if I<>-1 then
    Move(Buf1,Buf2,I)
  else
    Move(Buf1,Buf2,len);
end;
{$endif ndef FPC_SYSTEM_HAS_MOVECHAR0}


{$ifndef FPC_SYSTEM_HAS_INDEXCHAR0}
function IndexChar0(Const buf;len:SizeInt;b:Char):SizeInt;
var
  I : longint;
begin
  if Len<>0 then
   begin
     I:=IndexByte(Buf,Len,0);
     If (I=-1) then
       I:=Len;
     IndexChar0:=IndexByte(Buf,I,byte(b));
   end
  else
   IndexChar0:=0;
end;
{$endif ndef FPC_SYSTEM_HAS_INDEXCHAR0}


{$ifndef FPC_SYSTEM_HAS_COMPARECHAR0}
function CompareChar0(Const buf1,buf2;len:SizeInt):SizeInt;
type
  bytearray = array [0..high(sizeint)-1] of byte;
var
  i : longint;
begin
  I:=0;
  if (Len<>0) and (@Buf1<>@Buf2) then
   begin
     while (I<Len) And
           ((Pbyte(@Buf1)[i]<>0) and (PByte(@buf2)[i]<>0)) and
           (pbyte(@Buf1)[I]=pbyte(@Buf2)[I])  do
      inc(I);
     if (I=Len) or
        (PByte(@Buf1)[i]=0) or
        (PByte(@buf2)[I]=0) then  {No difference or 0 reached }
      I:=0
     else
      begin
        I:=bytearray(Buf1)[I]-bytearray(Buf2)[I];
        if I>0 then
         I:=1
        else
         if I<0 then
          I:=-1;
      end;
   end;
  CompareChar0:=I;
end;
{$endif not FPC_SYSTEM_HAS_COMPARECHAR0}


{****************************************************************************
                              Object Helpers
****************************************************************************}

{$ifndef FPC_SYSTEM_HAS_FPC_HELP_CONSTRUCTOR}
{ Note: _vmt will be reset to -1 when memory is allocated,
  this is needed for fpc_help_fail }
function fpc_help_constructor(_self:pointer;var _vmt:pointer;_vmt_pos:cardinal):pointer;[public,alias:'FPC_HELP_CONSTRUCTOR'];compilerproc;
type
//  ppointer = ^pointer;
  pvmt = ^tvmt;
  tvmt=packed record
    size,msize:ptrint;
    parent:pointer;
  end;
var
  vmtcopy : pointer;
begin
  { Inherited call? }
  if _vmt=nil then
    begin
      fpc_help_constructor:=_self;
      exit;
    end;
  vmtcopy:=_vmt;

  if (_self=nil) and
     (pvmt(_vmt)^.size>0) then
    begin
      getmem(_self,pvmt(_vmt)^.size);
      { reset vmt needed for fail }
      _vmt:=pointer(-1);
    end;
  if _self<>nil then
    begin
      fillchar(_self^,pvmt(vmtcopy)^.size,#0);
      ppointer(_self+_vmt_pos)^:=vmtcopy;
    end;
  fpc_help_constructor:=_self;
end;
{$endif FPC_SYSTEM_HAS_FPC_HELP_CONSTRUCTOR}

{$ifndef FPC_SYSTEM_HAS_FPC_HELP_DESTRUCTOR}
{ Note: _self will not be reset, the compiler has to generate the reset }
procedure fpc_help_destructor(_self,_vmt:pointer;vmt_pos:cardinal);[public,alias:'FPC_HELP_DESTRUCTOR'];  compilerproc;
type
  ppointer = ^pointer;
  pvmt = ^tvmt;
  tvmt = packed record
    size,msize : ptrint;
    parent : pointer;
  end;
begin
   { already released? }
   if (_self=nil) or
      (_vmt=nil) or
      (ppointer(_self+vmt_pos)^=nil) then
     exit;
   if (pvmt(ppointer(_self+vmt_pos)^)^.size=0) or
      (pvmt(ppointer(_self+vmt_pos)^)^.size+pvmt(ppointer(_self+vmt_pos)^)^.msize<>0) then
     RunError(210);
   { reset vmt to nil for protection }
   ppointer(_self+vmt_pos)^:=nil;
   freemem(_self, pvmt(_vmt)^.size);
end;
{$endif FPC_SYSTEM_HAS_FPC_HELP_DESTRUCTOR}


{$ifndef FPC_SYSTEM_HAS_FPC_HELP_FAIL}
{ Note: _self will not be reset, the compiler has to generate the reset }
procedure fpc_help_fail(_self:pointer;var _vmt:pointer;vmt_pos:cardinal);[public,alias:'FPC_HELP_FAIL'];compilerproc;
type
  ppointer = ^pointer;
  pvmt = ^tvmt;
  tvmt = packed record
    size,msize : ptrint;
    parent : pointer;
  end;
begin
   if (_self=nil) or (_vmt=nil) then
     exit;
   { vmt=-1 when memory was allocated }
   if PtrUInt(_vmt)= PtrUInt(-1) then
     begin
       if (_self=nil) or (ppointer(_self+vmt_pos)^=nil) then
         HandleError(210)
       else
         begin
           ppointer(_self+vmt_pos)^:=nil;
           freemem(_self, pvmt(_vmt)^.size);
           { reset _vmt to nil so it will not be freed a
             second time }
           _vmt:=nil;
         end;
     end
   else
     ppointer(_self+vmt_pos)^:=nil;
end;
{$endif FPC_SYSTEM_HAS_FPC_HELP_FAIL}

{$ifndef FPC_SYSTEM_HAS_FPC_CHECK_OBJECT}
procedure fpc_check_object(_vmt : pointer); [public,alias:'FPC_CHECK_OBJECT'];  compilerproc;
type
  pvmt = ^tvmt;
  tvmt = packed record
    size,msize : ptrint;
    parent : pointer;
  end;
begin
  if (_vmt=nil) or
     (pvmt(_vmt)^.size=0) or
     (pvmt(_vmt)^.size+pvmt(_vmt)^.msize<>0) then
    RunError(210);
end;

{$endif ndef FPC_SYSTEM_HAS_FPC_CHECK_OBJECT}


{$ifndef FPC_SYSTEM_HAS_FPC_CHECK_OBJECT_EXT}
{ checks for a correct vmt pointer }
{ deeper check to see if the current object is }
{ really related to the True }
procedure fpc_check_object_ext(vmt, expvmt : pointer); [public,alias:'FPC_CHECK_OBJECT_EXT']; compilerproc;
type
  pvmt = ^tvmt;
  tvmt = packed record
    size,msize : ptrint;
    parent : pointer;
  end;
begin
   if (vmt=nil) or
      (pvmt(vmt)^.size=0) or
      (pvmt(vmt)^.size+pvmt(vmt)^.msize<>0) then
        RunError(210);
   while assigned(vmt) do
     if vmt=expvmt then
       exit
     else
       vmt:=pvmt(vmt)^.parent;
   RunError(219);
end;
{$endif not FPC_SYSTEM_HAS_FPC_CHECK_OBJECT_EXT}


{****************************************************************************
                                 String
****************************************************************************}

{$ifndef FPC_SYSTEM_HAS_FPC_SHORTSTR_ASSIGN}

{$ifndef FPC_STRTOSHORTSTRINGPROC}
function fpc_shortstr_to_shortstr(len:longint;const sstr:shortstring): shortstring;[public,alias:'FPC_SHORTSTR_TO_SHORTSTR']; compilerproc;
var
  slen : byte;
begin
  slen:=length(sstr);
  if slen<len then
    len:=slen;
  move(sstr[0],result[0],len+1);
  if slen>len then
    result[0]:=chr(len);
end;
{$else FPC_STRTOSHORTSTRINGPROC}
procedure fpc_shortstr_to_shortstr(out res:shortstring; const sstr: shortstring);[public,alias:'FPC_SHORTSTR_TO_SHORTSTR']; compilerproc;
var
  slen : byte;
begin
  slen:=length(sstr);
  if slen>high(res) then
    slen:=high(res);
  move(sstr[0],res[0],slen+1);
  res[0]:=chr(slen);
end;
{$endif FPC_STRTOSHORTSTRINGPROC}

procedure fpc_shortstr_assign(len:longint;sstr,dstr:pointer);[public,alias:'FPC_SHORTSTR_ASSIGN']; {$ifdef HAS_COMPILER_PROC} compilerproc; {$endif}
var
  slen : byte;
type
  pstring = ^string;
begin
  slen:=length(pstring(sstr)^);
  if slen<len then
    len:=slen;
  move(sstr^,dstr^,len+1);
  if slen>len then
    pchar(dstr)^:=chr(len);
end;

{$endif ndef FPC_SYSTEM_HAS_FPC_SHORTSTR_ASSIGN}

{$ifndef FPC_SYSTEM_HAS_FPC_SHORTSTR_CONCAT}

procedure fpc_shortstr_concat(var dests:shortstring;const s1,s2:shortstring);compilerproc;
var
  s1l, s2l : longint;
begin
  s1l:=length(s1);
  s2l:=length(s2);
  if s1l+s2l>high(dests) then
    s2l:=high(dests)-s1l;
  if @dests=@s1 then
    move(s2[1],dests[s1l+1],s2l)
  else
    if @dests=@s2 then
      begin
        move(dests[1],dests[s1l+1],s2l);
        move(s1[1],dests[1],s1l);
      end
  else
    begin
      move(s1[1],dests[1],s1l);
      move(s2[1],dests[s1l+1],s2l);
    end;
  dests[0]:=chr(s1l+s2l);
end;
{$endif ndef FPC_SYSTEM_HAS_FPC_SHORTSTR_CONCAT}


{$ifndef FPC_SYSTEM_HAS_FPC_SHORTSTR_APPEND_SHORTSTR}
procedure fpc_shortstr_append_shortstr(var s1:shortstring;const s2:shortstring);compilerproc;
    [public,alias:'FPC_SHORTSTR_APPEND_SHORTSTR'];
var
  s1l, s2l : byte;
begin
  s1l:=length(s1);
  s2l:=length(s2);
  if s1l+s2l>high(s1) then
    s2l:=high(s1)-s1l;
  move(s2[1],s1[s1l+1],s2l);
  s1[0]:=chr(s1l+s2l);
end;
{$endif ndef FPC_SYSTEM_HAS_FPC_SHORTSTR_APPEND_SHORTSTR}


{$ifndef FPC_SYSTEM_HAS_FPC_SHORTSTR_COMPARE}
function fpc_shortstr_compare(const left,right:shortstring) : longint;[public,alias:'FPC_SHORTSTR_COMPARE']; compilerproc;
var
   s1,s2,max,i : byte;
   d : longint;
begin
  s1:=length(left);
  s2:=length(right);
  if s1<s2 then
    max:=s1
  else
    max:=s2;
  for i:=1 to max do
    begin
     d:=byte(left[i])-byte(right[i]);
     if d>0 then
       exit(1)
     else if d<0 then
       exit(-1);
    end;
  if s1>s2 then
    exit(1)
  else if s1<s2 then
    exit(-1)
  else
    exit(0);
end;

{$endif ndef FPC_SYSTEM_HAS_FPC_SHORTSTR_COMPARE}

{$ifndef FPC_SYSTEM_HAS_FPC_SHORTSTR_COMPARE_EQUAL}
function fpc_shortstr_compare_equal(const left,right:shortstring): longint; [public,alias:'FPC_SHORTSTR_COMPARE_EQUAL']; compilerproc;
begin
  Result := longint(left[0]) - longint(right[0]);
  if Result = 0 then
    Result := CompareByte(left[1],right[1], longint(left[0]));
end;
{$endif ndef FPC_SYSTEM_HAS_FPC_SHORTSTR_COMPARE_EQUAL}

{$ifndef FPC_STRTOSHORTSTRINGPROC}

function fpc_pchar_to_shortstr(p:pchar):shortstring;[public,alias:'FPC_PCHAR_TO_SHORTSTR']; compilerproc;
var
  l : longint;
  s: shortstring;
begin
  if p=nil then
    l:=0
  else
    l:=strlen(p);
  if l>255 then
    l:=255;
  if l>0 then
    move(p^,s[1],l);
  s[0]:=chr(l);
  fpc_pchar_to_shortstr := s;
end;

{$endif ndef FPC_STRTOSHORTSTRINGPROC}


{$ifndef FPC_SYSTEM_HAS_FPC_CHARARRAY_TO_SHORTSTR}

function fpc_chararray_to_shortstr(const arr: array of char):shortstring;[public,alias:'FPC_CHARARRAY_TO_SHORTSTR']; compilerproc;
var
  l: longint;
 index: longint;
 len: byte;
begin
  l := high(arr)+1;
  if l>=256 then
    l:=255
  else if l<0 then
    l:=0;
  index:=IndexByte(arr[0],l,0);
  if (index < 0) then
    len := l
  else
    len := index;
  move(arr[0],fpc_chararray_to_shortstr[1],len);
  fpc_chararray_to_shortstr[0]:=chr(len);
end;

{$endif ndef FPC_SYSTEM_HAS_FPC_CHARARRAY_TO_SHORTSTR}


{$ifndef FPC_SYSTEM_HAS_FPC_SHORTSTR_TO_CHARARRAY}

{ inside the compiler, the resulttype is modified to that of the actual }
{ chararray we're converting to (JM)                                    }
function fpc_shortstr_to_chararray(arraysize: longint; const src: ShortString): fpc_big_chararray;[public,alias: 'FPC_SHORTSTR_TO_CHARARRAY']; compilerproc;
var
  len: longint;
begin
  len := length(src);
  if len > arraysize then
    len := arraysize;
  { make sure we don't access char 1 if length is 0 (JM) }
  if len > 0 then
    move(src[1],fpc_shortstr_to_chararray[0],len);
  fillchar(fpc_shortstr_to_chararray[len],arraysize-len,0);
end;

{$endif FPC_SYSTEM_HAS_FPC_SHORTSTR_TO_CHARARRAY}

{$ifndef FPC_STRTOSHORTSTRINGPROC}
{function fpc_pchar_to_shortstr(p:pchar):shortstring;[public,alias:'FPC_PCHAR_TO_SHORTSTR']; compilerproc;
var
  l : longint;
  s: shortstring;
begin
  if p=nil then
    l:=0
  else
    l:=strlen(p);
  if l>255 then
    l:=255;
  if l>0 then
    move(p^,s[1],l);
  s[0]:=chr(l);
  fpc_pchar_to_shortstr := s;
end;
}
{$else FPC_STRTOSHORTSTRINGPROC}

procedure fpc_pchar_to_shortstr(out res : shortstring;p:pchar);[public,alias:'FPC_PCHAR_TO_SHORTSTR']; compilerproc;
var
  l : longint;
  s: shortstring;
begin
  if p=nil then
    l:=0
  else
    l:=strlen(p);
  if l>high(res) then
    l:=high(res);
  if l>0 then
    move(p^,s[1],l);
  s[0]:=chr(l);
  res:=s;
end;

{$endif FPC_STRTOSHORTSTRINGPROC}

{$ifndef FPC_SYSTEM_HAS_FPC_PCHAR_LENGTH}

function fpc_pchar_length(p:pchar):longint;[public,alias:'FPC_PCHAR_LENGTH']; compilerproc;
var i : longint;
begin
  i:=0;
  while p[i]<>#0 do inc(i);
  exit(i);
end;

{$endif ndef FPC_SYSTEM_HAS_FPC_PCHAR_LENGTH}



{****************************************************************************
                       Caller/StackFrame Helpers
****************************************************************************}

{$ifndef FPC_SYSTEM_HAS_GET_FRAME}
{_$error Get_frame must be defined for each processor }
{$endif ndef FPC_SYSTEM_HAS_GET_FRAME}

{$ifndef FPC_SYSTEM_HAS_GET_CALLER_ADDR}
{_$error Get_caller_addr must be defined for each processor }
{$endif ndef FPC_SYSTEM_HAS_GET_CALLER_ADDR}

{$ifndef FPC_SYSTEM_HAS_GET_CALLER_FRAME}
{_$error Get_caller_frame must be defined for each processor }
{$endif ndef FPC_SYSTEM_HAS_GET_CALLER_FRAME}

{****************************************************************************
                                 Math
****************************************************************************}


{****************************************************************************}

{$ifndef FPC_SYSTEM_HAS_ABS_LONGINT}
function abs(l:longint):longint;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
   if l<0 then
     abs:=-l
   else
     abs:=l;
end;

{$endif not FPC_SYSTEM_HAS_ABS_LONGINT}

{$ifndef FPC_SYSTEM_HAS_ODD_LONGINT}

function odd(l:longint):boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
   odd:=boolean(l and 1);
end;

{$endif ndef FPC_SYSTEM_HAS_ODD_LONGINT}

{$ifndef FPC_SYSTEM_HAS_ODD_LONGWORD}

function odd(l:longword):boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
   odd:=boolean(l and 1);
end;

{$endif ndef FPC_SYSTEM_HAS_ODD_LONGWORD}


{$ifndef FPC_SYSTEM_HAS_ODD_INT64}

function odd(l:int64):boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
   odd:=boolean(longint(l) and 1);
end;

{$endif ndef FPC_SYSTEM_HAS_ODD_INT64}

{$ifndef FPC_SYSTEM_HAS_ODD_QWORD}

function odd(l:qword):boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
   odd:=boolean(longint(l) and 1);
end;

{$endif ndef FPC_SYSTEM_HAS_ODD_QWORD}

{$ifndef FPC_SYSTEM_HAS_SQR_LONGINT}

function sqr(l:longint):longint;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
   sqr:=l*l;
end;

{$endif ndef FPC_SYSTEM_HAS_SQR_LONGINT}


{$ifndef FPC_SYSTEM_HAS_ABS_INT64}

function abs(l: Int64): Int64;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  if l < 0 then
    abs := -l
  else
    abs := l;
end;

{$endif ndef FPC_SYSTEM_HAS_ABS_INT64}


{$ifndef FPC_SYSTEM_HAS_SQR_INT64}

function sqr(l: Int64): Int64;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  sqr := l*l;
end;

{$endif ndef FPC_SYSTEM_HAS_SQR_INT64}


{$ifndef FPC_SYSTEM_HAS_SQR_QWORD}

function sqr(l: QWord): QWord;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  sqr := l*l;
end;

{$endif ndef FPC_SYSTEM_HAS_SQR_INT64}

{$ifndef FPC_SYSTEM_HAS_SPTR}
{_$error Sptr must be defined for each processor }
{$endif ndef FPC_SYSTEM_HAS_SPTR}


function align(addr : PtrUInt;alignment : PtrUInt) : PtrUInt;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    if addr mod alignment<>0 then
      result:=addr+(alignment-(addr mod alignment))
    else
      result:=addr;
  end;


function align(addr : Pointer; alignment : PtrUInt) : Pointer;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    if PtrUInt(addr) mod alignment <> 0 then
      result:=pointer(addr+(alignment-(PtrUInt(addr) mod alignment)))
    else
      result:=addr;
  end;


{****************************************************************************
                                 Str()
****************************************************************************}

{$ifndef FPC_SYSTEM_HAS_INT_STR_LONGINT}

procedure int_str(l:longint;out s:string);
var
  m,m1 : longword;
  pc,pc2 : pchar;
  hs : string[32];
  b : longint;
begin
  pc2:=@s[1];
  if (l<0) then
    begin
      b:=1;
      pc2^:='-';
      inc(pc2);
      m:=longword(-l);
    end
  else
    begin
      b:=0;
      m:=longword(l);
    end;
  pc:=@hs[0];
  repeat
    inc(pc);
    m1:=m div 10;
    pc^:=char(m-(m1*10)+byte('0'));
    m:=m1;
  until m=0;
  while (pc>pchar(@hs[0])) and
        (b<high(s)) do
    begin
      pc2^:=pc^;
      dec(pc);
      inc(pc2);
      inc(b);
    end;
  s[0]:=chr(b);
end;

{$endif ndef FPC_SYSTEM_HAS_INT_STR_LONGINT}

{$ifndef FPC_SYSTEM_HAS_INT_STR_LONGWORD}

procedure int_str(l:longword;out s:string);
var
  m1 : longword;
  b: longint;
  pc,pc2 : pchar;
  hs : string[32];
begin
  pc2:=@s[1];
  pc:=@hs[0];
  repeat
    inc(pc);
    m1:=l div 10;
    pc^:=char(l-(m1*10)+byte('0'));
    l:=m1;
  until l=0;
  b:=0;
  while (pc>pchar(@hs[0])) and
        (b<high(s)) do
    begin
      pc2^:=pc^;
      dec(pc);
      inc(pc2);
      inc(b);
    end;
  s[0]:=chr(b);
end;

{$endif ndef FPC_SYSTEM_HAS_INT_STR_LONGWORD}

{$ifndef FPC_SYSTEM_HAS_INT_STR_INT64}

procedure int_str(l:int64;out s:string);
var
  m,m1 : qword;
  pc,pc2 : pchar;
  b: longint;
  hs : string[64];
begin
  pc2:=@s[1];
  if (l<0) then
    begin
      b:=1;
      pc2^:='-';
      inc(pc2);
      m:=qword(-l);
    end
  else
    begin
      b:=0;
      m:=qword(l);
    end;
  pc:=@hs[0];
  repeat
    inc(pc);
    m1:=m div 10;
    pc^:=char(m-(m1*10)+byte('0'));
    m:=m1;
  until m=0;
  while (pc>pchar(@hs[0])) and
        (b < high(s)) do
    begin
      pc2^:=pc^;
      dec(pc);
      inc(pc2);
      inc(b);
    end;
  s[0]:=chr(b);
end;

{$endif ndef FPC_SYSTEM_HAS_INT_STR_INT64}

{$ifndef FPC_SYSTEM_HAS_INT_STR_QWORD}

procedure int_str(l:qword;out s:string);
var
  m1 : qword;
  pc,pc2 : pchar;
  b: longint;
  hs : string[64];
begin
  pc2:=@s[1];
  pc:=@hs[0];
  repeat
    inc(pc);
    m1:=l div 10;
    pc^:=char(l-(m1*10)+byte('0'));
    l:=m1;
  until l=0;
  b:=0;
  while (pc>pchar(@hs[0])) and
        (b<high(s)) do
    begin
      pc2^:=pc^;
      dec(pc);
      inc(pc2);
      inc(b);
    end;
  s[0]:=chr(b);
end;

{$endif ndef FPC_SYSTEM_HAS_INT_STR_QWORD}

{$ifndef FPC_SYSTEM_HAS_SYSRESETFPU}

procedure SysResetFpu;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  { nothing todo }
end;

{$endif FPC_SYSTEM_HAS_SYSRESETFPU}


{****************************************************************************
                                Set Handling
****************************************************************************}

{ Include set support which is processor specific}
{ Include generic pascal routines for sets if the processor }
{ specific routines are not available.                      }

{$ifndef FPC_SYSTEM_HAS_FPC_SET_LOAD_SMALL}
{ Error No pascal version of FPC_SET_LOAD_SMALL}
 { THIS DEPENDS ON THE ENDIAN OF THE ARCHITECTURE!
   Not anymore PM}

function fpc_set_load_small(l: fpc_small_set): fpc_normal_set; [public,alias:'FPC_SET_LOAD_SMALL']; compilerproc;
 {
  load a normal set p from a smallset l
 }
 begin
   fpc_set_load_small[0] := l;
   FillDWord(fpc_set_load_small[1],7,0);
 end;
{$endif FPC_SYSTEM_HAS_FPC_SET_LOAD_SMALL}


{$ifndef FPC_SYSTEM_HAS_FPC_SET_CREATE_ELEMENT}
function fpc_set_create_element(b : byte): fpc_normal_set;[public,alias:'FPC_SET_CREATE_ELEMENT']; compilerproc;
 {
  create a new set in p from an element b
 }
 begin
   FillDWord(fpc_set_create_element,SizeOf(fpc_set_create_element) div 4,0);
   fpc_set_create_element[b div 32] := 1 shl (b mod 32);
 end;
{$endif FPC_SYSTEM_HAS_FPC_SET_CREATE_ELEMENT}

{$ifndef FPC_SYSTEM_HAS_FPC_SET_SET_BYTE}

 function fpc_set_set_byte(const source: fpc_normal_set; b : byte): fpc_normal_set; compilerproc;
 {
  add the element b to the set "source"
 }
  var
   c: longint;
  begin
    move(source,fpc_set_set_byte,sizeof(source));
    c := fpc_set_set_byte[b div 32];
    c := (1 shl (b mod 32)) or c;
    fpc_set_set_byte[b div 32] := c;
  end;
{$endif FPC_SYSTEM_HAS_FPC_SET_SET_BYTE}


{$ifndef FPC_SYSTEM_HAS_FPC_SET_UNSET_BYTE}

function fpc_set_unset_byte(const source: fpc_normal_set; b : byte): fpc_normal_set; compilerproc;
 {
   suppresses the element b to the set pointed by p
   used for exclude(set,element)
 }
  var
   c: longint;
  begin
    move(source,fpc_set_unset_byte,sizeof(source));
    c := fpc_set_unset_byte[b div 32];
    c := c and not (1 shl (b mod 32));
    fpc_set_unset_byte[b div 32] := c;
  end;
{$endif FPC_SYSTEM_HAS_FPC_SET_UNSET_BYTE}


{$ifndef FPC_SYSTEM_HAS_FPC_SET_SET_RANGE}
 function fpc_set_set_range(const orgset: fpc_normal_set; l,h : byte): fpc_normal_set; compilerproc;
 {
   adds the range [l..h] to the set orgset
 }
  var
   i: integer;
   c: longint;
  begin
    move(orgset,fpc_set_set_range,sizeof(orgset));
    for i:=l to h do
      begin
        c := fpc_set_set_range[i div 32];
        c := (1 shl (i mod 32)) or c;
        fpc_set_set_range[i div 32] := c;
      end;
  end;
{$endif ndef FPC_SYSTEM_HAS_FPC_SET_SET_RANGE}


{$ifndef FPC_SYSTEM_HAS_FPC_SET_IN_BYTE}

 function fpc_set_in_byte(const p: fpc_normal_set; b: byte): boolean; [public,alias:'FPC_SET_IN_BYTE']; compilerproc; 
 {
   tests if the element b is in the set p the carryflag is set if it present
 }
  begin
    fpc_set_in_byte := (p[b div 32] and (1 shl (b mod 32))) <> 0;
  end;
{$endif}


{$ifndef FPC_SYSTEM_HAS_FPC_SET_ADD_SETS}
 function fpc_set_add_sets(const set1,set2: fpc_normal_set): fpc_normal_set;[public,alias:'FPC_SET_ADD_SETS']; compilerproc;
 var
   dest: fpc_normal_set absolute fpc_set_add_sets;
 {
   adds set1 and set2 into set dest
 }
  var
    i: integer;
   begin
     for i:=0 to 7 do
       dest[i] := set1[i] or set2[i];
   end;
{$endif}


{$ifndef FPC_SYSTEM_HAS_FPC_SET_MUL_SETS}
 function fpc_set_mul_sets(const set1,set2: fpc_normal_set): fpc_normal_set;[public,alias:'FPC_SET_MUL_SETS']; compilerproc;
 var
   dest: fpc_normal_set absolute fpc_set_mul_sets;
 {
   multiplies (takes common elements of) set1 and set2 result put in dest
 }
   var
    i: integer;
   begin
     for i:=0 to 7 do
       dest[i] := set1[i] and set2[i];
   end;
{$endif}


{$ifndef FPC_SYSTEM_HAS_FPC_SET_SUB_SETS}
 function fpc_set_sub_sets(const set1,set2: fpc_normal_set): fpc_normal_set;[public,alias:'FPC_SET_SUB_SETS']; compilerproc;
 var
   dest: fpc_normal_set absolute fpc_set_sub_sets;
 {
  computes the diff from set1 to set2 result in dest
 }
   var
    i: integer;
   begin
     for i:=0 to 7 do
       dest[i] := set1[i] and not set2[i];
   end;
{$endif}


{$ifndef FPC_SYSTEM_HAS_FPC_SET_SYMDIF_SETS}
 function fpc_set_symdif_sets(const set1,set2: fpc_normal_set): fpc_normal_set;[public,alias:'FPC_SET_SYMDIF_SETS']; compilerproc;
 var
   dest: fpc_normal_set absolute fpc_set_symdif_sets;
 {
   computes the symetric diff from set1 to set2 result in dest
 }
   var
    i: integer;
   begin
     for i:=0 to 7 do
       dest[i] := set1[i] xor set2[i];
   end;
{$endif}

{$ifndef FPC_SYSTEM_HAS_FPC_SET_COMP_SETS}
 function fpc_set_comp_sets(const set1,set2 : fpc_normal_set):boolean;[public,alias:'FPC_SET_COMP_SETS'];compilerproc;
 {
  compares set1 and set2 zeroflag is set if they are equal
 }
   var
    i: integer;
   begin
     fpc_set_comp_sets:= False;
     for i:=0 to 7 do
       if set1[i] <> set2[i] then
         exit;
     fpc_set_comp_sets:= True;
   end;
{$endif}



{$ifndef FPC_SYSTEM_HAS_FPC_SET_CONTAINS_SET}
 function fpc_set_contains_sets(const set1,set2 : fpc_normal_set):boolean;[public,alias:'FPC_SET_CONTAINS_SETS'];compilerproc;
 {
  on exit, zero flag is set if set1 <= set2 (set2 contains set1)
 }
 var
  i : integer;
 begin
   fpc_set_contains_sets:= False;
   for i:=0 to 7 do
     if (set1[i] and not set2[i]) <> 0 then
       exit;
   fpc_set_contains_sets:= True;
 end;
{$endif}



{****************************************************************************
                               Math Routines
****************************************************************************}

function Hi(b : byte): byte;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
   Hi := b shr 4
end;

function Lo(b : byte): byte;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
   Lo := b and $0f
end;

Function swap (X : Word) : Word;{$ifdef SYSTEMINLINE}inline;{$endif}
Begin
  swap:=(X and $ff) shl 8 + (X shr 8)
End;

Function Swap (X : Integer) : Integer;{$ifdef SYSTEMINLINE}inline;{$endif}
Begin
  swap:=(X and $ff) shl 8 + (X shr 8)
End;

Function swap (X : Longint) : Longint;{$ifdef SYSTEMINLINE}inline;{$endif}
Begin
  Swap:=(X and $ffff) shl 16 + (X shr 16)
End;

Function Swap (X : Cardinal) : Cardinal;{$ifdef SYSTEMINLINE}inline;{$endif}
Begin
  Swap:=(X and $ffff) shl 16 + (X shr 16)
End;

Function Swap (X : QWord) : QWord;{$ifdef SYSTEMINLINE}inline;{$endif}
Begin
  Swap:=(X and $ffffffff) shl 32 + (X shr 32);
End;

Function swap (X : Int64) : Int64;{$ifdef SYSTEMINLINE}inline;{$endif}
Begin
  Swap:=(X and $ffffffff) shl 32 + (X shr 32);
End;


{****************************************************************************
                    subroutines for string handling
****************************************************************************}

procedure fpc_Shortstr_SetLength(var s:shortstring;len:SizeInt);[Public,Alias : 'FPC_SHORTSTR_SETLENGTH']; compilerproc;
begin
  if Len>255 then
   Len:=255;
  s[0]:=chr(len);
end;

function fpc_shortstr_copy(const s : shortstring;index : SizeInt;count : SizeInt): shortstring;compilerproc;
begin
  if count<0 then
   count:=0;
  if index>1 then
   dec(index)
  else
   index:=0;
  if index>length(s) then
   count:=0
  else
   if count>length(s)-index then
    count:=length(s)-index;
  fpc_shortstr_Copy[0]:=chr(Count);
  Move(s[Index+1],fpc_shortstr_Copy[1],Count);
end;

function pos(const substr : shortstring;const s : shortstring):SizeInt;
var
  i,MaxLen : SizeInt;
  pc : pchar;
begin
  Pos:=0;
  if Length(SubStr)>0 then
   begin
     MaxLen:=Length(s)-Length(SubStr);
     i:=0;
     pc:=@s[1];
     while (i<=MaxLen) do
      begin
        inc(i);
        if (SubStr[1]=pc^) and
           (CompareChar(Substr[1],pc^,Length(SubStr))=0) then
         begin
           Pos:=i;
           exit;
         end;
        inc(pc);
      end;
   end;
end;

procedure InttoStr(Value: PtrUInt; buff: pchar);
var
  I, Len: Byte;
  // 21 is the max number of characters needed to represent 64 bits number in decimal
  S: string[21];
begin
  Len := 0;
  I := 21;
  if Value = 0 then
  begin
    buff^ := '0';
    buff  := buff + 1;
    buff^ := #0;
  end else
  begin
    while Value <> 0 do
    begin
      S[I] := AnsiChar((Value mod 10) + $30);
      Value := Value div 10;
      I := I-1;
      Len := Len+1;
    end;
    S[0] := Char(Len);
   for I := (sizeof(S)-Len) to sizeof(S)-1 do
   begin
    buff^ := S[I];
    buff +=1;
   end;
   buff^ := #0;
  end;
end;

procedure StrConcat(left, right, dst: pchar);
begin
  Move(left^,dst^,Length(left));
  dst := dst + Length(left);
  Move(right^,dst^,Length(right));
  dst +=Length(right);
  dst^ := #0;
end;

function StrCmp(p1, p2: pchar; Len: LongInt): Boolean;
var
   i: LongInt;
begin
 result:= false;
 for i:= 0 to Len-1 do
 begin
  if (p1^ <> p2^) then
  begin
    Exit;
  end;
  p1 += 1;
  p2 += 1;
 end;
result := true;
end;


{Faster when looking for a single char...}
function pos(c:char;const s:shortstring):SizeInt;
var
  i : SizeInt;
  pc : pchar;
begin
  pc:=@s[1];
  for i:=1 to length(s) do
   begin
     if pc^=c then
      begin
        pos:=i;
        exit;
      end;
     inc(pc);
   end;
  pos:=0;
end;


function fpc_char_copy(c:char;index : SizeInt;count : SizeInt): shortstring;compilerproc;
begin
  if (index=1) and (Count>0) then
   fpc_char_Copy:=c
  else
   fpc_char_Copy:='';
end;

function pos(const substr : shortstring;c:char): SizeInt;
begin
  if (length(substr)=1) and (substr[1]=c) then
   Pos:=1
  else
   Pos:=0;
end;

function upcase(c : char) : char;
begin
  if (c in ['a'..'z']) then
    upcase:=char(byte(c)-32)
  else
   upcase:=c;
end;


function upcase(const s : shortstring) : shortstring;
var
  i : longint;
begin
  upcase[0]:=s[0];
  for i := 1 to length (s) do
    upcase[i] := upcase (s[i]);
end;


function lowercase(c : char) : char;overload;
begin
  if (c in ['A'..'Z']) then
   lowercase:=char(byte(c)+32)
  else
   lowercase:=c;
end;


function lowercase(const s : shortstring) : shortstring; overload;
var
  i : longint;
begin
  lowercase [0]:=s[0];
  for i:=1 to length(s) do
   lowercase[i]:=lowercase (s[i]);
end;


const
  HexTbl : array[0..15] of char='0123456789ABCDEF';

function hexstr(val : longint;cnt : byte) : shortstring;
var
  i : longint;
begin
  hexstr[0]:=char(cnt);
  for i:=cnt downto 1 do
   begin
     hexstr[i]:=hextbl[val and $f];
     val:=val shr 4;
   end;
end;

function octstr(val : longint;cnt : byte) : shortstring;
var
  i : longint;
begin
  octstr[0]:=char(cnt);
  for i:=cnt downto 1 do
   begin
     octstr[i]:=hextbl[val and 7];
     val:=val shr 3;
   end;
end;


function binstr(val : longint;cnt : byte) : shortstring;
var
  i : longint;
begin
  binstr[0]:=char(cnt);
  for i:=cnt downto 1 do
   begin
     binstr[i]:=char(48+val and 1);
     val:=val shr 1;
   end;
end;


function hexstr(val : int64;cnt : byte) : shortstring;
var
  i : longint;
begin
  hexstr[0]:=char(cnt);
  for i:=cnt downto 1 do
   begin
     hexstr[i]:=hextbl[val and $f];
     val:=val shr 4;
   end;
end;


function octstr(val : int64;cnt : byte) : shortstring;
var
  i : longint;
begin
  octstr[0]:=char(cnt);
  for i:=cnt downto 1 do
   begin
     octstr[i]:=hextbl[val and 7];
     val:=val shr 3;
   end;
end;


function binstr(val : int64;cnt : byte) : shortstring;
var
  i : longint;
begin
  binstr[0]:=char(cnt);
  for i:=cnt downto 1 do
   begin
     binstr[i]:=char(48+val and 1);
     val:=val shr 1;
   end;
end;


function hexstr(val : pointer) : shortstring;
var
  i : longint;
  v : ptrint;
begin
  v:=ptrint(val);
  hexstr[0]:=chr(sizeof(pointer)*2);
  for i:=sizeof(pointer)*2 downto 1 do
   begin
     hexstr[i]:=hextbl[v and $f];
     v:=v shr 4;
   end;
end;


function space (b : byte): shortstring;
begin
  space[0] := chr(b);
  FillChar (Space[1],b,' ');
end;


{*****************************************************************************
                              Str() Helpers
*****************************************************************************}

procedure fpc_shortstr_SInt(v : valSInt;len : SizeInt;out s : shortstring);[public,alias:'FPC_SHORTSTR_SINT']; compilerproc;
begin
  int_str(v,s);
  if length(s)<len then
    s:=space(len-length(s))+s;
end;

procedure fpc_shortstr_UInt(v : valUInt;len : SizeInt;var s : shortstring);[public,alias:'FPC_SHORTSTR_UINT']; compilerproc;
begin
  int_str(v,s);
  if length(s)<len then
    s:=space(len-length(s))+s;
end;


{
   Array Of Char Str() helpers
}

procedure fpc_chararray_sint(v : valsint;len : SizeInt;var a:array of char);compilerproc;
var
  ss : shortstring;
  maxlen : SizeInt;
begin
  int_str(v,ss);
  if length(ss)<len then
    ss:=space(len-length(ss))+ss;
  if length(ss)<high(a)+1 then
    maxlen:=length(ss)
  else
    maxlen:=high(a)+1;
  move(ss[1],pchar(@a)^,maxlen);
end;


procedure fpc_chararray_uint(v : valuint;len : SizeInt;var a : array of char);compilerproc;
var
  ss : shortstring;
  maxlen : SizeInt;
begin
  int_str(v,ss);
  if length(ss)<len then
    ss:=space(len-length(ss))+ss;
  if length(ss)<high(a)+1 then
    maxlen:=length(ss)
  else
    maxlen:=high(a)+1;
  move(ss[1],pchar(@a)^,maxlen);
end;

{*****************************************************************************
                           Val() Functions
*****************************************************************************}

Function InitVal(const s:shortstring;var negativ:boolean;var base:byte):ValSInt;
var
  Code : SizeInt;
begin
{Skip Spaces and Tab}
  code:=1;
  while (code<=length(s)) and (s[code] in [' ',#9]) do
   inc(code);
{Sign}
  negativ:=False;
  case s[code] of
   '-' : begin
           negativ:=True;
           inc(code);
         end;
   '+' : inc(code);
  end;
{Base}
  base:=10;
  if code<=length(s) then
   begin
     case s[code] of
      '$' : begin
              base:=16;
              inc(code);
            end;
      '%' : begin
              base:=2;
              inc(code);              
            end;
      '&' : begin
              Base:=8;
              inc(code);              
            end;
      '0' : begin
              if (code < length(s)) and (s[code+1] in ['x', 'X']) then 
              begin
                inc(code, 2);
                base := 16;
              end;
            end;
     end;
  end;
  { strip leading zeros }
  while ((code < length(s)) and (s[code] = '0')) do begin
    inc(code);
  end;
  InitVal:=code;
end;


Function fpc_Val_SInt_ShortStr(DestSize: SizeInt; Const S: ShortString; var Code: ValSInt): ValSInt; [public, alias:'FPC_VAL_SINT_SHORTSTR']; compilerproc;
var
  u, temp, prev, maxPrevValue, maxNewValue: ValUInt;
  base : byte;
  negative : boolean;
begin
  fpc_Val_SInt_ShortStr := 0;
  Temp:=0;
  Code:=InitVal(s,negative,base);
  if Code>length(s) then
   exit;
  maxPrevValue := ValUInt(MaxUIntValue) div ValUInt(Base);
  if (base = 10) then
    maxNewValue := MaxSIntValue + ord(negative)
  else
    maxNewValue := MaxUIntValue;
  while Code<=Length(s) do
   begin
     case s[Code] of
       '0'..'9' : u:=Ord(S[Code])-Ord('0');
       'A'..'F' : u:=Ord(S[Code])-(Ord('A')-10);
       'a'..'f' : u:=Ord(S[Code])-(Ord('a')-10);
     else
      u:=16;
     end;
     Prev := Temp;
     Temp := Temp*ValUInt(base);
     If (u >= base) or
        (ValUInt(maxNewValue-u) < Temp) or
        (prev > maxPrevValue) Then
       Begin
         fpc_Val_SInt_ShortStr := 0;
         Exit
       End;
     Temp:=Temp+u;
     inc(code);
   end;
  code := 0;
  fpc_Val_SInt_ShortStr := ValSInt(Temp);
  If Negative Then
    fpc_Val_SInt_ShortStr := -fpc_Val_SInt_ShortStr;
  If Not(Negative) and (base <> 10) Then
   {sign extend the result to allow proper range checking}
    Case DestSize of
      1: fpc_Val_SInt_ShortStr := shortint(fpc_Val_SInt_ShortStr);
      2: fpc_Val_SInt_ShortStr := smallint(fpc_Val_SInt_ShortStr);
{     Uncomment the folling once full 64bit support is in place
      4: fpc_Val_SInt_ShortStr := SizeInt(fpc_Val_SInt_ShortStr);}
    End;
end;

{ we need this for fpc_Val_SInt_Ansistr and fpc_Val_SInt_WideStr because }
{ we have to pass the DestSize parameter on (JM)                         }
Function int_Val_SInt_ShortStr(DestSize: SizeInt; Const S: ShortString; var Code: ValSInt): ValSInt; [external name 'FPC_VAL_SINT_SHORTSTR'];


Function fpc_Val_UInt_Shortstr(Const S: ShortString; var Code: ValSInt): ValUInt; [public, alias:'FPC_VAL_UINT_SHORTSTR']; compilerproc;
var
  u, prev : ValUInt;
  base : byte;
  negative : boolean;
begin
  fpc_Val_UInt_Shortstr:=0;
  Code:=InitVal(s,negative,base);
  If Negative or (Code>length(s)) Then
    Exit;
  while Code<=Length(s) do
   begin
     case s[Code] of
       '0'..'9' : u:=Ord(S[Code])-Ord('0');
       'A'..'F' : u:=Ord(S[Code])-(Ord('A')-10);
       'a'..'f' : u:=Ord(S[Code])-(Ord('a')-10);
     else
      u:=16;
     end;
     prev := fpc_Val_UInt_Shortstr;
     If (u>=base) or
        (ValUInt(MaxUIntValue-u) div ValUInt(Base)<prev) then
      begin
        fpc_Val_UInt_Shortstr:=0;
        exit;
      end;
     fpc_Val_UInt_Shortstr:=fpc_Val_UInt_Shortstr*ValUInt(base) + u;
     inc(code);
   end;
  code := 0;
end;



Function fpc_Val_Real_ShortStr(const s : shortstring; var code : ValSInt): ValReal; [public, alias:'FPC_VAL_REAL_SHORTSTR']; compilerproc;
var
  hd,
  esign,sign : valreal;
  exponent,i : SizeInt;
  flags      : byte;
begin
  fpc_Val_Real_ShortStr:=0.0;
  code:=1;
  exponent:=0;
  esign:=1;
  flags:=0;
  sign:=1;
  while (code<=length(s)) and (s[code] in [' ',#9]) do
   inc(code);
  case s[code] of
   '+' : inc(code);
   '-' : begin
           sign:=-1;
           inc(code);
         end;
  end;
  while (Code<=Length(s)) and (s[code] in ['0'..'9']) do
   begin
   { Read integer part }
      flags:=flags or 1;

fpc_Val_Real_ShortStr:=fpc_Val_Real_ShortStr*10+(ord(s[code])-ord('0'));
      inc(code);
   end;
{ Decimal ? }
  if (length(s)>=code) and (s[code]='.') then
   begin
      hd:=1.0;
      inc(code);
      while (length(s)>=code) and (s[code] in ['0'..'9']) do
        begin
           { Read fractional part. }
           flags:=flags or 2;
           fpc_Val_Real_ShortStr:=fpc_Val_Real_ShortStr*10+(ord(s[code])-ord('0'));
           hd:=hd*10.0;
           inc(code);
        end;
      fpc_Val_Real_ShortStr:=fpc_Val_Real_ShortStr/hd;
   end;
 { Again, read integer and fractional part}
  if flags=0 then
   begin
      fpc_Val_Real_ShortStr:=0.0;
      exit;
   end;
 { Exponent ? }
  if (length(s)>=code) and (upcase(s[code])='E') then
   begin
      inc(code);
      if Length(s) >= code then
        if s[code]='+' then
          inc(code)
        else
          if s[code]='-' then
           begin
             esign:=-1;
             inc(code);
           end;
      if (length(s)<code) or not(s[code] in ['0'..'9']) then
        begin
           fpc_Val_Real_ShortStr:=0.0;
           exit;
        end;
      while (length(s)>=code) and (s[code] in ['0'..'9']) do
        begin
           exponent:=exponent*10;
           exponent:=exponent+ord(s[code])-ord('0');
           inc(code);
        end;
   end;
{ Calculate Exponent }
{
  if esign>0 then
    for i:=1 to exponent do
      fpc_Val_Real_ShortStr:=Val_Real_ShortStr*10
    else
      for i:=1 to exponent do
        fpc_Val_Real_ShortStr:=Val_Real_ShortStr/10; }
  hd:=1.0;
  for i:=1 to exponent do
    hd:=hd*10.0;
  if esign>0 then
    fpc_Val_Real_ShortStr:=fpc_Val_Real_ShortStr*hd
  else
    fpc_Val_Real_ShortStr:=fpc_Val_Real_ShortStr/hd;
{ Not all characters are read ? }
  if length(s)>=code then
   begin
     fpc_Val_Real_ShortStr:=0.0;
     exit;
   end;
{ evaluate sign }
  fpc_Val_Real_ShortStr:=fpc_Val_Real_ShortStr*sign;
{ success ! }
  code:=0;
end;


{Procedure SetString (Var S : Shortstring; Buf : PChar; Len : SizeInt);
begin
  If Len > High(S) then
    Len := High(S);
  SetLength(S,Len);
  If Buf<>Nil then
    begin
      Move (Buf[0],S[1],Len);
    end;
end;}


{$Q- no overflow checking }
{$R- no range checking }

    type
       tqwordrec = packed record
         low : dword;
         high : dword;
       end;


{$ifdef  FPC_INCLUDE_SOFTWARE_SHIFT_INT64}

{$ifndef FPC_SYSTEM_HAS_SHL_QWORD}
    function fpc_shl_qword(value,shift : qword) : qword; [public,alias: 'FPC_SHL_QWORD']; compilerproc;
      begin
        shift:=shift and 63;
        if shift=0 then
          result:=value
        else if shift>31 then
          begin
            tqwordrec(result).low:=0;
            tqwordrec(result).high:=tqwordrec(value).low shl (shift-32);
          end
        else
          begin
            tqwordrec(result).low:=tqwordrec(value).low shl shift;
            tqwordrec(result).high:=(tqwordrec(value).high shl shift) or (tqwordrec(value).low shr (32-shift));
          end;
      end;
{$endif FPC_SYSTEM_HAS_SHL_QWORD}


{$ifndef FPC_SYSTEM_HAS_SHR_QWORD}
   function fpc_shr_qword(value,shift : qword) : qword; [public,alias: 'FPC_SHR_QWORD']; compilerproc;
      begin
        shift:=shift and 63;
        if shift=0 then
          result:=value
        else if shift>31 then
          begin
            tqwordrec(result).high:=0;
            tqwordrec(result).low:=tqwordrec(value).high shr (shift-32);
          end
        else
          begin
            tqwordrec(result).high:=tqwordrec(value).high shr shift;
            tqwordrec(result).low:=(tqwordrec(value).low shr shift) or (tqwordrec(value).high shl (32-shift));
          end;
      end;
{$endif FPC_SYSTEM_HAS_SHR_QWORD}


{$ifndef FPC_SYSTEM_HAS_SHL_INT64}
    function fpc_shl_int64(value,shift : int64) : int64; [public,alias: 'FPC_SHL_INT64']; compilerproc;
      begin
        shift:=shift and 63;
        if shift=0 then
          result:=value
        else if shift>31 then
          begin
            tqwordrec(result).low:=0;
            tqwordrec(result).high:=tqwordrec(value).low shl (shift-32);
          end
        else
          begin
            tqwordrec(result).low:=tqwordrec(value).low shl shift;
            tqwordrec(result).high:=(tqwordrec(value).high shl shift) or (tqwordrec(value).low shr (32-shift));
          end;
      end;
{$endif FPC_SYSTEM_HAS_SHL_INT64}


{$ifndef FPC_SYSTEM_HAS_SHR_INT64}
    function fpc_shr_int64(value,shift : int64) : int64; [public,alias: 'FPC_SHR_INT64']; compilerproc;
      begin
        shift:=shift and 63;
        if shift=0 then
          result:=value
        else if shift>31 then
          begin
            tqwordrec(result).high:=0;
            tqwordrec(result).low:=tqwordrec(value).high shr (shift-32);
          end
        else
          begin
            tqwordrec(result).high:=tqwordrec(value).high shr shift;
            tqwordrec(result).low:=(tqwordrec(value).low shr shift) or (tqwordrec(value).high shl (32-shift));
          end;
      end;
{$endif FPC_SYSTEM_HAS_SHR_INT64}


{$endif FPC_INCLUDE_SOFTWARE_SHIFT_INT64}


    function count_leading_zeros(q : qword) : longint;

      var
         r,i : longint;

      begin
         r:=0;
         for i:=0 to 31 do
           begin
              if (tqwordrec(q).high and (dword($80000000) shr i))<>0 then
                begin
                   count_leading_zeros:=r;
                   exit;
                end;
              inc(r);
           end;
         for i:=0 to 31 do
           begin
              if (tqwordrec(q).low and (dword($80000000) shr i))<>0 then
                begin
                   count_leading_zeros:=r;
                   exit;
                end;
              inc(r);
           end;
         count_leading_zeros:=r;
      end;


{$ifndef FPC_SYSTEM_HAS_DIV_QWORD}
    function fpc_div_qword(n,z : qword) : qword;[public,alias: 'FPC_DIV_QWORD']; compilerproc;

      var
         shift,lzz,lzn : longint;

      begin
         fpc_div_qword:=0;
         if n=0 then
           HandleErrorFrame(200,get_frame);
         lzz:=count_leading_zeros(z);
         lzn:=count_leading_zeros(n);
         { if the denominator contains less zeros }
         { then the numerator                     }
         { the d is greater than the n            }
         if lzn<lzz then
           exit;
         shift:=lzn-lzz;
         n:=n shl shift;
         repeat
           if z>=n then
             begin
                z:=z-n;
                fpc_div_qword:=fpc_div_qword+(qword(1) shl shift);
             end;
           dec(shift);
           n:=n shr 1;
         until shift<0;
      end;
{$endif FPC_SYSTEM_HAS_DIV_QWORD}


{$ifndef FPC_SYSTEM_HAS_MOD_QWORD}
    function fpc_mod_qword(n,z : qword) : qword;[public,alias: 'FPC_MOD_QWORD']; compilerproc;

      var
         shift,lzz,lzn : longint;

      begin
         fpc_mod_qword:=0;
         if n=0 then
           HandleErrorFrame(200,get_frame);
         lzz:=count_leading_zeros(z);
         lzn:=count_leading_zeros(n);
         { if the denominator contains less zeros }
         { then the numerator                     }
         { the d is greater than the n            }
         if lzn<lzz then
           begin
              fpc_mod_qword:=z;
              exit;
           end;
         shift:=lzn-lzz;
         n:=n shl shift;
         repeat
           if z>=n then
             z:=z-n;
           dec(shift);
           n:=n shr 1;
         until shift<0;
         fpc_mod_qword:=z;
      end;
{$endif FPC_SYSTEM_HAS_MOD_QWORD}


{$ifndef FPC_SYSTEM_HAS_DIV_INT64}
    function fpc_div_int64(n,z : int64) : int64;[public,alias: 'FPC_DIV_INT64']; compilerproc;

      var
         sign : boolean;
         q1,q2 : qword;

      begin
         if n=0 then
           HandleErrorFrame(200,get_frame);
         { can the fpu do the work? }
           begin
              sign:=False;
              if z<0 then
                begin
                   sign:=not(sign);
                   q1:=qword(-z);
                end
              else
                q1:=z;
              if n<0 then
                begin
                   sign:=not(sign);
                   q2:=qword(-n);
                end
              else
                q2:=n;

              { the div is coded by the compiler as call to divqword }
              if sign then
                fpc_div_int64:=-(q1 div q2)
              else
                fpc_div_int64:=q1 div q2;
           end;
      end;
{$endif FPC_SYSTEM_HAS_DIV_INT64}


{$ifndef FPC_SYSTEM_HAS_MOD_INT64}
    function fpc_mod_int64(n,z : int64) : int64;[public,alias: 'FPC_MOD_INT64']; compilerproc;

      var
         signed : boolean;
         r,nq,zq : qword;

      begin
         if n=0 then
           HandleErrorFrame(200,get_frame);
         if n<0 then
           nq:=-n
         else
           nq:=n;
         if z<0 then
           begin
             signed:=True;
             zq:=qword(-z)
           end
         else
           begin
             signed:=False;
             zq:=z;
           end;
         r:=zq mod nq;
         if signed then
           fpc_mod_int64:=-int64(r)
         else
           fpc_mod_int64:=r;
      end;
{$endif FPC_SYSTEM_HAS_MOD_INT64}


{$ifndef FPC_SYSTEM_HAS_MUL_QWORD}
    { multiplies two qwords
      the longbool for checkoverflow avoids a misaligned stack
    }
    function fpc_mul_qword(f1,f2 : qword;checkoverflow : longbool) : qword;[public,alias: 'FPC_MUL_QWORD']; compilerproc;

      var
         _f1,bitpos : qword;
         l : longint;
         f1overflowed : boolean;
      begin
        fpc_mul_qword:=0;
        bitpos:=1;
        f1overflowed:=False;

        for l:=0 to 63 do
          begin
            if (f2 and bitpos)<>0 then
              begin
                _f1:=fpc_mul_qword;
                fpc_mul_qword:=fpc_mul_qword+f1;

                { if one of the operands is greater than the result an
                  overflow occurs                                      }
                if checkoverflow and (f1overflowed or ((_f1<>0) and (f1<>0) and
                  ((_f1>fpc_mul_qword) or (f1>fpc_mul_qword)))) then
                  HandleErrorFrame(215,get_frame);
              end;
            { when bootstrapping, we forget about overflow checking for qword :) }
            f1overflowed:=f1overflowed or ((f1 and (1 shl 63))<>0);
            f1:=f1 shl 1;
            bitpos:=bitpos shl 1;
          end;
      end;
{$endif FPC_SYSTEM_HAS_MUL_QWORD}


{$ifndef FPC_SYSTEM_HAS_MUL_INT64}
    function fpc_mul_int64(f1,f2 : int64;checkoverflow : longbool) : int64;[public,alias: 'FPC_MUL_INT64']; compilerproc;

      var
         sign : boolean;
         q1,q2,q3 : qword;

      begin
           begin
              sign:=False;
              if f1<0 then
                begin
                   sign:=not(sign);
                   q1:=qword(-f1);
                end
              else
                q1:=f1;
              if f2<0 then
                begin
                   sign:=not(sign);
                   q2:=qword(-f2);
                end
              else
                q2:=f2;
              { the q1*q2 is coded as call to mulqword }
              q3:=q1*q2;

              if checkoverflow and (q1 <> 0) and (q2 <>0) and
              ((q1>q3) or (q2>q3) or
                { the bit 63 can be only set if we have $80000000 00000000 }
                { and sign is True                                         }
                ((tqwordrec(q3).high and dword($80000000))<>0) and
                 ((q3<>(qword(1) shl 63)) or not(sign))
                ) then
                HandleErrorFrame(215,get_frame);

              if sign then
                fpc_mul_int64:=-q3
              else
                fpc_mul_int64:=q3;
           end;
      end;
{$endif FPC_SYSTEM_HAS_MUL_INT64}

    {$define FPC_SYSTEM_HAS_ROUND}
    function fpc_round_real(d : ValReal) : int64;assembler;compilerproc;
      var
        res   : int64;
      asm
        fldt (%rcx)
        fistpq res
        fwait
        movq res,%rax
      end;

    {$define FPC_SYSTEM_HAS_TRUNC}
    function fpc_trunc_real(d : ValReal) : int64;assembler;compilerproc;
      var
        oldcw,
        newcw : word;
        res   : int64;
      asm
        fnstcw oldcw
        fwait
        movw oldcw,%cx
        orw $0x0c3f,%cx
        movw %cx,newcw
        fldcw newcw
        fldt (%rcx)
        fistpq res
        fwait
        movq res,%rax
        fldcw oldcw
      end;



{ define EXTRAANSISHORT}

{
  This file contains the implementation of the AnsiString type,
  and all things that are needed for it.
  AnsiString is defined as a 'silent' pchar :
  a pchar that points to :

  @-8  : SizeInt for reference count;
  @-4  : SizeInt for size;
  @    : String + Terminating #0;
  Pchar(Ansistring) is a valid typecast.
  So AS[i] is converted to the address @AS+i-1.

  Constants should be assigned a reference count of -1
  Meaning that they can't be disposed of.
}

Type
  PAnsiRec = ^TAnsiRec;
  TAnsiRec = Record
    CodePage    : TSystemCodePage;
    ElementSize : Word;
{$ifdef CPU64}	
    { align fields  }
	Dummy       : DWord;
{$endif CPU64}
    Ref         : SizeInt;
    Len         : SizeInt;
  end;

Const
  AnsiFirstOff = SizeOf(TAnsiRec);
  AnsiRecLen = SizeOf(TAnsiRec);
  FirstOff   = SizeOf(TAnsiRec)-1;

{****************************************************************************}
{ Memory manager }

const
  MemoryManager: TMemoryManager = (
    NeedLock: True;
    GetMem: @SysGetMem;
    FreeMem: @SysFreeMem;
    FreeMemSize: @SysFreeMemSize;
    AllocMem: @SysAllocMem;
    ReAllocMem: @SysReAllocMem;
    MemSize: @SysMemSize;
  );

{****************************************************************************
                    Internal functions, not in interface.
****************************************************************************}



Function NewAnsiString(Len : SizeInt) : Pointer;
{
  Allocate a new AnsiString on the heap.
  initialize it to zero length and reference count 1.
}
Var
  P : Pointer;
begin
  { request a multiple of 16 because the heap manager alloctes anyways chunks of 16 bytes }
  GetMem(P,Len+(AnsiFirstOff+sizeof(char)));
  If P<>Nil then
   begin
     PAnsiRec(P)^.Ref:=1;         { Set reference count }
     PAnsiRec(P)^.Len:=0;         { Initial length }
     PAnsiRec(P)^.CodePage:=DefaultSystemCodePage;
     PAnsiRec(P)^.ElementSize:=SizeOf(AnsiChar);
     inc(p,AnsiFirstOff);         { Points to string now }
     PAnsiChar(P)^:=#0;           { Terminating #0 }
   end;
  NewAnsiString:=P;
end;


Procedure DisposeAnsiString(Var S : Pointer);
{
  Deallocates a AnsiString From the heap.
}
begin
  If S=Nil then
    exit;
  Dec (S,FirstOff);
  FreeMem(S, PAnsiRec(S)^.Len+AnsiRecLen);
  S:=Nil;
end;


Procedure fpc_AnsiStr_Decr_Ref (Var S : Pointer); [Public,Alias:'FPC_ANSISTR_DECR_REF'];  compilerproc;
{
  Decreases the ReferenceCount of a non constant ansistring;
  If the reference count is zero, deallocate the string;
}
Type
  pSizeInt = ^SizeInt;
Var
  l : pSizeInt;
Begin
  { Zero string }
  If S=Nil then exit;
  { check for constant strings ...}
  l:=@PAnsiRec(S-FirstOff)^.Ref;
  If l^<0 then exit;
  { declocked does a MT safe dec and returns True, if the counter is 0 }
  //If declocked(l^) then
    { Ref count dropped to zero }
    // TODO: to fix it properly
    DisposeAnsiString (S);        { Remove...}
end;

{ also define alias for internal use in the system unit }
Procedure fpc_AnsiStr_Decr_Ref (Var S : Pointer); [external name 'FPC_ANSISTR_DECR_REF'];

Procedure fpc_AnsiStr_Incr_Ref (S : Pointer); [Public,Alias:'FPC_ANSISTR_INCR_REF'];  compilerproc;
Begin
  If S=Nil then
    exit;
  { Let's be paranoid : Constant string ??}
  If PAnsiRec(S-FirstOff)^.Ref<0 then exit;
  inclocked(PAnsiRec(S-FirstOff)^.Ref);
end;

{ also define alias which can be used inside the system unit }
Procedure fpc_AnsiStr_Incr_Ref (S : Pointer); [external name 'FPC_ANSISTR_INCR_REF'];

//Procedure fpc_AnsiStr_Assign (Var S1 : Pointer;S2 : Pointer);[Public,Alias:'FPC_ANSISTR_ASSIGN'];  compilerproc;
//{
//  Assigns S2 to S1 (S1:=S2), taking in account reference counts./
//}
//begin
//  If S2<>nil then
//    If PAnsiRec(S2-FirstOff)^.Ref>0 then
//      inclocked(PAnsiRec(S2-FirstOff)^.ref);
  { Decrease the reference count on the old S1 }
//  fpc_ansistr_decr_ref (S1);
  { And finally, have S1 pointing to S2 (or its copy) }
//  S1:=S2;
//end;

{ alias for internal use }
//Procedure fpc_AnsiStr_Assign (Var S1 : Pointer;S2 : Pointer);[external name 'FPC_ANSISTR_ASSIGN'];

//{$define FPC_HAS_ANSISTR_ASSIGN}
Procedure fpc_AnsiStr_Assign (Var DestS : Pointer;S2 : Pointer);[Public,Alias:'FPC_ANSISTR_ASSIGN'];  compilerproc;
{
  Assigns S2 to S1 (S1:=S2), taking in account reference counts.
}
begin
  if DestS=S2 then
    exit;
  If S2<>nil then
    If PAnsiRec(S2-AnsiFirstOff)^.Ref>0 then
      inclocked(PAnsiRec(S2-AnsiFirstOff)^.Ref);
  { Decrease the reference count on the old S1 }
  fpc_ansistr_decr_ref (DestS);
  { And finally, have DestS pointing to S2 (or its copy) }
  DestS:=S2;
end;
//{$endif FPC_HAS_ANSISTR_ASSIGN}


{ alias for internal use }
Procedure fpc_AnsiStr_Assign (Var S1 : Pointer;S2 : Pointer);[external name 'FPC_ANSISTR_ASSIGN'];


procedure fpc_AnsiStr_Concat (var DestS:ansistring;const S1,S2 : AnsiString); compilerproc;
Var
  Size,Location : SizeInt;
  same : boolean;
begin
  { only assign if s1 or s2 is empty }
  if (S1='') then
    begin
      DestS:=s2;
      exit;
    end;
  if (S2='') then
    begin
      DestS:=s1;
      exit;
    end;
  Location:=Length(S1);
  Size:=length(S2);
  { Use Pointer() typecasts to prevent extra conversion code }
  if Pointer(DestS)=Pointer(S1) then
    begin
      same:=Pointer(S1)=Pointer(S2);
      SetLength(DestS,Size+Location);
      if same then
        Move(Pointer(DestS)^,(Pointer(DestS)+Location)^,Size)
      else
        Move(Pointer(S2)^,(Pointer(DestS)+Location)^,Size+1);
    end
  else if Pointer(DestS)=Pointer(S2) then
    begin
      SetLength(DestS,Size+Location);
      Move(Pointer(DestS)^,(Pointer(DestS)+Location)^,Size+1);
      Move(Pointer(S1)^,Pointer(DestS)^,Location);
    end
  else
    begin
      DestS:='';
      SetLength(DestS,Size+Location);
      Move(Pointer(S1)^,Pointer(DestS)^,Location);
      Move(Pointer(S2)^,(Pointer(DestS)+Location)^,Size+1);
    end;
end;


procedure fpc_AnsiStr_Concat_multi (var DestS:ansistring;const sarr:array of Ansistring); compilerproc;
Var
  lowstart,i  : Longint;
  p,pc        : pointer;
  Size,NewLen,
  OldDestLen  : SizeInt;
  destcopy    : pointer;
begin
  if high(sarr)=0 then
    begin
      DestS:='';
      exit;
    end;
  destcopy:=nil;
  lowstart:=low(sarr);
  if Pointer(DestS)=Pointer(sarr[lowstart]) then
    inc(lowstart);
  { Check for another reuse, then we can't use
    the append optimization }
  for i:=lowstart to high(sarr) do
    begin
      if Pointer(DestS)=Pointer(sarr[i]) then
        begin
          { if DestS is used somewhere in the middle of the expression,
            we need to make sure the original string still exists after
            we empty/modify DestS                                       }
          destcopy:=pointer(dests);
          fpc_AnsiStr_Incr_Ref(destcopy);
          lowstart:=low(sarr);
          break;
        end;
    end;
  { Start with empty DestS if we start with concatting
    the first array element }
  if lowstart=low(sarr) then
    DestS:='';
  OldDestLen:=length(DestS);
  { Calculate size of the result so we can do
    a single call to SetLength() }
  NewLen:=0;
  for i:=low(sarr) to high(sarr) do
    inc(NewLen,length(sarr[i]));
  SetLength(DestS,NewLen);
  { Concat all strings, except the string we already
    copied in DestS }
  pc:=Pointer(DestS)+OldDestLen;
  for i:=lowstart to high(sarr) do
    begin
      p:=pointer(sarr[i]);
      if assigned(p) then
        begin
          Size:=length(ansistring(p));
          Move(p^,pc^,Size+1);
          inc(pc,size);
        end;
    end;
  fpc_AnsiStr_Decr_Ref(destcopy);
end;





{$ifdef EXTRAANSISHORT}
Procedure AnsiStr_ShortStr_Concat (Var S1: AnsiString; Var S2 : ShortString);
{
  Concatenates a Ansi with a short string; : S2 + S2
}
Var
  Size,Location : SizeInt;
begin
  Size:=Length(S2);
  Location:=Length(S1);
  If Size=0 then
    exit;
  { Setlength takes case of uniqueness
    and alllocated memory. We need to use length,
    to take into account possibility of S1=Nil }
  SetLength (S1,Size+Length(S1));
  Move (S2[1],Pointer(Pointer(S1)+Location)^,Size);
  PByte( Pointer(S1)+length(S1) )^:=0; { Terminating Zero }
end;
{$endif EXTRAANSISHORT}


{ the following declaration has exactly the same effect as                   }
{ procedure fpc_AnsiStr_To_ShortStr (Var S1 : ShortString;S2 : Pointer);     }
{ which is what the old helper was, so we don't need an extra implementation }
{ of the old helper (JM)                                                     }
function fpc_AnsiStr_To_ShortStr (high_of_res: SizeInt;const S2 : Ansistring): shortstring;[Public, alias: 'FPC_ANSISTR_TO_SHORTSTR'];  compilerproc;
{
  Converts a AnsiString to a ShortString;
}
Var
  Size : SizeInt;
begin
  if S2='' then
   fpc_AnsiStr_To_ShortStr:=''
  else
   begin
     Size:=Length(S2);
     If Size>high_of_res then
      Size:=high_of_res;
     Move (S2[1],fpc_AnsiStr_To_ShortStr[1],Size);
     SetLength(fpc_AnsiStr_To_ShortStr,Size);
   end;
end;


Function fpc_ShortStr_To_AnsiStr (Const S2 : ShortString): ansistring; compilerproc;
{
  Converts a ShortString to a AnsiString;
}
Var
  Size : SizeInt;
begin
  Size:=Length(S2);
  SetLength(Result, Size);
  if Size>0 then
    Move(S2[1],Pointer(fpc_ShortStr_To_AnsiStr)^,Size);
end;

Function fpc_Char_To_AnsiStr(const c : Char): AnsiString; compilerproc;
{
  Converts a Char to a AnsiString;
}
begin
  Setlength (fpc_Char_To_AnsiStr,1);
  PByte(Pointer(fpc_Char_To_AnsiStr))^:=byte(c);
  { Terminating Zero }
  PByte(Pointer(fpc_Char_To_AnsiStr)+1)^:=0;
end;


Function fpc_PChar_To_AnsiStr(const p : pchar): ansistring; compilerproc;
Var
  L : SizeInt;
begin
  if (not assigned(p)) or (p[0]=#0) Then
    { result is automatically set to '' }
    exit;
  l:=IndexChar(p^,-1,#0);
  SetLength(fpc_PChar_To_AnsiStr,L);
  Move (P[0],Pointer(fpc_PChar_To_AnsiStr)^,L)
end;



Function fpc_CharArray_To_AnsiStr(const arr: array of char): ansistring; compilerproc;
var
  i  : SizeInt;
begin
  if arr[0]=#0 Then
    { result is automatically set to '' }
    exit;
  i:=IndexChar(arr,high(arr)+1,#0);
  if i = -1 then
    i := high(arr)+1;
  SetLength(fpc_CharArray_To_AnsiStr,i);
  Move (arr[0],Pointer(fpc_CharArray_To_AnsiStr)^,i);
end;


{ note: inside the compiler, the resulttype is modified to be the length }
{ of the actual chararray to which we convert (JM)                       }
function fpc_ansistr_to_chararray(arraysize: SizeInt; const src: ansistring): fpc_big_chararray; [public, alias: 'FPC_ANSISTR_TO_CHARARRAY']; compilerproc;
var
  len: SizeInt;
begin
  len := length(src);
  if len > arraysize then
    len := arraysize;
  { make sure we don't try to access element 1 of the ansistring if it's nil }
  if len > 0 then
    move(src[1],fpc_ansistr_to_chararray[0],len);
  fillchar(fpc_ansistr_to_chararray[len],arraysize-len,0);
end;



Function fpc_AnsiStr_Compare(const S1,S2 : AnsiString): SizeInt;[Public,Alias : 'FPC_ANSISTR_COMPARE'];  compilerproc;
{
  Compares 2 AnsiStrings;
  The result is
   <0 if S1<S2
   0 if S1=S2
   >0 if S1>S2
}
Var
  MaxI,Temp : SizeInt;
begin
  if pointer(S1)=pointer(S2) then
    begin
      result:=0;
      exit;
    end;
  Maxi:=Length(S1);
  temp:=Length(S2);
  If MaxI>Temp then
    MaxI:=Temp;
  if MaxI>0 then
    begin
      result:=CompareByte(S1[1],S2[1],MaxI);
      if result=0 then
        result:=Length(S1)-Length(S2);
    end
  else
    result:=Length(S1)-Length(S2);
end;

{ some values which are used in RTL for TSystemCodePage type }
const
  CP_ACP     = 0;     // default to ANSI code page
  CP_OEMCP   = 1;     // default to OEM (console) code page

function TranslatePlaceholderCP(cp: TSystemCodePage): TSystemCodePage; {$ifdef SYSTEMINLINE}inline;{$endif}
begin
  TranslatePlaceholderCP:=cp;
  case cp of
    CP_OEMCP,
    CP_ACP:
      TranslatePlaceholderCP:=DefaultSystemCodePage;
  end;
end;

procedure InternalSetCodePage(var s : RawByteString; CodePage : TSystemCodePage; Convert : Boolean = True);
  begin
    if Convert then
      begin
//{$ifdef FPC_HAS_CPSTRING}
//        s:=fpc_AnsiStr_To_AnsiStr(s,CodePage);
//{$else FPC_HAS_CPSTRING}
       // UniqueString(s);
   //     PAnsiRec(pointer(s)-AnsiFirstOff)^.CodePage:=CodePage;
//{$endif FPC_HAS_CPSTRING}
      end
    else
      begin
     //   UniqueString(s);
        PAnsiRec(pointer(s)-AnsiFirstOff)^.CodePage:=CodePage;
      end;
  end;


procedure SetCodePage(var s : RawByteString; CodePage : TSystemCodePage; Convert : Boolean = True);
  var
    OrgCodePage,
    TranslatedCodePage,
    TranslatedCurrentCodePage: TSystemCodePage;
  begin
    if (S='') then
      exit;
    { if the codepage are identical, we don't have to do anything (even if the
      string has multiple references) }
    OrgCodePage:=PAnsiRec(pointer(S)-AnsiFirstOff)^.CodePage;
    if OrgCodePage=CodePage then
      exit;
    { if we're just replacing a placeholder code page with its actual value or
      vice versa, we don't have to perform any conversion }
    TranslatedCurrentCodePage:=TranslatePlaceholderCP(OrgCodePage);
    TranslatedCodePage:=TranslatePlaceholderCP(CodePage);
    Convert:=Convert and
      (TranslatedCurrentCodePage<>TranslatedCodePage);
    if not Convert and (PAnsiRec(pointer(S)-AnsiFirstOff)^.Ref=1) then
      PAnsiRec(pointer(S)-AnsiFirstOff)^.CodePage:=CodePage
    else
      InternalSetCodePage(S,CodePage,Convert);
  end;
  


function StringCodePage(const S: RawByteString): TSystemCodePage; overload;
  begin
//{$ifdef FPC_HAS_CPSTRING}
//    if assigned(Pointer(S)) then
//      Result:=PAnsiRec(pointer(S)-AnsiFirstOff)^.CodePage
 //   else
//{$endif FPC_HAS_CPSTRING}
      Result:=DefaultSystemCodePage;
  end;



Function fpc_AnsiStr_Compare_equal(const S1,S2 : RawByteString): SizeInt;[Public,Alias : 'FPC_ANSISTR_COMPARE_EQUAL'];  compilerproc;
{
  Compares 2 AnsiStrings for equality/inequality only;
  The result is
   0 if S1=S2
   <>0 if S1<>S2
}
Var
  MaxI,Temp : SizeInt;
  cp1,cp2 : TSystemCodePage;
  r1,r2 : RawByteString;
begin
  if pointer(S1)=pointer(S2) then
    begin
      result:=0;
      exit;
    end;
  { don't compare strings if one of them is empty }
  if (pointer(S1)=nil) then
    begin
      result:=-1;
      exit;
    end;
  if (pointer(S2)=nil) then
    begin
      result:=1;
      exit;
    end;
  cp1:=TranslatePlaceholderCP(StringCodePage(S1));
  cp2:=TranslatePlaceholderCP(StringCodePage(S2));
  if cp1=cp2 then
    begin
      Maxi:=Length(S1);
      temp:=Length(S2);
      Result := Maxi - temp;
      if Result = 0 then
        if MaxI>0 then
          result:=CompareByte(S1[1],S2[1],MaxI);
    end
  else
    begin
      r1:=S1;
      r2:=S2;
      //convert them to utf8 then compare
      SetCodePage(r1,65001);
      SetCodePage(r2,65001);
      Maxi:=Length(r1);
      temp:=Length(r2);
      Result := Maxi - temp;
      if Result = 0 then
        if MaxI>0 then
          result:=CompareByte(r1[1],r2[1],MaxI);
    end;
end;

Procedure fpc_AnsiStr_CheckZero(p : pointer);[Public,Alias : 'FPC_ANSISTR_CHECKZERO'];  compilerproc;
begin
  if p=nil then
    HandleErrorFrame(201,get_frame);
end;


Procedure fpc_AnsiStr_CheckRange(len,index : SizeInt);[Public,Alias : 'FPC_ANSISTR_RANGECHECK'];  compilerproc;
begin
  if (index>len) or (Index<1) then
    HandleErrorFrame(201,get_frame);
end;

Procedure fpc_AnsiStr_SetLength (Var S : RawByteString; l : SizeInt{$ifdef FPC_HAS_CPSTRING};cp : TSystemCodePage{$endif FPC_HAS_CPSTRING});[Public,Alias : 'FPC_ANSISTR_SETLENGTH'];  compilerproc;
{
  Sets The length of string S to L.
  Makes sure S is unique, and contains enough room.
}
Var
  Temp : Pointer;
  lens, lena,
  movelen : SizeInt;
begin
  if (l>0) then
    begin
      if Pointer(S)=nil then
        begin
          Pointer(S):=NewAnsiString(L);
{$ifdef FPC_HAS_CPSTRING}
          cp:=TranslatePlaceholderCP(cp);
          PAnsiRec(Pointer(S)-AnsiFirstOff)^.CodePage:=cp;
{$else}
          PAnsiRec(Pointer(S)-AnsiFirstOff)^.CodePage:=DefaultSystemCodePage;
{$endif FPC_HAS_CPSTRING}
        end
      else if PAnsiRec(Pointer(S)-AnsiFirstOff)^.Ref=1 then
        begin
          Temp:=Pointer(s)-AnsiFirstOff;
          if Assigned(MemoryManager.MemSize) then
            lens := MemoryManager.MemSize(Temp)
          else
            lens := AnsiFirstOff+L+SizeOf(AnsiChar);
          lena:=AnsiFirstOff+L+sizeof(AnsiChar);
          { allow shrinking string if that saves at least half of current size }
          if (lena>lens) or ((lens>32) and (lena<=(lens div 2))) then
            begin
              reallocmem(Temp,lena);
              Pointer(S):=Temp+AnsiFirstOff;
            end;
        end
      else
        begin
          { Reallocation is needed... }
          Temp:=NewAnsiString(L);
          PAnsiRec(Pointer(Temp)-AnsiFirstOff)^.CodePage:=PAnsiRec(Pointer(S)-AnsiFirstOff)^.CodePage;
          { also move terminating null }
          lens:=succ(length(s));
          if l<lens then
            movelen:=l
          else
            movelen:=lens;
          Move(Pointer(S)^,Temp^,movelen);
          fpc_ansistr_decr_ref(Pointer(s));
          Pointer(S):=Temp;
        end;
      { Force nil termination in case it gets shorter }
      PByte(Pointer(S)+l)^:=0;
      PAnsiRec(Pointer(S)-AnsiFirstOff)^.Len:=l;
    end
  else  { length=0, deallocate the string }
    fpc_ansistr_decr_ref (Pointer(S));
end;

{$ifdef EXTRAANSISHORT}
Function fpc_AnsiStr_ShortStr_Compare (Var S1 : Pointer; Var S2 : ShortString): SizeInt;  compilerproc;
{
  Compares a AnsiString with a ShortString;
  The result is
   <0 if S1<S2
   0 if S1=S2
   >0 if S1>S2
}
Var
  i,MaxI,Temp : SizeInt;
begin
  Temp:=0;
  i:=0;
  MaxI:=Length(AnsiString(S1));
  if MaxI>byte(S2[0]) then
    MaxI:=Byte(S2[0]);
  While (i<MaxI) and (Temp=0) do
   begin
     Temp:= PByte(S1+I)^ - Byte(S2[i+1]);
     inc(i);
   end;
  AnsiStr_ShortStr_Compare:=Temp;
end;
{$endif EXTRAANSISHORT}


{*****************************************************************************
                     Public functions, In interface.
*****************************************************************************}


Function fpc_ansistr_Unique(Var S : Pointer): Pointer; [Public,Alias : 'FPC_ANSISTR_UNIQUE']; compilerproc;
{
  Make sure reference count of S is 1,
  using copy-on-write semantics.
Var
  SNew : Pointer;
  L    : SizeInt; }

begin
  Pointer(Result) := Pointer(S);
  // todo: to check this
end;

Procedure fpc_ansistr_append_char(Var S : AnsiString;c : char); [Public,Alias : 'FPC_ANSISTR_APPEND_CHAR']; compilerproc;
begin
  SetLength(S,length(S)+1);
  // avoid unique call
  PChar(Pointer(S)+length(S)-1)^:=c;
  PByte(Pointer(S)+length(S))^:=0; { Terminating Zero }
end;

Procedure fpc_ansistr_append_shortstring(Var S : AnsiString;Str : ShortString); [Public,Alias : 'FPC_ANSISTR_APPEND_SHORTSTRING']; compilerproc;
var
   ofs : SizeInt;
begin
   if Str='' then
     exit;
   ofs:=Length(S);
   SetLength(S,ofs+length(Str));
   move(Str[1],S[ofs+1],length(Str));
   PByte(Pointer(S)+length(S))^:=0; { Terminating Zero }
end;

Procedure fpc_ansistr_append_ansistring(Var S : AnsiString;Str : AnsiString); [Public,Alias : 'FPC_ANSISTR_APPEND_ANSISTRING']; compilerproc;
var
   ofs : SizeInt;
begin
   if Str='' then
     exit;
   ofs:=Length(S);
   SetLength(S,ofs+length(Str));
   move(Str[1],S[ofs+1],length(Str)+1);
end;

Function Fpc_Ansistr_Copy (Const S : AnsiString; Index,Size : SizeInt) : AnsiString;compilerproc;
var
  ResultAddress : Pointer;
begin
  ResultAddress:=Nil;
  dec(index);
  if Index < 0 then
    Index := 0;
  { Check Size. Accounts for Zero-length S, the double check is needed because
    Size can be maxint and will get <0 when adding index }
  if (Size>Length(S)) or
     (Index+Size>Length(S)) then
   Size:=Length(S)-Index;
  If Size>0 then
   begin
     If Index<0 Then
      Index:=0;
     ResultAddress:=Pointer(NewAnsiString (Size));
     if ResultAddress<>Nil then
      begin
        Move (Pointer(Pointer(S)+index)^,ResultAddress^,Size);
        PAnsiRec(ResultAddress-FirstOff)^.Len:=Size;
        PByte(ResultAddress+Size)^:=0;
      end;
   end;
  Pointer(fpc_ansistr_Copy):=ResultAddress;
end;

Function Pos (Const Substr : ShortString; Const Source : AnsiString) : SizeInt;

var
  i,MaxLen : SizeInt;
  pc : pchar;
begin
  Pos:=0;
  if Length(SubStr)>0 then
   begin
     MaxLen:=Length(source)-Length(SubStr);
     i:=0;
     pc:=@source[1];
     while (i<=MaxLen) do
      begin
        inc(i);
        if (SubStr[1]=pc^) and
           (CompareByte(Substr[1],pc^,Length(SubStr))=0) then
         begin
           Pos:=i;
           exit;
         end;
        inc(pc);
      end;
   end;
end;


Function Pos (Const Substr : AnsiString; Const Source : AnsiString) : SizeInt;
var
  i,MaxLen : SizeInt;
  pc : pchar;
begin
  Pos:=0;
  if Length(SubStr)>0 then
   begin
     MaxLen:=Length(source)-Length(SubStr);
     i:=0;
     pc:=@source[1];
     while (i<=MaxLen) do
      begin
        inc(i);
        if (SubStr[1]=pc^) and
           (CompareByte(Substr[1],pc^,Length(SubStr))=0) then
         begin
           Pos:=i;
           exit;
         end;
        inc(pc);
      end;
   end;
end;


{ Faster version for a char alone. Must be implemented because   }
{ pos(c: char; const s: shortstring) also exists, so otherwise   }
{ using pos(char,pchar) will always call the shortstring version }
{ (exact match for first argument), also with $h+ (JM)           }
Function Pos (c : Char; Const s : AnsiString) : SizeInt;
var
  i: SizeInt;
  pc : pchar;
begin
  pc:=@s[1];
  for i:=1 to length(s) do
   begin
     if pc^=c then
      begin
        pos:=i;
        exit;
      end;
     inc(pc);
   end;
  pos:=0;
end;

{
Procedure fpc_AnsiStr_UInt(v : ValUInt;Len : SizeInt; Var S : AnsiString);[Public,Alias : 'FPC_ANSISTR_VALUINT']; compilerproc;
Var
  SS : ShortString;
begin
  str(v:Len,SS);
  S:=SS;
end;
}


{
Procedure fpc_AnsiStr_SInt(v : ValSInt;Len : SizeInt; Var S : AnsiString);[Public,Alias : 'FPC_ANSISTR_VALSINT']; compilerproc;
Var
  SS : ShortString;
begin
  str (v:Len,SS);
  S:=SS;
end;
}

Procedure Delete (Var S : AnsiString; Index,Size: SizeInt);
Var
  LS : SizeInt;
begin
  ls:=Length(S);
  If (Index>LS) or (Index<=0) or (Size<=0) then
    exit;
  UniqueString (S);
  If (Size>LS-Index) then   // Size+Index gives overflow ??
     Size:=LS-Index+1;
  If (Size<=LS-Index) then
    begin
    Dec(Index);
    Move(PByte(Pointer(S))[Index+Size],PByte(Pointer(S))[Index],LS-Index-Size+1);
    end;
  Setlength(S,LS-Size);
end;


Procedure Insert (Const Source : AnsiString; Var S : AnsiString; Index : SizeInt);
var
  Temp : AnsiString;
  LS : SizeInt;
begin
  If Length(Source)=0 then
   exit;
  if index <= 0 then
   index := 1;
  Ls:=Length(S);
  if index > LS then
   index := LS+1;
  Dec(Index);
  Pointer(Temp) := NewAnsiString(Length(Source)+LS);
  SetLength(Temp,Length(Source)+LS);
  If Index>0 then
    move (Pointer(S)^,Pointer(Temp)^,Index);
  Move (Pointer(Source)^,PByte(Temp)[Index],Length(Source));
  If (LS-Index)>0 then
    Move(PByte(Pointer(S))[Index],PByte(temp)[Length(Source)+index],LS-Index);
  S:=Temp;
end;


Function StringOfChar(c : char;l : SizeInt) : AnsiString;
begin
  SetLength(StringOfChar,l);
  FillChar(Pointer(StringOfChar)^,Length(StringOfChar),c);
end;

{Procedure SetString (Var S : AnsiString; Buf : PChar; Len : SizeInt);
begin
  SetLength(S,Len);
  If (Buf<>Nil) then
    begin
      Move (Buf[0],S[1],Len);
    end;
end;}

function upcase(const s : ansistring) : ansistring;
var
  i : SizeInt;
begin
  Setlength(result,length(s));
  for i := 1 to length (s) do
    result[i] := upcase(s[i]);
end;

function lowercase(const s : ansistring) : ansistring;
var
  i : SizeInt;
begin
  Setlength(result,length(s));
  for i := 1 to length (s) do
    result[i] := lowercase(s[i]);
end;

{ export for internal usage }
Procedure int_Finalize (Data,TypeInfo: Pointer); [external name 'FPC_FINALIZE'];
Procedure int_Addref (Data,TypeInfo : Pointer); [external name 'FPC_ADDREF'];
Procedure int_DecRef (Data, TypeInfo : Pointer); [external name 'FPC_DECREF'];
Procedure int_Initialize (Data,TypeInfo: Pointer); [external name 'FPC_INITIALIZE'];
procedure int_FinalizeArray(data,typeinfo : pointer;count,size : longint); [external name 'FPC_FINALIZEARRAY'];



{*****************************************************************************
                        Dynamic Array support
*****************************************************************************}

function aligntoptr(p : pointer) : pointer;inline;
  begin
{$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
    if (ptrint(p) mod sizeof(ptrint))<>0 then
      inc(ptrint(p),sizeof(ptrint)-ptrint(p) mod sizeof(ptrint));
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
    result:=p;
  end;


{****************************************************************************
                  Internal Routines called from the Compiler
****************************************************************************}

    { the reverse order of the parameters make code generation easier }
    function fpc_do_is(aclass : tclass;aobject : tobject) : boolean;[public,alias: 'FPC_DO_IS']; compilerproc;
      begin
         fpc_do_is:=assigned(aobject) and assigned(aclass) and
           aobject.inheritsfrom(aclass);
      end;


    { the reverse order of the parameters make code generation easier }
    function fpc_do_as(aclass : tclass;aobject : tobject): tobject;[public,alias: 'FPC_DO_AS']; compilerproc;
      begin
         if assigned(aobject) and not(aobject.inheritsfrom(aclass)) then
           handleerrorframe(219,get_frame);
         result := aobject;
      end;

    { interface helpers }
    procedure fpc_intf_decr_ref(var i: pointer);[public,alias: 'FPC_INTF_DECR_REF']; compilerproc;
      begin
        if assigned(i) then
          IUnknown(i)._Release;
        i:=nil;
      end;

    { local declaration for intf_decr_ref for local access }
    procedure intf_decr_ref(var i: pointer); [external name 'FPC_INTF_DECR_REF'];


    procedure fpc_intf_incr_ref(i: pointer);[public,alias: 'FPC_INTF_INCR_REF']; compilerproc;
      begin
         if assigned(i) then
           IUnknown(i)._AddRef;
      end;

    { local declaration of intf_incr_ref for local access }
    procedure intf_incr_ref(i: pointer); [external name 'FPC_INTF_INCR_REF'];

    procedure fpc_intf_assign(var D: pointer; const S: pointer);[public,alias: 'FPC_INTF_ASSIGN']; compilerproc;
      begin
         if assigned(S) then
           IUnknown(S)._AddRef;
         if assigned(D) then
           IUnknown(D)._Release;
         D:=S;
      end;

    function fpc_intf_as(const S: pointer; const iid: TGUID): pointer;[public,alias: 'FPC_INTF_AS']; compilerproc;

      var
        tmpi: pointer; // _AddRef before _Release
      begin
        if assigned(S) then
          begin
             if IUnknown(S).QueryInterface(iid,tmpi)<>S_OK then
               handleerror(219);
             fpc_intf_as:=tmpi;
          end
        else
          fpc_intf_as:=nil;
      end;


    function fpc_class_as_intf(const S: pointer; const iid: TGUID): pointer;[public,alias: 'FPC_CLASS_AS_INTF']; compilerproc;

      var
        tmpi: pointer; // _AddRef before _Release
      begin
        if assigned(S) then
          begin
             if not TObject(S).GetInterface(iid,tmpi) then
               handleerror(219);
             fpc_class_as_intf:=tmpi;
          end
        else
          fpc_class_as_intf:=nil;
      end;

{****************************************************************************
                               TOBJECT
****************************************************************************}

      constructor TObject.Create;

        begin
        end;

      destructor TObject.Destroy;

        begin
        end;

      procedure TObject.Free;

        begin
           // the call via self avoids a warning
           if self<>nil then
             self.destroy;
        end;

      class function TObject.InstanceSize : SizeInt;

        begin
           InstanceSize:=pSizeInt(pointer(self)+vmtInstanceSize)^;
        end;

      procedure InitInterfacePointers(objclass: tclass;instance : pointer);

        var
           intftable : pinterfacetable;
           i: longint;

        begin
          while assigned(objclass) do
            begin
               intftable:=pinterfacetable((pointer(objclass)+vmtIntfTable)^);
			   if assigned(intftable) then
                 for i:=0 to intftable^.EntryCount-1 do
                   ppointer(@(PChar(instance)[intftable^.Entries[i].IOffset]))^:=
                     pointer(intftable^.Entries[i].VTable);
               objclass:=pclass(pointer(objclass)+vmtParent)^;
            end;
        end;

      class function TObject.InitInstance(instance : pointer) : tobject;
        begin
           { the size is saved at offset 0 }
           fillchar(instance^, InstanceSize, 0);
           { insert VMT pointer into the new created memory area }
           { (in class methods self contains the VMT!)           }
           ppointer(instance)^:=pointer(self);
		   { this is a work around }
           { InitInterfacePointers(self,instance);}
           InitInstance:=TObject(Instance);
        end;

      class function TObject.ClassParent : tclass;

        begin
           { type of self is class of tobject => it points to the vmt }
           { the parent vmt is saved at offset vmtParent              }
           classparent:=pclass(pointer(self)+vmtParent)^;
        end;

      class function TObject.NewInstance : tobject;

        var
           p : pointer;

        begin
           getmem(p, InstanceSize);
           if p <> nil then
              InitInstance(p);
           NewInstance:=TObject(p);
        end;

      procedure TObject.FreeInstance;

        begin
           CleanupInstance;
           FreeMem(Pointer(Self), InstanceSize);
        end;

      class function TObject.ClassType : TClass;

        begin
           ClassType:=TClass(Pointer(Self))
        end;

      type
         tmethodnamerec = packed record
            name : pshortstring;
            addr : pointer;
         end;

         tmethodnametable = packed record
           count : dword;
           entries : packed array[0..0] of tmethodnamerec;
         end;

         pmethodnametable =  ^tmethodnametable;

function ShortCompareText(const S1, S2: shortstring): SizeInt;
var
  c1, c2: Byte;
  i: Integer;
  L1, L2, Count: SizeInt;
  P1, P2: PChar;
begin
  L1 := Length(S1);
  L2 := Length(S2);
  if L1 > L2 then
    Count := L2
  else
    Count := L1;
  i := 0;
  P1 := @S1[1];
  P2 := @S2[1];
  while i < count do
  begin
    c1 := byte(p1^);
    c2 := byte(p2^);
    if c1 <> c2 then
    begin
      if c1 in [97..122] then
        Dec(c1, 32);
      if c2 in [97..122] then
        Dec(c2, 32);
      if c1 <> c2 then
        Break;
    end;
    Inc(P1); Inc(P2); Inc(I);
  end;
  if i < count then
    ShortCompareText := c1 - c2
  else
    ShortCompareText := L1 - L2;
end;

      class function TObject.MethodAddress(const name : shortstring) : pointer;

        var
           methodtable : pmethodnametable;
           i : dword;
           vmt : tclass;

        begin
           vmt:=self;
           while assigned(vmt) do
             begin
                methodtable:=pmethodnametable((Pointer(vmt)+vmtMethodTable)^);
                if assigned(methodtable) then
                  begin
                     for i:=0 to methodtable^.count-1 do
                       if ShortCompareText(methodtable^.entries[i].name^, name)=0 then
                         begin
                            MethodAddress:=methodtable^.entries[i].addr;
                            exit;
                         end;
                  end;
                vmt:=pclass(pointer(vmt)+vmtParent)^;
             end;
           MethodAddress:=nil;
        end;


      class function TObject.MethodName(address : pointer) : shortstring;
        var
           methodtable : pmethodnametable;
           i : dword;
           vmt : tclass;
        begin
           vmt:=self;
           while assigned(vmt) do
             begin
                methodtable:=pmethodnametable((Pointer(vmt)+vmtMethodTable)^);
                if assigned(methodtable) then
                  begin
                     for i:=0 to methodtable^.count-1 do
                       if methodtable^.entries[i].addr=address then
                         begin
                            MethodName:=methodtable^.entries[i].name^;
                            exit;
                         end;
                  end;
                vmt:=pclass(pointer(vmt)+vmtParent)^;
             end;
           MethodName:='';
        end;


      function TObject.FieldAddress(const name : shortstring) : pointer;
        type
           PFieldInfo = ^TFieldInfo;
           TFieldInfo =
{$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}
           packed
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
           record
             FieldOffset: PtrUInt;
             ClassTypeIndex: Word;
             Name: ShortString;
           end;

           PFieldTable = ^TFieldTable;
           TFieldTable =
{$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}
           packed
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
           record
             FieldCount: Word;
             ClassTable: Pointer;
             { should be array[Word] of TFieldInfo;  but
               Elements have variant size! force at least proper alignment }
             Fields: array[0..0] of TFieldInfo
           end;

        var
           UName: ShortString;
           CurClassType: TClass;
           FieldTable: PFieldTable;
           FieldInfo: PFieldInfo;
           i: Integer;

        begin
           if Length(name) > 0 then
           begin
             UName := UpCase(name);
             CurClassType := ClassType;
             while CurClassType <> nil do
             begin
               FieldTable := PFieldTable((Pointer(CurClassType) + vmtFieldTable)^);
               if FieldTable <> nil then
               begin
                 FieldInfo := @FieldTable^.Fields;
                 for i := 0 to FieldTable^.FieldCount - 1 do
                 begin
                   if UpCase(FieldInfo^.Name) = UName then
                   begin
                     fieldaddress := Pointer(Self) + FieldInfo^.FieldOffset;
                     exit;
                   end;
                   FieldInfo := PFieldInfo(PtrUInt(@FieldInfo^.Name) + 1 + Length(FieldInfo^.Name));
{$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
                   { align to largest field of TFieldInfo }
                   FieldInfo := Align(FieldInfo, SizeOf(PtrUInt));
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
                 end;
               end;
               { Try again with the parent class type }
               CurClassType:=pclass(pointer(CurClassType)+vmtParent)^;
             end;
           end;

           fieldaddress:=nil;
        end;

      function TObject.SafeCallException(exceptobject : tobject;
        exceptaddr : pointer) : longint;

        begin
           safecallexception:=0;
        end;

      class function TObject.ClassInfo : pointer;

        begin
           ClassInfo:=ppointer(Pointer(self)+vmtTypeInfo)^;
        end;

      class function TObject.ClassName : ShortString;

        begin
           ClassName:=PShortString((Pointer(Self)+vmtClassName)^)^;
        end;

      class function TObject.ClassNameIs(const name : string) : boolean;

        begin
           ClassNameIs:=Upcase(ClassName)=Upcase(name);
        end;

      class function TObject.InheritsFrom(aclass : TClass) : Boolean;

        var
           vmt : tclass;

        begin
           vmt:=self;
           while assigned(vmt) do
             begin
                if vmt=aclass then
                  begin
                     InheritsFrom:=True;
                     exit;
                  end;
                vmt:=pclass(pointer(vmt)+vmtParent)^;
             end;
           InheritsFrom:=False;
        end;

      class function TObject.stringmessagetable : pstringmessagetable;

        type
           pdword = ^dword;

        begin
           stringmessagetable:=pstringmessagetable((pointer(Self)+vmtMsgStrPtr)^);
        end;

      type
         tmessagehandler = procedure(var msg) of object;
         tmessagehandlerrec = packed record
            proc : pointer;
            obj : pointer;
         end;


      procedure TObject.Dispatch(var message);

        type
           tmsgtable = packed record
              index : dword;
              method : pointer;
           end;

           pmsgtable = ^tmsgtable;

        var
           index : dword;
           count,i : longint;
           msgtable : pmsgtable;
           p : pointer;
           vmt : tclass;
           msghandler : tmessagehandler;

        begin
           index:=dword(message);
           vmt:=ClassType;
           while assigned(vmt) do
             begin
                // See if we have messages at all in this class.
                p:=pointer(vmt)+vmtDynamicTable;
                If Assigned(p) and (Pdword(p)^<>0) then
                  begin
                     msgtable:=pmsgtable(PtrInt(p^)+4);
                     count:=pdword(p^)^;
                  end
                else
                  Count:=0;
                { later, we can implement a binary search here }
                for i:=0 to count-1 do
                  begin
                     if index=msgtable[i].index then
                       begin
                          p:=msgtable[i].method;
                          tmessagehandlerrec(msghandler).proc:=p;
                          tmessagehandlerrec(msghandler).obj:=self;
                          msghandler(message);
                          exit;
                       end;
                  end;
                vmt:=pclass(pointer(vmt)+vmtParent)^;
             end;
           DefaultHandler(message);
        end;

      procedure TObject.DispatchStr(var message);

        type
           PSizeUInt = ^SizeUInt;

        var
           name : shortstring;
           count,i : longint;
           msgstrtable : pmsgstrtable;
           p : pointer;
           vmt : tclass;
           msghandler : tmessagehandler;

        begin
           name:=pshortstring(@message)^;
           vmt:=ClassType;
           while assigned(vmt) do
             begin
                p:=(pointer(vmt)+vmtMsgStrPtr);
                If (P<>Nil) and (PDWord(P)^<>0) then
                  begin
                  count:=pdword(PSizeUInt(p)^)^;
                  msgstrtable:=pmsgstrtable(PSizeUInt(P)^+4);
                  end
                else
                  Count:=0;
                { later, we can implement a binary search here }
                for i:=0 to count-1 do
                  begin
                     if name=msgstrtable[i].name^ then
                       begin
                          p:=msgstrtable[i].method;
                          tmessagehandlerrec(msghandler).proc:=p;
                          tmessagehandlerrec(msghandler).obj:=self;
                          msghandler(message);
                          exit;
                       end;
                  end;
                vmt:=pclass(pointer(vmt)+vmtParent)^;
             end;
           DefaultHandlerStr(message);
        end;

      procedure TObject.DefaultHandler(var message);

        begin
        end;

      procedure TObject.DefaultHandlerStr(var message);

        begin
        end;

      procedure TObject.CleanupInstance;

        Type
          TRecElem = packed Record
            Info : Pointer;
            Offset : Longint;
          end;

          TRecElemArray = packed array[1..Maxint] of TRecElem;

          PRecRec = ^TRecRec;
          TRecRec = record
            Size,Count : Longint;
            Elements : TRecElemArray;
          end;

        var
           vmt  : tclass;
           temp : pbyte;
           count,
           i    : longint;
{$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
           recelem  : TRecElem;
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
        begin
           vmt:=ClassType;
           while vmt<>nil do
             begin
               { This need to be included here, because Finalize()
                 has should support for tkClass }
               Temp:=Pointer((Pointer(vmt)+vmtInitTable)^);
               if Assigned(Temp) then
                 begin
                   inc(Temp);
                   I:=Temp^;
                   inc(temp,I+1);                // skip name string;
                   temp:=aligntoptr(temp);
{$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
                   move(PRecRec(Temp)^.Count,Count,sizeof(Count));
{$else FPC_REQUIRES_PROPER_ALIGNMENT}
                   Count:=PRecRec(Temp)^.Count;  // get element Count
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
                   For I:=1 to count do
{$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
                     begin
                       move(PRecRec(Temp)^.elements[I],RecElem,sizeof(RecElem));
                       With RecElem do
                         int_Finalize (pointer(self)+Offset,Info);
                     end;
{$else FPC_REQUIRES_PROPER_ALIGNMENT}
                     With PRecRec(Temp)^.elements[I] do
                       int_Finalize (pointer(self)+Offset,Info);
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
                 end;
               vmt:=pclass(pointer(vmt)+vmtParent)^;
             end;
        end;

      procedure TObject.AfterConstruction;

        begin
        end;

      procedure TObject.BeforeDestruction;

        begin
        end;

      function IsGUIDEqual(const guid1, guid2: tguid): boolean;
        begin
          IsGUIDEqual:=
            (guid1.D1=guid2.D1) and
            (PDWORD(@guid1.D2)^=PDWORD(@guid2.D2)^) and
            (PDWORD(@guid1.D4[0])^=PDWORD(@guid2.D4[0])^) and
            (PDWORD(@guid1.D4[4])^=PDWORD(@guid2.D4[4])^);
        end;

      function TObject.getinterface(const iid : tguid;out obj) : boolean;
        var
          IEntry: pinterfaceentry;
        begin
          IEntry:=getinterfaceentry(iid);
          if Assigned(IEntry) then
            begin
              Pointer(obj):=Pointer(Self)+IEntry^.IOffset;
              if assigned(pointer(obj)) then
                iinterface(obj)._AddRef;
              getinterface:=True;
            end
          else
            begin
              PPointer(@Obj)^:=nil;
              getinterface:=False;
            end;
        end;

      function TObject.getinterfacebystr(const iidstr : string;out obj) : boolean;
        var
          IEntry: pinterfaceentry;
        begin
          IEntry:=getinterfaceentrybystr(iidstr);
          if Assigned(IEntry) then
            begin
              Pointer(obj):=Pointer(Self)+IEntry^.IOffset;
              if assigned(pointer(obj)) then
                iinterface(obj)._AddRef;
              getinterfacebystr:=True;
            end
          else
            begin
              PPointer(@Obj)^:=nil;
              getinterfacebystr:=False;
            end;
        end;

      class function TObject.getinterfaceentry(const iid : tguid) : pinterfaceentry;
        var
          i: integer;
          intftable: pinterfacetable;
          Res: pinterfaceentry;
        begin
          getinterfaceentry:=nil;
          intftable:=pinterfacetable((pointer(Self)+vmtIntfTable)^);
          if assigned(intftable) then begin
            i:=intftable^.EntryCount;
            Res:=@intftable^.Entries[0];
            while (i>0) and
               not (assigned(Res^.iid) and IsGUIDEqual(Res^.iid^,iid)) do begin
              inc(Res);
              dec(i);
            end;
            if (i>0) then
              getinterfaceentry:=Res;
          end;
          if (getinterfaceentry=nil)and not(classparent=nil) then
            getinterfaceentry:=classparent.getinterfaceentry(iid)
        end;

      class function TObject.getinterfaceentrybystr(const iidstr : string) : pinterfaceentry;
        var
          i: integer;
          intftable: pinterfacetable;
          Res: pinterfaceentry;
        begin
          getinterfaceentrybystr:=nil;
          intftable:=getinterfacetable;
          if assigned(intftable) then begin
            i:=intftable^.EntryCount;
            Res:=@intftable^.Entries[0];
            while (i>0) and (Res^.iidstr^<>iidstr) do begin
              inc(Res);
              dec(i);
            end;
            if (i>0) then
              getinterfaceentrybystr:=Res;
          end;
          if (getinterfaceentrybystr=nil)and not(classparent=nil) then
            getinterfaceentrybystr:=classparent.getinterfaceentrybystr(iidstr)
        end;

      class function TObject.getinterfacetable : pinterfacetable;
        begin
          getinterfacetable:=pinterfacetable((pointer(Self)+vmtIntfTable)^);
        end;

      function TObject.Equals(Obj: TObject) : boolean;
        begin
          result:=Obj=Self;
        end;

      function TObject.GetHashCode: PtrInt;
        begin
          result:=PtrInt(Self);
        end;

      function TObject.ToString: {$ifdef FPC_HAS_FEATURE_ANSISTRINGS}ansistring{$else FPC_HAS_FEATURE_ANSISTRINGS}shortstring{$endif FPC_HAS_FEATURE_ANSISTRINGS};
        begin
		while true do;
          //result:=ClassName;
        end;

{****************************************************************************
                                Exception support
****************************************************************************}


Const
  { Type of exception. Currently only one. }
  FPC_EXCEPTION   = 1;

  { types of frames for the exception address stack }
  cExceptionFrame = 1;
  cFinalizeFrame  = 2;

Type
  PExceptAddr = ^TExceptAddr;
  TExceptAddr = record
    buf       : pjmp_buf;
    next      : PExceptAddr;
    frametype : Longint;
  end;

  TExceptObjectClass = Class of TObject;

Const
  CatchAllExceptions : PtrInt = -1;

ThreadVar
  ExceptAddrStack   : PExceptAddr;
  ExceptObjectStack : PExceptObject;

Function RaiseList : PExceptObject;
begin
  RaiseList:=ExceptObjectStack;
end;


function AcquireExceptionObject: Pointer;
var
  _ExceptObjectStack : PExceptObject;
begin
  _ExceptObjectStack:=ExceptObjectStack;
  If _ExceptObjectStack<>nil then
    begin
      Inc(_ExceptObjectStack^.refcount);
      AcquireExceptionObject := _ExceptObjectStack^.FObject;
    end
  else
    RunError(231);
end;


procedure ReleaseExceptionObject;
var
  _ExceptObjectStack : PExceptObject;
begin
  _ExceptObjectStack:=ExceptObjectStack;
  If _ExceptObjectStack <> nil then
    begin
      if _ExceptObjectStack^.refcount > 0 then
        Dec(_ExceptObjectStack^.refcount);
    end
  else
    RunError(231);
end;


Function fpc_PushExceptAddr (Ft: Longint;_buf,_newaddr : pointer): PJmp_buf ;
  [Public, Alias : 'FPC_PUSHEXCEPTADDR'];compilerproc;
var
  _ExceptAddrstack : ^PExceptAddr;
begin
  _ExceptAddrstack:=@ExceptAddrstack;
  PExceptAddr(_newaddr)^.Next:=_ExceptAddrstack^;
  _ExceptAddrStack^:=PExceptAddr(_newaddr);
  PExceptAddr(_newaddr)^.Buf:=PJmp_Buf(_buf);
  PExceptAddr(_newaddr)^.FrameType:=ft;
  result:=PJmp_Buf(_buf);
end;


Procedure fpc_PushExceptObj (Obj : TObject; AnAddr,AFrame : Pointer);
  [Public, Alias : 'FPC_PUSHEXCEPTOBJECT']; compilerproc;
var
  Newobj : PExceptObject;
  _ExceptObjectStack : ^PExceptObject;
  framebufsize,
  framecount  : longint;
  frames      : PPointer;
  prev_frame,
  curr_frame,
  caller_frame,
  caller_addr : Pointer;
begin
  _ExceptObjectStack:=@ExceptObjectStack;
  If _ExceptObjectStack^=Nil then
    begin
      New(_ExceptObjectStack^);
      _ExceptObjectStack^^.Next:=Nil;
    end
  else
    begin
      New(NewObj);
      NewObj^.Next:=_ExceptObjectStack^;
      _ExceptObjectStack^:=NewObj;
    end;
  with _ExceptObjectStack^^ do
    begin
      FObject:=Obj;
      Addr:=AnAddr;
      refcount:=0;
    end;
  { Backtrace }
  curr_frame:=AFrame;
  prev_frame:=get_frame;
  frames:=nil;
  framebufsize:=0;
  framecount:=0;
  while (framecount<RaiseMaxFrameCount) and (curr_frame > prev_frame) and
        (curr_frame<(StackBottom + StackLength)) do
   Begin
     caller_addr := get_caller_addr(curr_frame);
     caller_frame := get_caller_frame(curr_frame);
     if (caller_addr=nil) or
        (caller_frame=nil) then
       break;
     if (framecount>=framebufsize) then
       begin
         inc(framebufsize,16);
         //ReallocMem(frames, (framebufsize-16)*sizeof(pointer), framebufsize*sizeof(pointer));
		 ReallocMem(frames, framebufsize*sizeof(pointer))
       end;
     frames[framecount]:=caller_addr;
     inc(framecount);
     prev_frame:=curr_frame;
     curr_frame:=caller_frame;
   End;
  _ExceptObjectStack^^.framecount:=framecount;
  _ExceptObjectStack^^.frames:=frames;
end;
{ make it avalable for local use }
Procedure fpc_PushExceptObj (Obj : TObject; AnAddr,AFrame : Pointer); [external name 'FPC_PUSHEXCEPTOBJECT'];


Procedure DoUnHandledException;
var
  _ExceptObjectStack : PExceptObject;
begin
  _ExceptObjectStack:=ExceptObjectStack;
  If (ExceptProc<>Nil) and (_ExceptObjectStack<>Nil) then
    with _ExceptObjectStack^ do
      begin
        TExceptProc(ExceptProc)(FObject,Addr,FrameCount,Frames);
        halt(217)
      end;
  if erroraddr = nil then
    RunError(217)
  else
    if errorcode <= maxExitCode then
      halt(errorcode)
    else
      halt(255)
end;



Function fpc_Raiseexception (Obj : TObject; AnAddr,AFrame : Pointer) : TObject;[Public, Alias : 'FPC_RAISEEXCEPTION']; compilerproc;
var
  _ExceptObjectStack : PExceptObject;
  _ExceptAddrstack : PExceptAddr;
begin
  fpc_Raiseexception:=nil;
  fpc_PushExceptObj(Obj,AnAddr,AFrame);
  _ExceptAddrstack:=ExceptAddrStack;
  If _ExceptAddrStack=Nil then
    DoUnhandledException;
  _ExceptObjectStack:=ExceptObjectStack;
  if (RaiseProc <> nil) and (_ExceptObjectStack <> nil) then
    with _ExceptObjectStack^ do
      RaiseProc(FObject,Addr,FrameCount,Frames);
  fpc_longjmp(_ExceptAddrStack^.Buf^,FPC_Exception);
end;


Procedure fpc_PopAddrStack;[Public, Alias : 'FPC_POPADDRSTACK']; compilerproc;
var
  hp : ^PExceptAddr;
begin
  hp:=@ExceptAddrStack;
  If hp^=nil then
    begin
      halt (255);
    end
  else
    begin
      hp^:=hp^^.Next;
    end;
end;


function fpc_PopObjectStack : TObject;[Public, Alias : 'FPC_POPOBJECTSTACK']; compilerproc;
var
  hp,_ExceptObjectStack : PExceptObject;
begin
  _ExceptObjectStack:=ExceptObjectStack;
  If _ExceptObjectStack=nil then
    begin
    halt (1);
    end
  else
    begin
       { we need to return the exception object to dispose it }
       if _ExceptObjectStack^.refcount = 0 then begin
         fpc_PopObjectStack:=_ExceptObjectStack^.FObject;
       end else begin
         fpc_PopObjectStack:=nil;
       end;
       hp:=_ExceptObjectStack;
       ExceptObjectStack:=_ExceptObjectStack^.next;
       if assigned(hp^.frames) then
         freemem(hp^.frames);
       dispose(hp);
       erroraddr:=nil;
    end;
end;

{ this is for popping exception objects when a second exception is risen }
{ in an except/on                                                        }
function fpc_PopSecondObjectStack : TObject;[Public, Alias : 'FPC_POPSECONDOBJECTSTACK']; compilerproc;
var
  hp,_ExceptObjectStack : PExceptObject;
begin
  _ExceptObjectStack:=ExceptObjectStack;
  If not(assigned(_ExceptObjectStack)) or
     not(assigned(_ExceptObjectStack^.next)) then
    begin
      halt (1);
    end
  else
    begin
      if _ExceptObjectStack^.next^.refcount=0 then
        { we need to return the exception object to dispose it if refcount=0 }
        fpc_PopSecondObjectStack:=_ExceptObjectStack^.next^.FObject
      else
        fpc_PopSecondObjectStack:=nil;
      hp:=_ExceptObjectStack^.next;
      _ExceptObjectStack^.next:=hp^.next;
      if assigned(hp^.frames) then
        freemem(hp^.frames);
      dispose(hp);
    end;
end;

Procedure fpc_ReRaise;[Public, Alias : 'FPC_RERAISE']; compilerproc;
var
  _ExceptAddrStack : PExceptAddr;
begin
  _ExceptAddrStack:=ExceptAddrStack;
  If _ExceptAddrStack=Nil then
    DoUnHandledException;
  ExceptObjectStack^.refcount := 0;
  fpc_longjmp(_ExceptAddrStack^.Buf^,FPC_Exception);
end;


Function fpc_Catches(Objtype : TClass) : TObject;[Public, Alias : 'FPC_CATCHES']; compilerproc;
var
  _Objtype : TExceptObjectClass;
begin

  If ExceptObjectStack=Nil then
  begin
    halt (255);
  end;

  _Objtype := TExceptObjectClass(Objtype);
  if Not ((_Objtype = TExceptObjectClass(CatchAllExceptions)) or
         (ExceptObjectStack^.FObject is _ObjType)) then
    fpc_Catches:=Nil
  else
    begin
      // catch !
      fpc_Catches:=ExceptObjectStack^.FObject;
      { this can't be done, because there could be a reraise (PFV)
       PopObjectStack;

       Also the PopAddrStack shouldn't be done, we do it now
       immediatly in the exception handler (FK)
      PopAddrStack; }
    end;
end;

Procedure fpc_DestroyException(o : TObject);[Public, Alias : 'FPC_DESTROYEXCEPTION']; compilerproc;
begin
  { with free we're on the really save side }
  o.Free;
end;


Procedure SysInitExceptions;
{
  Initialize exceptionsupport
}
begin
  ExceptObjectstack := Nil;
  ExceptAddrStack := Nil;
end;


var
   variantmanager : tvariantmanager;

procedure printmissingvariantunit;
  begin
  end;


procedure invalidvariantop;
  begin
     printmissingvariantunit;
     HandleErrorFrame(221,get_frame);
  end;


procedure invalidvariantopnovariants;
  begin
    printmissingvariantunit;
    HandleErrorFrame(221,get_frame);
  end;


procedure vardisperror;
  begin
    printmissingvariantunit;
    HandleErrorFrame(222,get_frame);
  end;


{ ---------------------------------------------------------------------
    Compiler helper routines.
  ---------------------------------------------------------------------}

procedure varclear(var v : tvardata);
begin
   if not(v.vtype in [varempty,varerror,varnull]) then
     invalidvariantop;
end;


procedure variant_init(var v : tvardata);[Public,Alias:'FPC_VARIANT_INIT'];
  begin
     { calling the variant manager here is a problem because the static/global variants
       are initialized while the variant manager isn't assigned }
     fillchar(v,sizeof(variant),0);
  end;


procedure fpc_variant_clear (var v : tvardata);[Public,Alias:'FPC_VARIANT_CLEAR'];compilerproc;
  begin
    if assigned(VarClearProc) then
      VarClearProc(v);
  end;

procedure variant_clear(var v: tvardata); external name 'FPC_VARIANT_CLEAR';
	
procedure variant_addref(var v : tvardata);[Public,Alias:'FPC_VARIANT_ADDREF'];
  begin
    if assigned(VarAddRefProc) then
      VarAddRefProc(v);
  end;

{ using pointers as argument here makes life for the compiler easier }
procedure fpc_variant_copy(d,s : pointer);compilerproc;
  begin
    if assigned(VarCopyProc) then
      VarCopyProc(tvardata(d^),tvardata(s^));
  end;


//procedure fpc_vararray_get(var d : variant;const s : variant;indices : plongint;len : sizeint);compilerproc;
//begin
//  d:= variantmanager.vararrayget(s,len,indices);
//end;


procedure fpc_vararray_put(var d : variant;const s : variant;indices : plongint;len : sizeint);compilerproc;
begin
  variantmanager.vararrayput(d,s,len,indices);
end;


{ ---------------------------------------------------------------------
    Overloaded operators.
  ---------------------------------------------------------------------}

{ Integer }

operator :=(const source : byte) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  Variantmanager.varfromInt(Dest,Source,1);
end;


operator :=(const source : shortint) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  Variantmanager.varfromInt(Dest,Source,-1);
end;


operator :=(const source : word) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  Variantmanager.varfromInt(Dest,Source,2);
end;


operator :=(const source : smallint) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  Variantmanager.varfromInt(Dest,Source,-2);
end;


operator :=(const source : dword) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  Variantmanager.varfromInt(Dest,Source,4);
end;


operator :=(const source : longint) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  Variantmanager.varfromInt(Dest,Source,-4);
end;


operator :=(const source : qword) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  Variantmanager.varfromWord64(Dest,Source);
end;


operator :=(const source : int64) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  Variantmanager.varfromInt64(Dest,Source);
end;

{ Boolean }

operator :=(const source : boolean) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  Variantmanager.varfromBool(Dest,Source);
end;


operator :=(const source : wordbool) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  Variantmanager.varfromBool(Dest,Boolean(Source));
end;


operator :=(const source : longbool) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  Variantmanager.varfromBool(Dest,Boolean(Source));
end;


{ Chars }

operator :=(const source : char) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  VariantManager.VarFromPStr(Dest,Source);
end;



{ Strings }

operator :=(const source : shortstring) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  VariantManager.VarFromPStr(Dest,Source);
end;


operator :=(const source : ansistring) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  VariantManager.VarFromLStr(Dest,Source);
end;


{ Floats }

{$ifdef SUPPORT_SINGLE}
operator :=(const source : single) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  VariantManager.VarFromReal(Dest,Source);
end;
{$endif SUPPORT_SINGLE}


{$ifdef SUPPORT_DOUBLE}
operator :=(const source : double) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  VariantManager.VarFromReal(Dest,Source);
end;
{$endif SUPPORT_DOUBLE}

{ Misc. }
operator :=(const source : currency) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    VariantManager.VarFromCurr(Dest,Source);
  end;


operator :=(const source : tdatetime) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    VariantManager.VarFromTDateTime(Dest,Source);
  end;


operator :=(const source : error) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    Variantmanager.varfromInt(Dest,Source,-sizeof(error));
  end;
  
{**********************************************************************
                       from Variant assignments
 **********************************************************************}

{ Integer }

operator :=(const source : variant) dest : byte;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  dest:=variantmanager.vartoint(source);
end;


operator :=(const source : variant) dest : shortint;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    dest:=variantmanager.vartoint(source);
  end;


operator :=(const source : variant) dest : word;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    dest:=variantmanager.vartoint(source);
  end;


operator :=(const source : variant) dest : smallint;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    dest:=variantmanager.vartoint(source);
  end;


operator :=(const source : variant) dest : dword;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    dest:=variantmanager.vartoint(source);
  end;


operator :=(const source : variant) dest : longint;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    dest:=variantmanager.vartoint(source);
  end;


operator :=(const source : variant) dest : qword;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  dest:=variantmanager.vartoword64(source);
end;


operator :=(const source : variant) dest : int64;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  dest:=variantmanager.vartoint64(source);
end;


{ Boolean }

operator :=(const source : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  dest:=variantmanager.vartobool(source);
end;


operator :=(const source : variant) dest : wordbool;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  dest:=variantmanager.vartobool(source);
end;


operator :=(const source : variant) dest : longbool;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
   dest:=variantmanager.vartobool(source);
end;


{ Chars }

operator :=(const source : variant) dest : char;{$ifdef SYSTEMINLINE}inline;{$endif}

Var
  S : String;

begin
  VariantManager.VarToPStr(S,Source);
  If Length(S)>0 then
    Dest:=S[1];
end;


{ Strings }

operator :=(const source : variant) dest : shortstring;{$ifdef SYSTEMINLINE}inline;{$endif}

begin
  VariantManager.VarToPStr(Dest,Source);
end;

operator :=(const source : variant) dest : ansistring;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  VariantManager.vartolstr(dest, source);
end;


{ Floats }

{$ifdef SUPPORT_SINGLE}
operator :=(const source : variant) dest : single;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  dest:=variantmanager.vartoreal(source);
end;
{$endif SUPPORT_SINGLE}


{$ifdef SUPPORT_DOUBLE}
operator :=(const source : variant) dest : double;{$ifdef SYSTEMINLINE}inline;{$endif}
begin
  dest:=variantmanager.vartoreal(source);
end;
{$endif SUPPORT_DOUBLE}


{ Misc. }
operator :=(const source : variant) dest : currency;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    dest:=variantmanager.vartocurr(source);
  end;


operator :=(const source : variant) dest : tdatetime;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    dest:=variantmanager.vartotdatetime(source);
  end;


operator :=(const source : variant) dest : error;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    dest:=variantmanager.vartoint(source);
  end;
{**********************************************************************
                               Operators
 **********************************************************************}

operator or(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
//     dest:=op1;
     variantmanager.varop(dest,op2,opor);
  end;

operator and(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    // dest:=op1;
     variantmanager.varop(dest,op2,opand);
  end;

operator xor(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
  //   dest:=op1;
     variantmanager.varop(dest,op2,opxor);
  end;

operator not(const op : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
 //    dest:=op;
     variantmanager.varnot(dest);
  end;

operator shl(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
   //  dest:=op1;
     variantmanager.varop(dest,op2,opshiftleft);
  end;

operator shr(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
   //  dest:=op1;
     variantmanager.varop(dest,op2,opshiftright);
  end;

operator +(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
   //  dest:=op1;
     variantmanager.varop(dest,op2,opadd);
  end;

operator -(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
   //  dest:=op1;
     variantmanager.varop(dest,op2,opsubtract);
  end;

operator *(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    // dest:=op1;
     variantmanager.varop(dest,op2,opmultiply);
  end;

operator /(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    // dest:=op1;
     variantmanager.varop(dest,op2,opdivide);
  end;

operator **(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
   //  dest:=op1;
     variantmanager.varop(dest,op2,oppower);
  end;

operator div(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
   //  dest:=op1;
     variantmanager.varop(dest,op2,opintdivide);
  end;

operator mod(const op1,op2 : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
   //  dest:=op1;
     variantmanager.varop(dest,op2,opmodulus);
  end;

operator -(const op : variant) dest : variant;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    // dest:=op;
     variantmanager.varneg(dest);
  end;

operator =(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    // dest:=variantmanager.cmpop(op1,op2,opcmpeq);
       dest:=False;
  end;

operator <(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
  //   dest:=variantmanager.cmpop(op1,op2,opcmplt);
       dest:=False;
  end;

operator >(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    // dest:=variantmanager.cmpop(op1,op2,opcmpgt);
       dest:=False;
  end;

operator >=(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
    // dest:=variantmanager.cmpop(op1,op2,opcmpge);
       dest:=False;
  end;

operator <=(const op1,op2 : variant) dest : boolean;{$ifdef SYSTEMINLINE}inline;{$endif}
  begin
   //  dest:=variantmanager.cmpop(op1,op2,opcmplt);
       dest:=False;
  end;

procedure VarArrayRedim(var A: Variant; HighBound: SizeInt);
  begin
    variantmanager.vararrayredim(a,highbound);
  end;

procedure VarCast(var dest : variant;const source : variant;vartype : longint);

  begin
    variantmanager.varcast(dest,source,vartype);
  end;


{**********************************************************************
                        from OLEVariant assignments
 **********************************************************************}
{ Integer }

{**********************************************************************
                      Variant manager functions
 **********************************************************************}

procedure GetVariantManager(var VarMgr: TVariantManager);
begin
  VarMgr:=VariantManager;
end;

procedure SetVariantManager(const VarMgr: TVariantManager);
begin
  VariantManager:=VarMgr;
end;

function IsVariantManagerSet: Boolean;
var
   i : longint;
begin
   I:=0;
   Result:=True;
   While Result and (I<(sizeof(tvariantmanager) div sizeof(pointer))-1) do
     begin
       Result:=Pointer(ppointer(PtrUInt(@variantmanager)+i*sizeof(pointer))^)<>Pointer(@invalidvariantop);
       Inc(I);
     end;
end;


procedure initvariantmanager;
begin
   VarDispProc:=@vardisperror;
   DispCallByIDProc:=@vardisperror;
end;

{****************************************************************************
                         Run-Time Type Information (RTTI)
****************************************************************************}


{ Run-Time type information routines }

{ The RTTI is implemented through a series of constants : }

Const
       tkUnknown       = 0;
       tkInteger       = 1;
       tkChar          = 2;
       tkEnumeration   = 3;
       tkFloat         = 4;
       tkSet           = 5;
       tkMethod        = 6;
       tkSString       = 7;
       tkString        = tkSString;
       tkLString       = 8;
       tkAString       = 9;
       tkWString       = 10;
       tkVariant       = 11;
       tkArray         = 12;
       tkRecord        = 13;
       tkInterface     = 14;
       tkClass         = 15;
       tkObject        = 16;
       tkWChar         = 17;
       tkBool          = 18;
       tkInt64         = 19;
       tkQWord         = 20;
//       tkDynArray      = 21;


type
  TRTTIProc=procedure(Data,TypeInfo:Pointer);

procedure RecordRTTI(Data,TypeInfo:Pointer;rttiproc:TRTTIProc);
{
  A record is designed as follows :
    1    : tkrecord
    2    : Length of name string (n);
    3    : name string;
    3+n  : record size;
    7+n  : number of elements (N)
    11+n : N times : Pointer to type info
                     Offset in record
}
var
  Temp : pbyte;
  namelen : byte;
  count,
  offset,
  i : longint;
  info : pointer;
begin
  Temp:=PByte(TypeInfo);
  inc(Temp);
  { Skip Name }
  namelen:=Temp^;
  inc(temp,namelen+1);
  temp:=aligntoptr(temp);
  { Skip size }
  inc(Temp,4);
  { Element count }
  Count:=PLongint(Temp)^;
  inc(Temp,sizeof(Count));
  { Process elements }
  for i:=1 to count Do
    begin
      Info:=PPointer(Temp)^;
      inc(Temp,sizeof(Info));
      Offset:=PLongint(Temp)^;
      inc(Temp,sizeof(Offset));
      rttiproc (Data+Offset,Info);
    end;
end;


procedure ArrayRTTI(Data,TypeInfo:Pointer;rttiproc:TRTTIProc);
{
  An array is designed as follows :
   1    : tkArray;
   2    : length of name string (n);
   3    : NAme string
   3+n  : Element Size
   7+n  : Number of elements
   11+n : Pointer to type of elements
}
var
  Temp : pbyte;
  namelen : byte;
  count,
  size,
  i : SizeInt;
  info : pointer;
begin
  Temp:=PByte(TypeInfo);
  inc(Temp);
  { Skip Name }
  namelen:=Temp^;
  inc(temp,namelen+1);
  temp:=aligntoptr(temp);
  { Element size }
  size:=PSizeInt(Temp)^;
  inc(Temp,sizeof(Size));
  { Element count }
  Count:=PSizeInt(Temp)^;
  inc(Temp,sizeof(Count));
  Info:=PPointer(Temp)^;
  inc(Temp,sizeof(Info));
  { Process elements }
  for I:=0 to Count-1 do
    rttiproc(Data+(I*size),Info);
end;


Procedure fpc_Initialize (Data,TypeInfo : pointer);[Public,Alias : 'FPC_INITIALIZE'];  compilerproc;
begin
  case PByte(TypeInfo)^ of
//    tkAstring,tkWstring,tkInterface,tkDynArray:
    tkAstring,tkWstring,tkInterface:
      PPchar(Data)^:=Nil;
    tkArray:
      arrayrtti(data,typeinfo,@int_initialize);
    tkObject,
    tkRecord:
      recordrtti(data,typeinfo,@int_initialize);
    tkVariant:
      variant_init(PVarData(Data)^);
  end;
end;


Procedure fpc_finalize (Data,TypeInfo: Pointer);[Public,Alias : 'FPC_FINALIZE'];  compilerproc;
begin
  case PByte(TypeInfo)^ of
    tkAstring :
      begin
       fpc_AnsiStr_Decr_Ref(PPointer(Data)^);
        PPointer(Data)^:=nil;
      end;
    tkArray :
      arrayrtti(data,typeinfo,@int_finalize);
    tkObject,
    tkRecord:
      recordrtti(data,typeinfo,@int_finalize);
    tkInterface:
      begin
        Intf_Decr_Ref(PPointer(Data)^);
        PPointer(Data)^:=nil;
      end;
    tkVariant:
      variant_clear(PVarData(Data)^);
  end;
end;


Procedure fpc_Addref (Data,TypeInfo : Pointer); [Public,alias : 'FPC_ADDREF'];  compilerproc;
begin
  case PByte(TypeInfo)^ of
    tkAstring :
      fpc_AnsiStr_Incr_Ref(PPointer(Data)^);
    tkArray :
      arrayrtti(data,typeinfo,@int_addref);
    tkobject,
    tkrecord :
      recordrtti(data,typeinfo,@int_addref);
    tkInterface:
      Intf_Incr_Ref(PPointer(Data)^);
    tkVariant:
      variant_addref(pvardata(Data)^);
  end;
end;


{ alias for internal use }
{ we use another name else the compiler gets puzzled because of the wrong forward def }
procedure fpc_systemDecRef (Data, TypeInfo : Pointer);[external name 'FPC_DECREF'];

Procedure fpc_DecRef (Data, TypeInfo : Pointer);[Public,alias : 'FPC_DECREF'];  compilerproc;
begin
  case PByte(TypeInfo)^ of
    { see AddRef for comment about below construct (JM) }
    tkAstring:
      fpc_AnsiStr_Decr_Ref(PPointer(Data)^);
//    tkWstring:
//      fpc_WideStr_Decr_Ref(PPointer(Data)^);
    tkArray:
      arrayrtti(data,typeinfo,@fpc_systemDecRef);
    tkobject,
    tkrecord:
      recordrtti(data,typeinfo,@fpc_systemDecRef);
//    tkDynArray:
//      fpc_dynarray_decr_ref(PPointer(Data)^,TypeInfo);
    tkInterface:
      Intf_Decr_Ref(PPointer(Data)^);
    tkVariant:
      variant_clear(pvardata(data)^);
  end;
end;


Procedure fpc_Copy (Src, Dest, TypeInfo : Pointer);[Public,alias : 'FPC_COPY'];  compilerproc;
var
  Temp : pbyte;
  namelen : byte;
  count,
  offset,
  i : longint;
  info : pointer;
begin
  case PByte(TypeInfo)^ of
    tkAstring:
      begin
        fpc_AnsiStr_Incr_Ref(PPointer(Src)^);
        fpc_AnsiStr_Decr_Ref(PPointer(Dest)^);
        PPointer(Dest)^:=PPointer(Src)^;
      end;
  tkobject,
    tkrecord:
      begin
        Temp:=PByte(TypeInfo);
        inc(Temp);
        { Skip Name }
        namelen:=Temp^;
        inc(temp,namelen+1);
        temp:=aligntoptr(temp);

        { copy data }
        move(src^,dest^,plongint(temp)^);

        { Skip size }
        inc(Temp,4);
        { Element count }
        Count:=PLongint(Temp)^;
        inc(Temp,sizeof(Count));
        { Process elements }
        for i:=1 to count Do
          begin
            Info:=PPointer(Temp)^;
            inc(Temp,sizeof(Info));
            Offset:=PLongint(Temp)^;
            inc(Temp,sizeof(Offset));
            fpc_Copy(Src+Offset,Src+Offset,Info);
	  			end;
      end;
 end;
end;



procedure fpc_finalize_array(data,typeinfo : pointer;count,size : longint); [Public,Alias:'FPC_FINALIZEARRAY'];  compilerproc;
  var
     i : longint;
  begin
     for i:=0 to count-1 do
       int_finalize(data+size*i,typeinfo);
end;


{*****************************************************************************
                             Directory support.
*****************************************************************************}


{$ifopt R+}
{$define RangeCheckWasOn}
{$R-}
{$endif opt R+}

{$ifopt I+}
{$define IOCheckWasOn}
{$I-}
{$endif opt I+}

{$ifopt Q+}
{$define OverflowCheckWasOn}
{$Q-}
{$endif opt Q+}

{*****************************************************************************
                             Miscellaneous
*****************************************************************************}

procedure fpc_rangeerror;[public,alias:'FPC_RANGEERROR']; compilerproc;
begin
  HandleErrorFrame(201,get_frame);
end;

procedure fpc_divbyzero;[public,alias:'FPC_DIVBYZERO']; compilerproc;
begin
  HandleErrorFrame(200,get_frame);
end;

procedure fpc_overflow;[public,alias:'FPC_OVERFLOW']; compilerproc;
begin
  HandleErrorFrame(215,get_frame);
end;

procedure fpc_iocheck;[public,alias:'FPC_IOCHECK']; compilerproc;
var
  l : longint;
begin
  if InOutRes<>0 then
   begin
     l:=InOutRes;
     InOutRes:=0;
     HandleErrorFrame(l,get_frame);
   end;
end;

Function IOResult: Word; {$ifdef SYSTEMINLINE}inline;{$endif}
Begin
  IOResult := InOutRes;
  InOutRes := 0;
End;

Function GetThreadID: TThreadID; {$ifdef SYSTEMINLINE}inline;{$endif}
begin
  // ThreadID is stored in a threadvar and made available in interface
  // to allow setup of this value during thread initialization.
  Result := ThreadID;
end;

{*****************************************************************************
                         Stack check code
*****************************************************************************}

{$IFNDEF NO_GENERIC_STACK_CHECK}

{$IFOPT S+}
{$DEFINE STACKCHECK}
{$ENDIF}
{$S-}
procedure fpc_stackcheck(stack_size:Cardinal);[public,alias:'FPC_STACKCHECK'];
var
  c : Pointer;
begin
  { Avoid recursive calls when called from the exit routines }
  if StackError then
   exit;
  c := Sptr - (stack_size + STACK_MARGIN);
  if (c <= StackBottom) then
   begin
     StackError:=True;
     HandleError(202);
   end;
end;
{$IFDEF STACKCHECK}
{$S+}
{$ENDIF}
{$UNDEF STACKCHECK}

{$ENDIF NO_GENERIC_STACK_CHECK}

{*****************************************************************************
                        Initialization / Finalization
*****************************************************************************}

const
  maxunits=1024; { See also files.pas of the compiler source }
type
  TInitFinalRec=record
    InitProc,
    FinalProc : TProcedure;
  end;
  TInitFinalTable=record
    TableCount,
    InitCount  : QWord;
    Procs      : array[1..maxunits] of TInitFinalRec;
  end;
{$asmmode intel}
var
  InitFinalTable : TInitFinalTable;external name 'INITFINAL';

procedure fpc_InitializeUnits;[public,alias:'FPC_INITIALIZEUNITS']; compilerproc;
var
  i : QWord;
begin
  { call cpu/fpu initialisation routine }
  // boot FPU
  with InitFinalTable do
   begin
     for i:=1 to QWord(TableCount) do
      begin
        if assigned(Procs[i].InitProc) then
         Procs[i].InitProc();
        InitCount:=i;
      end;
   end;
  if assigned(InitProc) then
    TProcedure(InitProc)();
end;

{$asmmode GAS}
procedure FinalizeUnits;[public,alias:'FPC_FINALIZEUNITS'];
begin
  with InitFinalTable do
   begin
     while (InitCount>0) do
      begin
        // we've to decrement the cound before calling the final. code
        // else a halt in the final. code leads to a endless loop
        dec(InitCount);
        if assigned(Procs[InitCount+1].FinalProc) then
         Procs[InitCount+1].FinalProc();
      end;
   end;
end;

{$IFDEF CPUX86_64}
//procedure install_exception_handlers;forward;
//procedure remove_exception_handlers;forward;
procedure PascalMain; stdcall; external name 'PASCALMAIN';
procedure fpc_do_exit; stdcall; external name 'FPC_DO_EXIT';

var
  { old compilers emitted a reference to _fltused if a module contains
    floating type code so the linker could leave away floating point
    libraries or not. VC does this as well so we need to define this
    symbol as well (FK)
  }
  _fltused : int64;cvar;public;
  { value of the stack segment
    to check if the call stack can be written on exceptions }
//  _SS : Cardinal;


{$ENDIF}


{*****************************************************************************
                          Error / Exit / ExitProc
*****************************************************************************}

Procedure InternalExit;
var
  current_exit: Procedure;
  dump: string;
Begin
  while exitProc<>nil Do
   Begin
     InOutRes:=0;
     current_exit:=tProcedure(exitProc);
     exitProc:=nil;
     current_exit();
   End;
  { Finalize units }
  FinalizeUnits;
  { Show runtime error and exit }
  If erroraddr<>nil Then
   Begin
     { to get a nice symify }
//     Writeln(stdout,BackTraceStrFunc(Erroraddr));
     dump_stack(dump, ErrorBase);
   End;
End;


Procedure do_exit;[Public,Alias:'FPC_DO_EXIT'];
begin
  // TODO: do the exit cleaner
  // InternalExit;
  System_exit;
end;


Procedure lib_exit;[Public,Alias:'FPC_LIB_EXIT'];
begin
  InternalExit;
end;


Procedure Halt(ErrNum: Byte);
Begin
  ExitCode := ErrNum;
  Do_Exit;
end;


function SysBackTraceStr (Addr: Pointer): ShortString;
begin
  SysBackTraceStr:='  $'+HexStr(Ptrint(addr),sizeof(PtrInt)*2);
end;


Procedure HandleErrorAddrFrame (Errno : longint;addr,frame : Pointer);[public,alias:'FPC_BREAK_ERROR'];
begin
  If pointer(ErrorProc)<>Nil then
    ErrorProc(Errno,addr,frame);
  errorcode:=word(Errno);
  erroraddr:=addr;
  errorbase:=frame;
  if ExceptAddrStack <> nil then
    raise TObject(nil) at addr,frame;
  if errorcode <= maxExitCode then
    halt(errorcode)
  else
    halt(255)
end;

Procedure HandleErrorFrame (Errno : longint;frame : Pointer);
{
  Procedure to handle internal errors, i.e. not user-invoked errors
  Internal function should ALWAYS call HandleError instead of RunError.
  Can be used for exception handlers to specify the frame
}
begin
  HandleErrorAddrFrame(Errno,get_caller_addr(frame),get_caller_frame(frame));
end;


Procedure HandleError (Errno : longint);[public,alias : 'FPC_HANDLEERROR'];
{
  Procedure to handle internal errors, i.e. not user-invoked errors
  Internal function should ALWAYS call HandleError instead of RunError.
}
begin
  HandleErrorFrame(Errno,get_frame);
end;


procedure RunError(w : word);[alias: 'FPC_RUNERROR'];
begin
  errorcode:=w;
  erroraddr:=get_caller_addr(get_frame);
  errorbase:=get_caller_frame(get_frame);
  if errorcode <= maxExitCode then
    halt(errorcode)
  else
    halt(255)
end;


Procedure RunError;{$ifdef SYSTEMINLINE}inline;{$endif}
Begin
  RunError (0);
End;

(*

Procedure Halt;{$ifdef SYSTEMINLINE}inline;{$endif}
Begin
  Halt(0);
End;
*)

Procedure dump_stack(var f: string; bp : Pointer);
var
  i : Longint;
  prevbp : Pointer;
  is_dev : boolean;
  caller_frame,
  caller_addr : Pointer;
Begin
  try
    prevbp:=bp-1;
    i:=0;
    is_dev:= False;
    while bp > prevbp Do
     Begin
       caller_addr := get_caller_addr(bp);
       caller_frame := get_caller_frame(bp);
       if (caller_addr=nil) or
          (caller_frame=nil) then
         break;
       f := f+BackTraceStrFunc(caller_addr);
       f := f+#13#10;
       Inc(i);
       If ((i>max_frame_dump) and is_dev) or (i>256) Then
         break;
       prevbp:=bp;
       bp:=caller_frame;
     End;
   except
     { prevent endless dump if an exception occured }
   end;
end;


Type
  PExitProcInfo = ^TExitProcInfo;
  TExitProcInfo = Record
    Next     : PExitProcInfo;
    SaveExit : Pointer;
    Proc     : TProcedure;
  End;
const
  ExitProcList: PExitProcInfo = nil;

Procedure DoExitProc;
var
  P    : PExitProcInfo;
  Proc : TProcedure;
Begin
  P:=ExitProcList;
  ExitProcList:=P^.Next;
  ExitProc:=P^.SaveExit;
  Proc:=P^.Proc;
  DisPose(P);
  Proc();
End;


Procedure AddExitProc(Proc: TProcedure);
var
  P : PExitProcInfo;
Begin
  New(P);
  P^.Next:=ExitProcList;
  P^.SaveExit:=ExitProc;
  P^.Proc:=Proc;
  ExitProcList:=P;
  ExitProc:=@DoExitProc;
End;


{*****************************************************************************
                          Abstract/Assert support.
*****************************************************************************}

procedure fpc_AbstractErrorIntern;compilerproc;[public,alias : 'FPC_ABSTRACTERROR'];
begin
  If pointer(AbstractErrorProc)<>nil then
    AbstractErrorProc();
  HandleErrorFrame(211,get_frame);
end;

Procedure fpc_assert(Const Msg,FName:Shortstring;LineNo:Longint;ErrorAddr:Pointer); [Public,Alias : 'FPC_ASSERT']; compilerproc;
begin
  if pointer(AssertErrorProc)<>nil then
    AssertErrorProc(Msg,FName,LineNo,ErrorAddr)
  else
    HandleErrorFrame(227,get_frame);
end;

Procedure SysAssert(Const Msg,FName:Shortstring;LineNo:Longint;ErrorAddr:Pointer);
begin
  Halt(227);
end;

procedure fpc_raise_nested;[public,alias:'FPC_RAISE_NESTED']; compilerproc;
begin
   while true do;
  //Internal_PopSecondObjectStack.Free;
  //Internal_Reraise;
end;

procedure fpc_doneexception;[public,alias:'FPC_DONEEXCEPTION'] compilerproc;
begin
end;



{*****************************************************************************
                       SetJmp/LongJmp support.
*****************************************************************************}


function fpc_setjmp(var S : jmp_buf) : longint;assembler;[Public, alias : 'FPC_SETJMP'];nostackframe; compilerproc;
  asm
{$ifdef win64}
    // Save registers.
    movq %rbx,(%rcx)
    movq %rbp,8(%rcx)
    movq %r12,16(%rcx)
    movq %r13,24(%rcx)
    movq %r14,32(%rcx)
    movq %r15,40(%rcx)
    movq %rsi,64(%rcx)
    movq %rdi,72(%rcx)
    leaq 8(%rsp),%rdx       // Save SP as it will be after we return.
    movq %rdx,48(%rcx)
    movq 0(%rsp),%r8        // Save PC we are returning to now.
    movq %r8,56(%rcx)
    xorq %rax,%rax
{$else win64}
    // Save registers.
    movq %rbx,(%rdi)
    movq %rbp,8(%rdi)
    movq %r12,16(%rdi)
    movq %r13,24(%rdi)
    movq %r14,32(%rdi)
    movq %r15,40(%rdi)
    leaq 8(%rsp),%rdx       // Save SP as it will be after we return.
    movq %rdx,48(%rdi)
    movq 0(%rsp),%rsi       // Save PC we are returning to now.
    movq %rsi,56(%rdi)
    xorq %rax,%rax
{$endif win64}
  end;


procedure fpc_longjmp(var S : jmp_buf;value : longint);assembler;[Public, alias : 'FPC_LONGJMP'];nostackframe; compilerproc;
  asm
{$ifdef win64}
    // Restore registers.
    movq (%rcx),%rbx
    movq 8(%rcx),%rbp
    movq 16(%rcx),%r12
    movq 24(%rcx),%r13
    movq 32(%rcx),%r14
    movq 40(%rcx),%r15
    // Set return value for setjmp.
    test %edx,%edx
    mov $01,%eax
    cmove %eax,%edx
    mov %edx,%eax
    movq 48(%rcx),%rsp
    movq 56(%rcx),%rdx
    movq 64(%rcx),%rsi
    movq 72(%rcx),%rdi
    jmpq *%rdx
{$else win64}
    // Restore registers.
    movq (%rdi),%rbx
    movq 8(%rdi),%rbp
    movq 16(%rdi),%r12
    movq 24(%rdi),%r13
    movq 32(%rdi),%r14
    movq 40(%rdi),%r15
    // Set return value for setjmp.
    test %esi,%esi
    mov $01,%eax
    cmove %eax,%esi
    mov %esi,%eax
    movq 56(%rdi),%rdx
    movq 48(%rdi),%rsp
    jmpq *%rdx
{$endif win64}
  end;

{$ifdef IOCheckWasOn}
{$I+}
{$endif}

{$ifdef RangeCheckWasOn}
{$R+}
{$endif}

{$ifdef OverflowCheckWasOn}
{$Q+}
{$endif}

{*****************************************************************************
                             Memory Manager
*****************************************************************************}

procedure GetMemoryManager(var MemMgr:TMemoryManager);
begin
	MemMgr := MemoryManager;
end;


procedure SetMemoryManager(const MemMgr:TMemoryManager);
begin
	MemoryManager := MemMgr;
end;


function IsMemoryManagerSet:Boolean;
begin
	//IsMemoryManagerSet := (MemoryManager.GetMem<>@SysGetMem) or (MemoryManager.FreeMem<>@SysFreeMem);
	IsMemoryManagerSet := False;
end;


procedure GetMem(var P: Pointer; Size: PtrInt);
begin
        //  P := nil;
	P := MemoryManager.GetMem(Size);
end;



procedure FreeMem(P: Pointer; Size: PtrInt);
begin
	MemoryManager.FreeMem(p);
end;

{ Delphi style }
function FreeMem(P: Pointer): PtrInt;
begin
	Freemem := MemoryManager.FreeMem(P);
	//Freemem := 0;
end;


function GetMem(Size: PtrInt): Pointer;
begin
    //     Result := nil;
	Result := MemoryManager.GetMem(Size);
end;

function GetMemory(size:ptrint):pointer;

begin
 //GetMemory := Getmem(size);
 GetMemory := nil;
end;

function ReAllocMem(var P: Pointer; NewSize: PtrUInt): Pointer;
begin
	Result := MemoryManager.ReAllocMem(P, NewSize);
	//Result := nil;
end;

{ Needed for calls from Assembler }
function fpc_getmem(size:ptrint):pointer;compilerproc;[public,alias:'FPC_GETMEM'];
begin
     //Result := nil;
     Result := MemoryManager.GetMem(size);
end;

procedure fpc_freemem(p:pointer);compilerproc;[public,alias:'FPC_FREEMEM'];
begin
//	if p <> nil then
  //	MemoryManager.FreeMem(p);
end;

function SysGetMem(size : ptrint):pointer;
begin
	Result := nil;
end;

function SysFreeMem(p: pointer): ptrint;
begin
	Result := 0; // Perform nothing 
end;

Function SysFreeMemSize(p: pointer; size: ptrint): ptrint;
begin
	Result := 0;
end;

function SysMemSize(p: pointer): ptrint;
begin
	Result := 0;
end;

function SysAllocMem(Size: PtrInt): Pointer;
begin
  Result := nil;
 // Result := MemoryManager.GetMem(size);
 // if Result <> nil then
 //   FillChar(Result^, MemoryManager.MemSize(Result), 0);
end;

function SysReAllocMem(var p: pointer; size: ptruint):pointer;
begin
  Result := nil;
end;

Var
  CurrentTM : TThreadManager;

{*****************************************************************************
                           Threadvar initialization
*****************************************************************************}

procedure InitThread(stklen: cardinal);
begin
  //SysResetFPU;
  { ExceptAddrStack and ExceptObjectStack are threadvars       }
  { so every thread has its on exception handling capabilities }
  SysInitExceptions;
  { Open all stdio fds again }
  //SysInitStdio;
  InOutRes := 0;
  // ErrNo:=0;
  { Stack checking }
  StackLength := stklen;
  StackBottom := Sptr - StackLength;
  ThreadID := CurrentTM.GetCurrentThreadID();
end;

function BeginThread(ThreadFunction: tthreadfunc): TThreadID;
var
  dummy: TThreadID;
begin
  Result := BeginThread(nil, DefaultStackSize, ThreadFunction, nil, 0, dummy);
end;

function BeginThread(ThreadFunction: tthreadfunc; p: pointer): TThreadID;
var
  dummy: TThreadID;
begin
  Result := BeginThread(nil, DefaultStackSize, ThreadFunction, p, 0, dummy);
end;

function BeginThread(ThreadFunction: tthreadfunc; p: Pointer; var ThreadId: TThreadID): TThreadID;
begin
  Result := BeginThread(nil, DefaultStackSize, ThreadFunction, p, 0, ThreadId);
end;

procedure EndThread;
begin
  EndThread(0);
end;

function BeginThread(sa: Pointer; stacksize: dword; ThreadFunction: tthreadfunc; p: pointer; creationFlags: dword;  var ThreadId: TThreadID): TThreadID;
begin
  Result := CurrentTM.BeginThread(sa, stacksize, threadfunction, P, creationflags, ThreadID);
end;

procedure EndThread(ExitCode : DWord);
begin
  CurrentTM.EndThread(ExitCode);
end;

function  SuspendThread (threadHandle: TThreadID) : dword;

begin
  Result:=CurrentTM.SuspendThread(ThreadHandle);
end;

function ResumeThread  (threadHandle: TThreadID) : dword;

begin
  Result:=CurrentTM.ResumeThread(ThreadHandle);
end;

procedure ThreadSwitch;

begin
  CurrentTM.ThreadSwitch;
end;

function  KillThread (threadHandle : TThreadID) : dword;

begin
  Result:=CurrentTM.KillThread(ThreadHandle);
end;

function  WaitForThreadTerminate (threadHandle: TThreadID; TimeoutMs : longint) : dword;

begin
  Result:=CurrentTM.WaitForThreadTerminate(ThreadHandle,TimeOutMS);
end;

function  ThreadSetPriority (threadHandle: TThreadID; Prio: longint): boolean;
begin
  Result:=CurrentTM.ThreadSetPriority(ThreadHandle,Prio);
end;

function  ThreadGetPriority (threadHandle: TThreadID): longint;
begin
  Result:=CurrentTM.ThreadGetPriority(ThreadHandle);
end;

function  GetCurrentThreadId : TThreadID;

begin
  Result:=CurrentTM.GetCurrentThreadID();
end;

procedure InitCriticalSection(var cs : TRTLCriticalSection);

begin
  CurrentTM.InitCriticalSection(cs);
end;

procedure DoneCriticalsection(var cs : TRTLCriticalSection);
begin
  CurrentTM.DoneCriticalSection(cs);
end;

procedure EnterCriticalsection(var cs : TRTLCriticalSection);
begin
  CurrentTM.EnterCriticalSection(cs);
end;

procedure LeaveCriticalsection(var cs : TRTLCriticalSection);
begin
  CurrentTM.LeaveCriticalSection(cs);
end;

Function GetThreadManager(Var TM : TThreadManager) : Boolean;
begin
  TM:=CurrentTM;
  Result:=True;
end;

Function SetThreadManager(Const NewTM : TThreadManager; Var OldTM : TThreadManager) : Boolean;
begin
  GetThreadManager(OldTM);
  Result:=SetThreadManager(NewTM);
end;

Function SetThreadManager(Const NewTM : TThreadManager) : Boolean;
begin
  Result:=True;
  If Assigned(CurrentTM.DoneManager) then
    Result:=CurrentTM.DoneManager();
  If Result then
    begin
    CurrentTM:=NewTM;
    If Assigned(CurrentTM.InitManager) then
      Result:=CurrentTM.InitManager();
    end;
end;

function  BasicEventCreate(EventAttributes : Pointer; AManualReset,InitialState : Boolean;const Name : ansistring):pEventState;
begin
  result:=currenttm.BasicEventCreate(EventAttributes,AManualReset,InitialState, Name);
end;

procedure basiceventdestroy(state:peventstate);
begin
  currenttm.basiceventdestroy(state);
end;

procedure basiceventResetEvent(state:peventstate);
begin
  currenttm.basiceventResetEvent(state);
end;

procedure basiceventSetEvent(state:peventstate);

begin
  currenttm.basiceventSetEvent(state);
end;

function  basiceventWaitFor(Timeout : Cardinal;state:peventstate) : longint;

begin
 result:=currenttm.basiceventWaitFor(Timeout,state);
end;

function  RTLEventCreate :PRTLEvent;

begin
  result:=currenttm.rtleventcreate();
end;


procedure RTLeventdestroy(state:pRTLEvent);

begin
  currenttm.rtleventdestroy(state);
end;

procedure RTLeventSetEvent(state:pRTLEvent);

begin
  currenttm.rtleventsetEvent(state);
end;

procedure RTLeventResetEvent(state:pRTLEvent);

begin
  currenttm.rtleventResetEvent(state);
end;

procedure RTLeventStartWait(state:pRTLEvent);

begin
  currenttm.rtleventStartWait(state);
end;

procedure RTLeventWaitFor(state:pRTLEvent);

begin
  currenttm.rtleventWaitFor(state);
end;

procedure RTLeventWaitFor(state:pRTLEvent;timeout : longint);

begin
  currenttm.rtleventWaitForTimeout(state,timeout);
end;

procedure RTLeventsync(m:trtlmethod;p:tprocedure);

begin
  currenttm.rtleventsync(m,p);
end;

{-------------------------------------------------------------------------------
                           Threadvar support
-------------------------------------------------------------------------------}

type
  pltvInitEntry = ^ltvInitEntry;
  ltvInitEntry = packed record
     varaddr : pdword;
     size    : longint;
  end;

  TltvInitTablesTable = packed record
    count  : dword;
    tables : packed array [1..32767] of pltvInitEntry;
  end;

var
  ThreadvarTablesTable: TltvInitTablesTable; external name 'FPC_THREADVARTABLES';

procedure init_unit_threadvars(TableEntry: pltvInitEntry);
begin
  while TableEntry^.varaddr <> nil do
  begin
    CurrentTM.InitThreadvar (TableEntry^.varaddr^, TableEntry^.size);
    Inc(PChar(TableEntry), SizeOf(TableEntry^));
  end;
end;

procedure init_all_unit_threadvars;
var
  I: Integer;
begin
{$ifdef DEBUG_MT}
  WriteLn ('init_all_unit_threadvars (',ThreadvarTablesTable.count,') units');
{$endif}
  for I := 1 to ThreadvarTablesTable.count do
    init_unit_threadvars(ThreadvarTablesTable.tables[I]);
end;

procedure copy_unit_threadvars(TableEntry: pltvInitEntry);
var
  oldp, newp: Pointer;
begin
  while TableEntry^.varaddr <> nil do
  begin
    newp := CurrentTM.RelocateThreadVar(TableEntry^.varaddr^);
    oldp := pointer(PChar(TableEntry^.varaddr)+SizeOf(Pointer));
    Move(oldp^, newp^, TableEntry^.size);
    Inc(PChar(TableEntry), SizeOf(TableEntry^));
  end;
end;

procedure copy_all_unit_threadvars;
var
  i : integer;
begin
{$ifdef DEBUG_MT}
  WriteLn ('copy_all_unit_threadvars (',ThreadvarTablesTable.count,') units');
{$endif}
  for i := 1 to ThreadvarTablesTable.count do
    copy_unit_threadvars(ThreadvarTablesTable.tables[i]);
end;

procedure InitThreadVars(RelocProc: Pointer);
begin
  { initialize threadvars }
  init_all_unit_threadvars;
  { allocate mem for main thread threadvars }
  CurrentTM.AllocateThreadVars;
  { copy main thread threadvars }
  copy_all_unit_threadvars;
  { install threadvar handler }
  fpc_threadvar_relocate_proc := RelocProc;
end;

{*****************************************************************************
                            Resources support
*****************************************************************************}

// some standard functions

Function ParamCount: Longint;
Begin
exit(0);
End;


function paramstr(l: longint) : string;
begin
	Result := '';
end;

procedure SysInitStdIO;
begin
end;


procedure SysInitExecPath;
begin
end;

function GetProcessID: SizeUInt;
begin
	Result := GetCurrentThreadID;
end;

procedure fpc_emptymethod;[public,alias : 'FPC_EMPTYMETHOD'];
begin
end;

begin
  SysInitExceptions;
  StackLength := 1024;
  StackBottom := Sptr - StackLength;
  InOutRes:=0;
  initvariantmanager;
end.
