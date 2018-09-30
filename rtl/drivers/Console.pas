//
// Console.pas
//
// This unit contains the functions that handle the console.
//
// Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
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

procedure CleanConsole;
procedure PrintDecimal(Value: PtrUInt);
procedure WriteConsoleF(const Format: AnsiString; const Args: array of PtrUInt);
procedure ReadConsole(out C: XChar);
procedure ReadlnConsole(Format: PXChar);
procedure DisabledConsole;
procedure EnabledConsole;
procedure ConsoleInit;

var
 Color: Byte = 10;

const
  HEX_CHAR: array[0..15] of XChar = ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}


const
  CHAR_CODE : array [1..57] of XChar =
  ('0','1','2','3','4','5','6','7','8','9','0','?','=','0',' ','q','w',
   'e','r','t','y','u','i','o','p','[',']','0','0','a','s','d','f','g','h',
   'j','k','l','¤','{','}','0','0','z','x','c','v','b','n','m',',','.','-',
   '0','*','0',' ');

const
  VIDEO_OFFSET = $B8000;

type
  TConsole = record
    car: XChar;
    form: Byte;
  end;

var
  LockConsole: UInt64 = 3;

procedure PrintString(const S: AnsiString); forward;

var
  PConsole: ^TConsole;
  X, Y: Byte;
  KeyBuffer: array[1..127] of XChar;
  BufferCount: LongInt = 1 ;
  ThreadInKey: PThread = nil;
  LastChar: LongInt = 1;

procedure SetCursor(X, Y: Byte);
begin
  write_portb($0E, $3D4);
  write_portb(Y, $3D5);
  write_portb($0f, $3D4);
  write_portb(X, $3D5);
end;

procedure FlushUp;
begin
  X := 0 ;
  Move(PXChar(VIDEO_OFFSET+160)^, PXChar(VIDEO_OFFSET)^, 24*80*2);
  FillWord(PXChar(VIDEO_OFFSET+160*24)^, 80, $0720);
end;

procedure PutC(const Car: XChar);
begin
  Y := 24;
  if X > 79 then
   FlushUp;
  PConsole := Pointer(VIDEO_OFFSET + (80*2)*Y + (X*2));
  PConsole.form := color;
  PConsole.car := Car;
  X := X+1;
  SetCursor(X, Y);
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

procedure CleanConsole;
begin
  FillWord(PXChar(video_offset)^, 2000, $0720);
  X := 0;
  Y := 0;
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
  {$IFDEF ToroHeadLess}
    Exit;
  {$ENDIF}
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
        Exit ;
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
        Exit ;
      case Format[J] of
        'c':
          begin
            CleanConsole;
            Inc(J);
          end;
        'n':
          begin
            FlushUp;
            Inc(J);
            x := 0;
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
    if Format[J] = '/' then
    begin
      Inc(J);
      if Format[J] = #0 then
        Exit;
      case Format[J] of
        'n': color := 7 ;
        'a': color := 1;
        'v': color := 2;
        'V': color := 10;
        'z': color := $f;
        'c': color := 3;
        'r': color := 4;
        'R': color := 12 ;
        'N': color := $af;
      end;
      Inc(J);
      Continue;
    end;
    PutC(Format[J]);
    Inc(J);
  end;
  LockConsole := 3;
  RestoreInt;
end;

procedure KeyHandler;
var
  Key: Byte;
  PBuff: PXChar;
begin
  EOI;
  while (read_portb($64) and 1) = 1 do
  begin
    Key := read_portb($60);
    Key := 127 and Key;
    if Key and 128 <> 0 then
      Exit;
    case Key of
      29,42,58: Exit;
      14:
        begin
          if x <> 0 then
          begin
            Dec(x);
            PutC(#0);
            Dec(x);
            Setcursor(x,y);
          end;
        end;
      28:
        begin
          Inc(y);
          if y = 25 then
            FlushUp;
          SetCursor(x,y);
          Inc(BufferCount);
          if BufferCount > SizeOf(KeyBuffer) then
            BufferCount := 1;
          pbuff := @KeyBuffer[BufferCount];
          pbuff^ := #13;
          if ThreadinKey <> nil then
            ThreadinKey.state := tsReady;
        end;
      75,72,80,77: Continue;
      else
      begin
        Inc(BufferCount);
        if BufferCount > SizeOf(KeyBuffer) then
          BufferCount := 1;
        PBuff := @KeyBuffer[BufferCount];
        PBuff^ := Char_Code[Key];
        PutC(PBuff^);
        if ThreadinKey <> nil then
          ThreadinKey.state := tsReady;
      end;
    end;
  end;
end;

procedure IrqKeyb; {$IFDEF FPC} [nostackframe]; {$ENDIF} assembler;
asm
  {$IFDEF DCC} .noframe {$ENDIF}
  // save registers
  push rbp
  push rax
  push rbx
  push rcx
  push rdx
  push rdi
  push rsi
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  // protect the stack
  mov r15 , rsp
  mov rbp , r15
  sub r15 , 32
  mov  rsp , r15
  // set interruption
  sti
  // call handler
  Call KeyHandler
  mov rsp , rbp
  // restore the registers
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rsi
  pop rdi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  pop rbp
  db $48
  db $cf
end;

procedure ReadConsole(out C: XChar);
begin
  ThreadInkey := GetCurrentThread;
  if BufferCount = LastChar then
  begin
    ThreadInKey.state := tsIOPending;
    SysThreadSwitch;
  end;
  Inc(LastChar);
  if LastChar > SizeOf(KeyBuffer) then
    LastChar := SizeOf(KeyBuffer);
  C := KeyBuffer[LastChar];
  ThreadInKey := nil;
end;

procedure ReadlnConsole(Format: PXChar);
var
  C: XChar;
begin
  while True do
  begin
    ReadConsole(C);
    if C = #13 then
    begin
      Format^ := #0;
      Exit;
    end;
    Format^ := C;
    Inc(Format);
  end;
end;

procedure EnabledConsole;
begin
  {$IFDEF ToroHeadLess}
  {$ELSE}
    IrqOn(1);
  {$ENDIF}
end;

procedure DisabledConsole;
begin
  {$IFDEF ToroHeadLess}
  {$ELSE}
    IrqOff(1);
  {$ENDIF}
end;

procedure ConsoleInit;
begin
  {$IFDEF ToroHeadLess}
  {$ELSE}
    CaptureInt(33,@IrqKeyb);
  {$ENDIF}
end;

end.

