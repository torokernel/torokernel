//
// Console.pas
//
// Console Manipulation.
// NOTE: This Procedures doesn't have protection , WriteConsole doesn't have big problems but ReadConsole yes if is used in two CPUS simultaneous..
// 
// Changes:
// 27 / 03 / 2009: Adding support for QWORD parameters in Printk_() and WriteConsole().
// 08 / 02 / 2007: Rename to Console.pas  , new procedures to read and write the console by Matias Vara.
// The consoles's procedures are only for users , the kernel only need PrintK_()
// 15 / 07 / 2006 : The code was rewrited  by Matias Vara .
// 09 / 02 / 2005 :  First Version by Matias Vara .
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
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
procedure PrintK_(Format: PChar; Arg: PtrUInt);
procedure WriteConsole(const Format: string; const Args: array of PtrUInt);
procedure ReadConsole(var ch: Char);
procedure ReadlnConsole(Format: Pchar);
procedure DisabledConsole;
procedure EnabledConsole;
procedure ConsoleInit;

var
 Color: Byte = 10;

const
  HEX_CHAR: array[0..15] of Char = ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');

implementation

const
    CHAR_CODE : array [1..57] of char=
   ('0','1','2','3','4','5','6','7','8','9','0','?','=','0',' ','q','w',
   'e','r','t','y','u','i','o','p','[',']','0','0','a','s','d','f','g','h',
   'j','k','l','¤','{','}','0','0','z','x','c','v','b','n','m',',','.','-',
   '0','*','0',' ');


const
	VIDEO_OFFSET = $B8000;

type
	TConsole = record // screen text mode
		car: Char;
		form: Byte;
	end;


procedure PrintString(const S: string); forward;


var
	PConsole: ^TConsole;
	X, Y: Byte;
        KeyBuffer: array[1..127] of char;
	BufferCount: LongInt;
	ThreadInKey: PThread;
	LastChar: LongInt;
	
// position the cursor in screen 
procedure SetCursor(X, Y: Byte);
begin
	write_portb($0E,$3D4);
	write_portb(Y, $3D5);
	write_portb($0f,$3D4);
	write_portb(X, $3D5);
end;

// Put caracter to screen 
procedure putc(Car:char);
begin
  Y := 24;
  if X > 79 then
  X := 0;
{$IFDEF FPC} PConsole := pointer(VIDEO_OFFSET)  + (80*2)*Y + (X*2) ; {$ENDIF}
{$IFDEF DELPHI} PConsole := pointer(VIDEO_OFFSET + (80*2)*Y + (X*2)); {$ENDIF}
  PConsole.form := color;
  PConsole.car := Car;
  X := X+1;
  SetCursor(X, Y);
end;

{$IFDEF DELPHI}
procedure fillword(var x; Count: Integer; Value: Word);
type
  longintarray = array [0..high(Integer) div 4-1] of longint;
  wordarray    = array [0..high(Integer) div 2-1] of word;
var
  i,v : longint;
begin
  if Count <= 0 then exit;
  // aligned?
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
{$ENDIF}


// Flush up the screen 
procedure Flushp;
begin
  X := 0 ;
  Move(PChar(VIDEO_OFFSET+160)^, PChar(VIDEO_OFFSET)^, 24*80*2);
  fillword(PChar(VIDEO_OFFSET+160*24)^, 80, $0720);
end;




// Print in decimal form
//
procedure PrintDecimal(Value: PtrUInt);
var
 I, Len: Byte;
 S: string[64];
begin
Len := 0;
I := 10;
if Value = 0 then
begin
 putc('0');
 end else
 begin
  while Value <> 0 do
  begin
   S[I] := Chr((Value mod 10) + $30);
   Value := Value div 10;
   I := I-1;
   Len := Len+1;
  end;
  if (Len <> 10) then
  begin
   S[0] := chr(Len);
   for I := 1 to Len do
   begin
    S[I] := S[11-Len];
    Len := Len-1;
   end;
   end else
   begin
    S[0] := chr(10);
   end;
   for I := 1 to ord(S[0]) do
   begin
    putc(S[I]);
   end;
  end;
end;


procedure PrintHexa(Value: PtrUInt);
var
  I: Byte;
begin
  putc('0');
  putc('x');
  for I := SizeOf(PtrUInt)*2-1 downto 0 do
    putc(HEX_CHAR[(Value shr I*4) and $0F]);
end;

procedure PrintString(const S: string);
var
	I: Integer;
begin
	for I := 1 to Length(S) do
  	putc(S[I]);
end;

// Clean the screen 
procedure CleanConsole;
begin
  fillword (PChar(video_offset)^, 2000, $0720);
	X := 0;
	Y := 0;
end;

// Format: pointer to char
// args : array of types 
//
// Simple printer function  . 
//
procedure PrintK_(Format: PChar; Arg: PtrUInt);
var
  ArgNo: PtrUInt;
  I: LongInt;
begin
  ArgNo := 0 ;
  while (Format^ <> #0) do
  begin
    // we have only one argument
    if (Format^ = '%') and (Argno = 0)then
    begin
      Format := Format+1;
      if Format^ = #0 then
      	Exit ;
      case Format^ of
        'h': PrintHexa(Arg);
     	'd': PrintDecimal (Arg);
     	'%':putc('%');
      	else
      	begin
        	Format := Format+1;
        	Continue;
        end;
      end;
      Format := Format+1;
      ArgNo :=1;
      Continue;
    end;
    if Format^ = '\' then
    begin
    	Format := Format+1;
     	if Format^ = #0 then
      	Exit ;
      case Format^ of
       	'c': begin
        			 CleanConsole;
           		 Format := Format+1;
            end;
       	'n': begin
           		 flushp;
           		 Format := Format+1;
							 x := 0;
            end;
       	'\': begin
           		putc('\');
           		Format := Format+1;
            end;
       	'v': begin
           		I := 1;
              while I < 10 do
              begin
              	putc(' ');
                Inc(I);
              end;
              Format := Format+1;
           	end;
				else
       	begin
       		putc('\');
        	putc(Format^);
      	end;
      end;
      Continue;
    end;
    // Terminal Color indicator
    if Format^ = '/' then
    begin
     Format := Format+1;
     If Format^=#0 then
      exit;
     case Format^ of
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
     Format := Format+1;
     continue;
    end;
    putc(Format^);
    Format := Format+1;
  end;
end;

//
// WriteConsole : 
// Print to screen using format
//
procedure WriteConsole(const Format: string; const Args: array of PtrUInt);
var
  ArgNo: LongInt;
  I, J: LongInt;
  Value: QWORD;
  Values: pchar;
begin
  ArgNo := 0 ;
  J := 1;
  while J <= Length(Format) do
  begin
    // we have an argument
    if (Format[J] = '%') and (High(Args) <> -1) and (High(Args) >= ArgNo) then
    begin
      J:= J+1;
      if J > Length(Format) then
      	Exit ;
      case Format[J] of
	      'c':
          begin
		        putc(char(args[ArgNo]));
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
            putc('%');
          end;
        'p':
          begin
            Values := pointer(args[ArgNo]);
            while Values^ <> #0 do
            begin
              putc(Values^);
              Inc(Values);
            end;
          end;
      	else
      	begin
        	J:= J+1;
        	Continue;
        end;
      end;
      J:= J+1;
      ArgNo := ArgNo+1;
      Continue;
    end;
    if Format[J] = '\' then
    begin
    	J:= J+1;
     	if J > Length(Format) then
      	Exit ;
      case Format[J] of
       	'c': begin
        			 CleanConsole;
           		 J:=J+1;
            end;
       	'n': begin
           		 flushp;
           		 J:= J+1;
							 x := 0;
            end;
       	'\': begin
           		putc('\');
           		J:=J+1;
            end;
       	'v':
          begin
            I := 1;
            while I < 10 do
            begin
              putc(' ');
              Inc(I);
            end;
            J:=J+1;
          end;
				else
       	begin
       		putc('\');
        	putc(Format[J]);
      	end;
      end;
      Continue;
    end;

    // Terminal Color indicator
    if Format[J] = '/' then
    begin
     j:=j+1;
     If Format[J]=#0 then
      exit;
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
     j:=j+1;
     continue;
    end;
    putc(Format[J]);
    J:= J+1;
  end;
end;



//
// KeybHandler :
// Handler the irq of keyboard
//
procedure KeyHandler;
var
  key: Byte;
  pbuff: PChar;
begin
  eoi;
  while (read_portb($64) and 1) = 1 do
  begin
    key:=read_portb($60);
    key:= 127 and key;
    // Shift and Crt key are not implement
    if key and 128 <> 0 then
      Exit;
    // Manipulation of keys
    case key of
      //Shift, Crt and CpsLockk are not implement
      29,42,58: Exit;
      14:
        begin
          //Bkspc key
          if x<>0 then
	        begin
	          x := x-1;
            putc(#0);
            x:= x-1;
	          setcursor(x,y);
	        end;
        end;
      28:
        begin
          // Enter Key
	        y := y+1;
	        if y = 25 then
	          Flushp;
	        SetCursor(x,y);
          BufferCount := BufferCount+1;
          if BufferCount > SizeOf(KeyBuffer) then
            BufferCount:=1;
          pbuff := @KeyBuffer[BufferCount];
	        pbuff^ := #13;
	        if ThreadinKey <> nil then
	          ThreadinKey.state:=tsReady;
        end;
      75,72,80,77: Continue;
      else
      begin
        // Printing the key to the screen
        BufferCount := BufferCount+1;
        if BufferCount>sizeof(KeyBuffer) then
          BufferCount:=1;
        pbuff := @KeyBuffer[BufferCount];
	      pbuff^ := Char_Code[key];
	      putc(pbuff^);
	      if ThreadinKey <> nil then
	        ThreadinKey.state:=tsReady;
      end;
    end;
  end;
end;


procedure IrqKeyb;[nostackframe];assembler;
asm
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
 push r13
 push r14
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
 pop r14
 pop r13
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



//
// ReadConsole :
// Read a Char from Console
//
procedure ReadConsole(var ch: Char);
begin
ThreadInkey:=GetCurrentThread;
If BufferCount=LastChar then 
begin
 ThreadInKey.state:=tsIOPending;
 ThreadSwitch;
end;
LastChar := LastChar+1;
If LastChar>sizeof(KeyBuffer) then 
 LastChar:=sizeof(KeyBuffer);
ch:=KeyBuffer[LastChar];
ThreadinKey:=nil;
end;

//
// ReadlnConsole :
// Read the console until enter key
procedure ReadlnConsole(Format: PChar);
var ch: Char;
begin
while (true) do
begin
 ReadConsole(ch);
 if ch=#13 then
 begin
  Format^:=#0;
  exit;
 end;
 Format^ := ch;
 Format:=Format+1;
end;
end;

procedure EnabledConsole;
begin
irq_on(1);
end;

procedure DisabledConsole;
begin
irq_off(1);
end;

//
// ConsoleInit :
// Initialization of Console
//
procedure ConsoleInit;
begin
BufferCount:=1;
ThreadInKey:=nil;
LastChar:=1;
CaptureInt(33,@IrqKeyb);
end;

end.

