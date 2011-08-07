//
// Debug.pas :
//
// Print debug procedures for debugging process .
// This procedures are similar to PrintK procedures
// DebugPrint() procedure requires lock only in this case.
//
// Changes :
//
// 06/05/2009 Supports  QWORDS parameters.
// 23/09/2006 First version.
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

unit Debug;

{$I Toro.inc}

interface

uses Arch;

procedure DebugInit;
procedure DebugPrint(Format: PXChar; const QArg: PtrUInt; const Arg1, Arg2: DWORD);
procedure DebugTrace(Format: PXChar; const QArg: PtrUInt; const Arg1, Arg2: DWORD);

implementation

uses Console, Process;

var
	LockDebug: UInt64;

// base of serial port of COM1
const
  BASE_COM_PORT = $3f8;

procedure WaitForCompletion;
var
  lsr: Byte;
begin
  repeat
    lsr := read_portb(BASE_COM_PORT+5);
  until (lsr and $20) = $20;
end;

procedure SendChar(C: XChar);
begin
  write_portb(Byte(C), BASE_COM_PORT);
  WaitForCompletion;
end;

procedure DebugPrintDecimal(Value: PtrUInt);
var
  I, Len: Byte;
  S: string[64];
begin
  Len := 0;
  I := 10;
  if Value = 0 then
  begin
    SendChar('0');
  end else
  begin
    while Value <> 0 do
    begin
      S[I] := XChar((Value mod 10) + $30);
      Value := Value div 10;
      Dec(I);
      Inc(Len);
    end;
    if (Len <> 10) then
    begin
      S[0] := XChar(Len);
      for I := 1 to Len do
      begin
        S[I] := S[11-Len];
        Dec(Len);
      end;
    end else
    begin
      S[0] := XChar(10);
    end;
    for I := 1 to ord(S[0]) do
      SendChar(S[I]);
  end;
end;

procedure DebugPrintHexa(const Value: PtrUInt);
var
  I: Byte;
begin
  SendChar('0');
  SendChar('x');
  for I := SizeOf(PtrUInt)*2-1 downto 0 do
    SendChar(HEX_CHAR[Value shr (I*4) and $F]);
end;

procedure DebugPrintString(const S: shortstring);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    SendChar(S[I]);
end;

// No locking. Locking is performed by caller function (DebugTrace or DebugPrint)
procedure DebugFormat(Format: PXChar; const QArg: PtrUInt; Arg1, Arg2: UInt32);
var
  ArgNo: Integer;
  DecimalValue: PtrUInt;
  S: ShortString;
begin
  ArgNo := 0 ;
  while Format^ <> #0 do
  begin
    if (Format^ = '%') and (Argno <> 2) then
    begin
      Format := Format+1;
      if Format^ = #0 then
        Exit;
      if ArgNo = 0 then
        DecimalValue := Arg1
      else
        DecimalValue := Arg2;
      case Format^ of
        'h': begin
               DebugPrintHexa(QArg);
             end;
     	'd': begin
               DebugPrintDecimal(DecimalValue);
               Inc(ArgNo);
             end;
     	'q': begin
               Str(QArg, S);
      	       DebugPrintString(S);
             end;
     	'%': SendChar('%');
        else
        begin
      	  Format := Format+1;
      	  Continue;
      	end;
      end;
      Format := Format+1;
      Continue;
    end;
    if Format^ = '\' then
    begin
      Format := Format+1;
      if Format^ = #0 then
      	Exit;
      case Format^ of
     		'n': begin
         			SendChar(XChar(13));
       				SendChar(XChar(10));
         			Format := Format+1;
         		end;
     		'\': begin
         			SendChar('\');
         			Format := Format+1;
         		end;
				else
       	begin
       		SendChar('\');
       		SendChar(Format^);
       	end;
      end;
    	Continue;
  	end;
  	SendChar(Format^);
  	Format := Format+1;
	end;
end;

// Similar to printk but the Char are send using serial port for debug procedures
// Can format only 1 qword argument
procedure DebugPrint(Format: PXChar; const QArg: PtrUInt; const Arg1, Arg2: DWORD);
begin
  SpinLock(3, 4, LockDebug);
  DebugFormat(Format, QArg, Arg1, Arg2);
  LockDebug := 3;
end;

procedure DebugTrace(Format: PXChar; const QArg: PtrUInt; const Arg1, Arg2: DWORD);
{$IFDEF DebugThreadInfo}
var
  CPUI: LongInt;
  CurrentTime: Int64;
  Thread: PThread;
{$ENDIF}
begin
  SpinLock(3, 4, LockDebug);
{$IFDEF DebugThreadInfo}
  CPUI := GetApicID;
  Thread := Cpu[CPUI].CurrentThread;
  // this instruction corrupts the serial port output, on real computer it doesn't happen, only when running on emulator
  CurrentTime := read_rdtsc;
  DebugFormat('%q CPU%d #%d ', CurrentTime, CPUI, PtrUInt(Thread));
{$ENDIF}
  DebugFormat(Format, QArg, Arg1,Arg2);
  SendChar(XChar(13));
  SendChar(XChar(10));
  LockDebug := 3;
end;

// initialize all structures for work of debug .
procedure DebugInit;
begin
  // speed and more registers of serial port
  write_portb($83, BASE_COM_PORT+3);
  write_portb(0, BASE_COM_PORT+1);
  write_portb(1, BASE_COM_PORT);
  write_portb(3, BASE_COM_PORT+3);
  LockDebug := 3;
  printk_('Mode debug: Enabled, using ... COM1\n',0);
  DebugTrace('Initialization of debugging At Time %q:%d:%d', Int64(StartTime.Hour), StartTime.Min, StartTime.Sec);
  {$IFDEF DCC} System.DebugTraceProc := @DebugTrace; {$ENDIF}
end;

end.

