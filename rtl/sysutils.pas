unit SysUtils;

{$I Toro.inc}


interface

type
{$IFDEF DELPHI}
  TSysCharSet = set of Char;
{$ENDIF}

  Exception = class(TObject)
  private
    FMessage: string;
  public
    constructor Create(const Msg: string);
//    constructor CreateFmt(const msg: string; const args: array of const);
    property Message : string read FMessage write FMessage;
  end;
  ExceptClass = class of Exception;

function CompareMem(P1, P2: Pointer; Length: Cardinal): Boolean;
function CompareMemRange(P1, P2: Pointer; Length: Cardinal): Integer;
function CompareStr(const S1, S2: string): Integer;
function CompareText(const S1, S2: string): Integer;
//Function Format(Const Fmt : AnsiString; const Args : Array of const) : AnsiString;
{$IFDEF DELPHI}
procedure DivMod(Dividend: Integer; Divisor: Word; var Result, Remainder: Word);
function StrLen(const Str: PChar): Cardinal;
{$ENDIF}

implementation

function CompareMem(P1, P2: Pointer; Length: cardinal): Boolean;
var
  i: cardinal;
begin
  Result:=True;
  I:=0;
  If (P1)<>(P2) then
    While Result and (i<Length) do
      begin
      Result:=PByte(P1)^=PByte(P2)^;
      Inc(I);
      Inc(pchar(P1));
      Inc(pchar(P2));
      end;
end;

{   CompareMemRange returns the result of comparison of Length bytes at P1 and P2
    case       result
    P1 < P2    < 0
    P1 > P2    > 0
    P1 = P2    = 0    }

function CompareMemRange(P1, P2: Pointer; Length: cardinal): integer;
var
  I: Cardinal;
begin
  I := 0;
  Result := 0;
  while (Result = 0) and (I < Length) do
  begin
    Result := Byte(PChar(P1)^)-Byte(PChar(P2)^);
    P1 := pchar(P1)+1;            // VP compat.
    P2 := pchar(P2)+1;
    Inc(I);
   end ;
end ;


{   CompareStr compares S1 and S2, the result is the based on
    substraction of the ascii values of the characters in S1 and S2
    case     result
    S1 < S2  < 0
    S1 > S2  > 0
    S1 = S2  = 0     }

function CompareStr(const S1, S2: string): Integer;
var
  Count, Count1, Count2: Integer;
begin
//  result := 0;
  Count1 := Length(S1);
  Count2 := Length(S2);
  if Count1 > Count2 then
    Count := Count2
  else
    Count := Count1;
  Result := CompareMemRange(@S1[1], @S2[1], Count);
  if Result = 0 then
    Result := Count1-Count2;
end;

{   CompareText compares S1 and S2, the result is the based on
    substraction of the ascii values of characters in S1 and S2
    comparison is case-insensitive
    case     result
    S1 < S2  < 0
    S1 > S2  > 0
    S1 = S2  = 0     }

function CompareText(const S1, S2: string): integer;
var
  i, count, count1, count2: integer; Chr1, Chr2: byte;
begin
  result := 0;
  Count1 := Length(S1);
  Count2 := Length(S2);
  if (Count1>Count2) then
    Count := Count2
  else
    Count := Count1;
  i := 0;
  while (result=0) and (i<count) do
    begin
    inc (i);
     Chr1 := byte(s1[i]);
     Chr2 := byte(s2[i]);
     if Chr1 in [97..122] then
       dec(Chr1,32);
     if Chr2 in [97..122] then
       dec(Chr2,32);
     result := Chr1 - Chr2;
     end ;
  if (result = 0) then
    result:=(count1-count2);
end;

(*
Const
  feInvalidFormat   = 1;
  feMissingArgument = 2;
  feInvalidArgIndex = 3;


Procedure DoFormatError (ErrCode : Longint);
begin
  //!! must be changed to contain format string...
  Case ErrCode of
   feInvalidFormat : raise Exception.Create('InvalidFormat');
   feMissingArgument : raise Exception.Create('ArgumentMissing');
   feInvalidArgIndex : raise Exception.Create('InvalidArgIndex');
 end;
end;

{$IFDEF DELPHI}
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

function space (b : byte): shortstring;
begin
  Result[0] := chr(b);
  FillChar (Result[1], b, ' ');
end;

{$ENDIF}

function Format (Const Fmt : AnsiString; const Args : Array of const) : AnsiString;
var
	ChPos, OldPos, ArgPos, DoArg, Len: Integer;
    Hs,ToAdd: AnsiString;
    Index : Integer;
    Width,Prec : Longint;
    Left : Boolean;
    Fchar : char;
    vq: qword;

  {
    ReadFormat reads the format string. It returns the type character in
    uppercase, and sets index, Width, Prec to their correct values,
    or -1 if not set. It sets Left to true if left alignment was requested.
    In case of an error, DoFormatError is called.
  }

  function ReadFormat : Char;
  var
  	Value : longint;

    procedure ReadInteger;
		var
    	Code: Integer;
      S: string;
    begin
      If Value<>-1 then exit; // Was already read.
      OldPos:=chPos;
      While (Chpos<=Len) and (Pos(Fmt[chpos],'1234567890')<>0) do
      	Inc(chpos);
      If Chpos>len then
        DoFormatError(feInvalidFormat);
      If Fmt[Chpos]='*' then
        begin
        If (Chpos>OldPos) or (ArgPos>High(Args))
           or (Args[ArgPos].Vtype<>vtInteger) then
          DoFormatError(feInvalidFormat);
        Value:=Args[ArgPos].VInteger;
        Inc(ArgPos);
        Inc(chPos);
        end
      else
      begin
        If (OldPos<chPos) Then
        begin
        	S := Copy(Fmt,OldPos,ChPos-OldPos);
          Val(S, value, Code);
          // This should never happen !!
          if Code > 0 then
          	DoFormatError (feInvalidFormat);
        end
        else
          Value:=-1;
      end;
    end;

    Procedure ReadIndex;

    begin
      ReadInteger;
      If Fmt[ChPos]=':' then
        begin
        If Value=-1 then DoFormatError(feMissingArgument);
        Index:=Value;
        Value:=-1;
        Inc(Chpos);
        end;
{$ifdef fmtdebug}
      Log ('Read index');
{$endif}
    end;

    Procedure ReadLeft;

    begin
      If Fmt[chpos]='-' then
        begin
        left:=True;
        Inc(chpos);
        end
      else
        Left:=False;
{$ifdef fmtdebug}
      Log ('Read Left');
{$endif}
    end;

    Procedure ReadWidth;

    begin
      ReadInteger;
      If Value<>-1 then
        begin
        Width:=Value;
        Value:=-1;
        end;
{$ifdef fmtdebug}
      Log ('Read width');
{$endif}
    end;

    Procedure ReadPrec;

    begin
      If Fmt[chpos]='.' then
        begin
        inc(chpos);
        ReadInteger;
        If Value=-1 then
         Value:=0;
        prec:=Value;
        end;
{$ifdef fmtdebug}
      Log ('Read precision');
{$endif}
    end;

{$ifdef INWIDEFORMAT}
  var
    FormatChar : TFormatChar;
{$endif INWIDEFORMAT}

  begin
{$ifdef fmtdebug}
    Log ('Start format');
{$endif}
    Index:=-1;
    Width:=-1;
    Prec:=-1;
    Value:=-1;
    inc(chpos);
    If Fmt[Chpos]='%' then
      begin
        Result:='%';
        exit;                           // VP fix
      end;
    ReadIndex;
    ReadLeft;
    ReadWidth;
    ReadPrec;
{$ifdef INWIDEFORMAT}
    FormatChar:=UpCase(Fmt[ChPos])[1];
    if word(FormatChar)>255 then
      ReadFormat:=#255
    else
      ReadFormat:=FormatChar;
{$else INWIDEFORMAT}
    ReadFormat:=Upcase(Fmt[ChPos]);
{$endif INWIDEFORMAT}
{$ifdef fmtdebug}
    Log ('End format');
{$endif}
end;


{$ifdef fmtdebug}
Procedure DumpFormat (C : char);
begin
  Write ('Fmt : ',fmt:10);
  Write (' Index : ',Index:3);
  Write (' Left  : ',left:5);
  Write (' Width : ',Width:3);
  Write (' Prec  : ',prec:3);
  Writeln (' Type  : ',C);
end;
{$endif}


function Checkarg (AT : Integer; err:boolean):boolean;
{
  Check if argument INDEX is of correct type (AT)
  If Index=-1, ArgPos is used, and argpos is augmented with 1
  DoArg is set to the argument that must be used.
}
begin
  result:=false;
  if Index=-1 then
    DoArg:=Argpos
  else
    DoArg:=Index;
  ArgPos:=DoArg+1;
  If (Doarg>High(Args)) or (Args[Doarg].Vtype<>AT) then
   begin
     if err then
      DoFormatError(feInvalidArgindex);
     dec(ArgPos);
     exit;
   end;
  result:=true;
end;

Const Zero = '000000000000000000000000000000000000000000000000000000000000000';

begin
  Result:='';
  Len:=Length(Fmt);
  Chpos:=1;
  OldPos:=1;
  ArgPos:=0;
  While chpos<=len do
    begin
    While (ChPos<=Len) and (Fmt[chpos]<>'%') do
      inc(chpos);
    If ChPos>OldPos Then
      Result:=Result+Copy(Fmt,OldPos,Chpos-Oldpos);
    If ChPos<Len then
      begin
      FChar:=ReadFormat;
{$ifdef fmtdebug}
      DumpFormat(FCHar);
{$endif}
      Case FChar of
        'D' : begin
              if Checkarg(vtinteger,false) then
                Str(Args[Doarg].VInteger,ToAdd)
              else if CheckArg(vtInt64,false) then
                Str(Args[DoArg].VInt64^,toadd)
{$IFDEF FPC}
              else if CheckArg(vtQWord,true) then
                Str(int64(Args[DoArg].VQWord^),toadd)
{$ENDIF}
              ;
              Width:=Abs(width);
              Index:=Prec-Length(ToAdd);
              If ToAdd[1]<>'-' then
                ToAdd:=StringOfChar('0',Index)+ToAdd
              else
                // + 1 to accomodate for - sign in length !!
                Insert(StringOfChar('0',Index+1),toadd,2);
              end;
        'U' : begin
              if Checkarg(vtinteger,false) then
                Str(cardinal(Args[Doarg].VInteger),ToAdd)
              else if CheckArg(vtInt64,false) then
                Str(qword(Args[DoArg].VInt64^),toadd)
{$IFDEF FPC}
              else if CheckArg(vtQWord,true) then
                Str(Args[DoArg].VQWord^,toadd)
{$ENDIF}
							;
              Width:=Abs(width);
              Index:=Prec-Length(ToAdd);
              ToAdd:=StringOfChar('0',Index)+ToAdd
              end;
//        'E' : begin
//              if CheckArg(vtCurrency,false) then
//                ToAdd:=FloatToStrF(Args[doarg].VCurrency^,ffexponent,Prec,3)
//              else if CheckArg(vtExtended,true) then
//                ToAdd:=FloatToStrF(Args[doarg].VExtended^,ffexponent,Prec,3);
//              end;
//        'F' : begin
//              if CheckArg(vtCurrency,false) then
//                ToAdd:=FloatToStrF(Args[doarg].VCurrency^,ffFixed,9999,Prec)
//              else if CheckArg(vtExtended,true) then
//                ToAdd:=FloatToStrF(Args[doarg].VExtended^,ffFixed,9999,Prec);
//              end;
//        'G' : begin
//              if CheckArg(vtCurrency,false) then
//                ToAdd:=FloatToStrF(Args[doarg].VCurrency^,ffGeneral,Prec,3)
//              else if CheckArg(vtExtended,true) then
//                ToAdd:=FloatToStrF(Args[doarg].VExtended^,ffGeneral,Prec,3);
//              end;
//        'N' : begin
//              if CheckArg(vtCurrency,false) then
//                ToAdd:=FloatToStrF(Args[doarg].VCurrency^,ffNumber,9999,Prec)
//              else if CheckArg(vtExtended,true) then
//                ToAdd:=FloatToStrF(Args[doarg].VExtended^,ffNumber,9999,Prec);
//              end;
//        'M' : begin
//              if CheckArg(vtExtended,false) then
//                ToAdd:=FloatToStrF(Args[doarg].VExtended^,ffCurrency,9999,Prec)
//              else if CheckArg(vtCurrency,true) then
//                ToAdd:=FloatToStrF(Args[doarg].VCurrency^,ffCurrency,9999,Prec);
//              end;
        'S' : begin
                if CheckArg(vtString,false) then
                  hs:=Args[doarg].VString^
                else
                  if CheckArg(vtChar,false) then
                    hs:=Args[doarg].VChar
                else
                  if CheckArg(vtPChar,false) then
                    hs:=Args[doarg].VPChar
//                else
//                  if CheckArg(vtPWideChar,false) then
//                    hs:=WideString(Args[doarg].VPWideChar)
//                else
//                  if CheckArg(vtWideChar,false) then
//                    hs:=WideString(Args[doarg].VWideChar)
//                else
//                  if CheckArg(vtWidestring,false) then
//                    hs:=WideString(Args[doarg].VWideString)
                else
                  if CheckArg(vtAnsiString,true) then
                    hs:=ansistring(Args[doarg].VAnsiString);
                Index:=Length(hs);
                If (Prec<>-1) and (Index>Prec) then
                  Index:=Prec;
                ToAdd:=Copy(hs,1,Index);
              end;
        'P' : Begin
              CheckArg(vtpointer,true);
              ToAdd := HexStr(ptrint(Args[DoArg].VPointer),sizeof(Ptrint)*2);
              // Insert ':'. Is this needed in 32 bit ? No it isn't.
              // Insert(':',ToAdd,5);
              end;
        'X' : begin
              if Checkarg(vtinteger,false) then
                 begin
                   vq:=Cardinal(Args[Doarg].VInteger);
                   index:=16;
                 end
              else
                 begin
                   CheckArg(vtInt64,true);
                   vq:=Qword(Args[DoArg].VInt64^);
                   index:=31;
                 end;
              If Prec>index then
                ToAdd:=HexStr(vq,index)
              else
                begin
                // determine minimum needed number of hex digits.
                Index:=1;
                While (qWord(1) shl (Index*4)<=vq) and (index<16) do
                  inc(Index);
                If Index>Prec then
                  Prec:=Index;
                ToAdd:=HexStr(vq,Prec);
                end;
              end;
        '%': ToAdd:='%';
      end;
      If Width<>-1 then
        If Length(ToAdd)<Width then
          If not Left then
            ToAdd := Space(Width-Length(ToAdd))+ToAdd
          else
            ToAdd:=ToAdd+space(Width-Length(ToAdd));
      Result:=Result+ToAdd;
      end;
    inc(chpos);
    Oldpos:=chpos;
    end;
end;
*)

{$IFDEF DELPHI}
procedure DivMod(Dividend: Integer; Divisor: Word; var Result, Remainder: Word);
asm
        PUSH    EBX
        MOV     EBX,EDX
        MOV     EDX,EAX
        SHR     EDX,16
        DIV     BX
        MOV     EBX,Remainder
        MOV     [ECX],AX
        MOV     [EBX],DX
        POP     EBX
end;

function StrLen(const Str: PChar): Cardinal; assembler;
asm
        MOV     EDX,EDI
        MOV     EDI,EAX
        MOV     ECX,0FFFFFFFFH
        XOR     AL,AL
        REPNE   SCASB
        MOV     EAX,0FFFFFFFEH
        SUB     EAX,ECX
        MOV     EDI,EDX
end;
{$ENDIF}

constructor Exception.Create(const Msg: string);
begin
	inherited Create;
  FMessage := Msg;
end;


{
constructor Exception.CreateFmt(const Msg: string; const args : array of const);
begin
	inherited Create;
	FMessage := Format(Msg, args);
end;
}

initialization

end.
