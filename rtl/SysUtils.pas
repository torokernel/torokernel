unit SysUtils;

{$I Toro.inc}

interface

type
  Exception = class(TObject)
  private
    FMessage: string;
  public
    constructor Create(const Msg: string);
//    constructor CreateFmt(const msg: string; const args: array of const);
    property Message : string read FMessage write FMessage;
  end;
  ExceptClass = class of Exception;

type
  TFormatSettings = record
    CurrencyString: string;
    CurrencyFormat: Byte;
    CurrencyDecimals: Byte;
    DateSeparator: Char;
    TimeSeparator: Char;
    ListSeparator: Char;
    ShortDateFormat: string;
    LongDateFormat: string;
    TimeAMString: string;
    TimePMString: string;
    ShortTimeFormat: string;
    LongTimeFormat: string;
    ShortMonthNames: array[1..12] of string;
    LongMonthNames: array[1..12] of string;
    ShortDayNames: array[1..7] of string;
    LongDayNames: array[1..7] of string;
    ThousandSeparator: Char;
    DecimalSeparator: Char;
    TwoDigitYearCenturyWindow: Word;
    NegCurrFormat: Byte;
  end;

  Int64Rec = packed record
     case Integer of
       0: (Lo, Hi: Cardinal);
       1: (Words: array[0..3] of Word);
       2: (Bytes: array[0..7] of Byte);
  end;


function CompareMem(P1, P2: Pointer; Length: Cardinal): Boolean;
function CompareMemRange(P1, P2: Pointer; Length: Cardinal): Integer;
function CompareStr(const S1, S2: string): Integer;
function CompareText(const S1, S2: string): Integer;
//Function Format(Const Fmt : AnsiString; const Args : Array of const) : AnsiString;
{$IFDEF DCC}
procedure DivMod(Dividend: Integer; Divisor: Word; var Result, Remainder: Word);
function StrLen(const P: PAnsiChar): Cardinal;
{$ENDIF}

var
  FormatSettings: TFormatSettings;

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

{$IFDEF DCC}
procedure DivMod(Dividend: Integer; Divisor: Word; var Result, Remainder: Word);
begin
  Result    := Dividend div Divisor;
  Remainder := Dividend mod Divisor;
end;

function StrLen(const P: PAnsiChar): Cardinal;
begin
  Result := 0;
  if P <> nil then
    while P[Result] <> #0 do
      Inc(Result);
end;
{$ENDIF}

constructor Exception.Create(const Msg: string);
begin
	inherited Create;
  FMessage := Msg;
end;

initialization

end.
