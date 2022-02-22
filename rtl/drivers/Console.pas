//
// Console.pas
//
// This unit contains the functions that handle the console.
//
// Copyright (c) 2003-2021 Matias Vara <matiasevara@gmail.com>
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

unit Console;

{$I ../Toro.inc}

interface

uses Arch, Process;

procedure PrintDecimal(Value: PtrUInt);
procedure WriteConsoleF(const Format: AnsiString; const Args: array of PtrUInt);
procedure ConsoleInit;
procedure ReadFromSerial(out C: XChar);
procedure PutCtoSerial(C: XChar);

var
 HeadLess: Boolean;

const
  HEX_CHAR: array[0..15] of XChar = ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}

const
  BASE_COM_PORT = $3f8;

var
  LockConsole: UInt64 = 3;

procedure PrintString(const S: AnsiString); forward;

var
  PutC: procedure (C: Char) = PutCtoSerial;

procedure FlushUp;
begin
  PutCtoSerial(XChar(13));
  PutCtoSerial(XChar(10));
end;

procedure WaitForCompletion;
var
  lsr: Byte;
begin
  repeat
    lsr := read_portb(BASE_COM_PORT+5);
  until (lsr and $20) = $20;
end;

procedure PutCtoSerial(C: XChar);
begin
  WaitForCompletion;
  write_portb(Byte(C), BASE_COM_PORT);
end;

procedure ReadFromSerial(out C: XChar);
begin
  while (read_portb(BASE_COM_PORT+5) and 1 = 0) do;
  C := Char(read_portb(BASE_COM_PORT));
end;

{$IFDEF DCC}
procedure FillWord(var X; Count: Integer; Value: Word);
type
  wordarray    = array [0..high(Integer) div 2-1] of Word;
var
  I: Integer;
begin
  for I := 0 to Count-1 do
    wordarray(X)[I] := Value;
end;
{$ENDIF}

procedure PrintDecimal(Value: PtrUInt);
var
  I, Len: Byte;
  S: string[21]; // 21 is the max number of characters needed to represent 64 bits number in decimal
begin
  Len := 0;
  I := 21;
  if Value = 0 then
  begin
    PutC('0');
  end else
  begin
    while Value <> 0 do
    begin
      S[I] := AnsiChar((Value mod 10) + $30);
      Value := Value div 10;
      I := I-1;
      Len := Len+1;
    end;
    S[0] := XChar(Len);
   for I := (sizeof(S)-Len) to sizeof(S)-1 do
   begin
    PutC(S[I]);
   end;
  end;
end;

procedure PrintHexa(Value: PtrUInt);
var
  I: Byte;
  P: Boolean;
begin
  P := False;
  PutC('0');
  PutC('x');
  if (Value = 0) then
  begin
    Putc('0');
    Exit;
  end;
  for I := SizeOf(PtrUInt)*2-1 downto 0 do
  begin
   if not(P) and (HEX_CHAR[(Value shr (I*4)) and $0F] <> '0') then
     P:= True;
   if P then
     PutC(HEX_CHAR[(Value shr (I*4)) and $0F]);
  end;
end;

procedure PrintString(const S: AnsiString);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    PutC(S[I]);
end;

procedure WriteConsoleF(const Format: AnsiString; const Args: array of PtrUInt);
var
  ArgNo: LongInt;
  I, J: LongInt;
  Value: QWORD;
  Values: PXChar;
  tmp: TNow;
  ValueSt: PAnsiString;
begin
  If HeadLess then
    Exit;
  DisableInt;
  SpinLock (3,4,LockConsole);

  ArgNo := 0 ;
  J := 1;
  while J <= Length(Format) do
  begin
    if (Format[J] = '%') and (High(Args) <> -1) and (High(Args) >= ArgNo) then
    begin
      Inc(J);
      if J > Length(Format) then
      begin
        LockConsole := 3;
        RestoreInt;
        Exit;
      end;
      case Format[J] of
        'c':
           begin
             PutC(XChar(args[ArgNo]));
           end;
        'h':
           begin
            Value := args[ArgNo];
            PrintHexa(Value);
           end;
        'd':
           begin
            Value := args[ArgNo];
            PrintDecimal (Value);
           end;
        '%':
           begin
            PutC('%');
           end;
        's':
           begin
            ValueSt := Pointer(args[ArgNo]);
            PrintString (ValueSt^);
           end;
        'p':
           begin
             Values := pointer(args[ArgNo]);
             while Values^ <> #0 do
             begin
               PutC(Values^);
               Inc(Values);
             end;
           end;
        else
        begin
          Inc(J);
          Continue;
        end;
      end;
      Inc(J);
      Inc(ArgNo);
      Continue;
    end;
    if Format[J] = '\' then
    begin
      Inc(J);
      if J > Length(Format) then
      begin
        LockConsole := 3;
        RestoreInt;
        Exit;
      end;
      case Format[J] of
        'c':
          begin
            Inc(J);
          end;
        'n':
          begin
            FlushUp;
            Inc(J);
          end;
        '\':
          begin
            PutC('\');
            Inc(J);
          end;
        'v':
          begin
            I := 1;
            while I < 10 do
            begin
              PutC(' ');
              Inc(I);
            end;
            J:=J+1;
          end;
        't':
          begin
            Now(@tmp);
            if (tmp.Day < 10) then
              PrintDecimal (0);
            PrintDecimal (tmp.Day);
            PutC('/');
            if (tmp.Month < 10) then
              PrintDecimal (0);
            PrintDecimal (tmp.Month);
            PutC('/');
            PrintDecimal (tmp.Year);
            PutC('-');
            if (tmp.Hour < 10) then
              PrintDecimal (0);
            PrintDecimal (tmp.Hour);
            PutC(':');
            if (tmp.Min < 10) then
              PrintDecimal (0);
            PrintDecimal (tmp.Min);
            PutC(':');
            if (tmp.Sec < 10) then
              PrintDecimal (0);
            PrintDecimal (tmp.Sec);
            Inc(J);
          end;
        else
        begin
          PutC('\');
          PutC(Format[J]);
        end;
    end;
    Continue;
    end;
    PutC(Format[J]);
    Inc(J);
  end;
  LockConsole := 3;
  RestoreInt;
end;

procedure ConsoleInit;
begin
  HeadLess := false;
  write_portb ($83, BASE_COM_PORT+3);
  write_portb (0, BASE_COM_PORT+1);
  write_portb (1, BASE_COM_PORT);
  write_portb (3, BASE_COM_PORT+3);
end;

end.

