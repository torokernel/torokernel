//
// Debug.pas :
//
// Print debug procedures for debugging process .
// This procedures are similar to PrintK procedures
// DebugPrint() procedure requires lock only in this case.
//
// Changes :
//
// 18/12/2016 Adding protection to WriteDebug()
// 08/12/2016 Removing spin-locks to prevent deadlocks
// 06/05/2009 Supports QWORDS parameters.
// 23/09/2006 First version.
//
// Copyright (c) 2003-2016 Matias Vara <matiasevara@gmail.com>
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
procedure WriteDebug (const Format: AnsiString; const Args: array of PtrUInt);

implementation

uses Console, Process;

var
	LockDebug: UInt64 = 3;

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


procedure WriteSerial(const Format: AnsiString; const Args: array of PtrUInt);
var
  ArgNo: LongInt;
  I, J: LongInt;
  Value: QWORD;
  Values: PXChar;
  tmp: TNow;
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
		        SendChar(XChar(args[ArgNo]));
			    end;
        'h':
          begin
            Value := args[ArgNo];
          	DebugPrintHexa(Value);
          end;
     	  'd':
          begin
            Value := args[ArgNo];
          	DebugPrintDecimal (Value);
          end;
     	  '%':
          begin
            SendChar('%');
          end;
        'p':
          begin
            Values := pointer(args[ArgNo]);
            while Values^ <> #0 do
            begin
              SendChar(Values^);
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
        	     //CleanConsole;
           		 J:=J+1;
            end;
       	'n': begin
           		SendChar(XChar(13));
       			SendChar(XChar(10));
				J:=J+1;
            end;
       	'\': begin
           		SendChar('\');
           		J:=J+1;
            end;
       	'v':
          begin
            I := 1;
            while I < 10 do
            begin
              SendChar(' ');
              Inc(I);
            end;
            J:=J+1;
          end;
        't': begin
               Now(@tmp);
			   if (tmp.Day < 10) then DebugPrintDecimal  (0);
               DebugPrintDecimal (tmp.Day);
               SendChar('/');
			   if (tmp.Month < 10) then DebugPrintDecimal  (0);
               DebugPrintDecimal (tmp.Month);
               SendChar('/');
               DebugPrintDecimal (tmp.Year);
               SendChar('-');
			   if (tmp.Hour < 10) then DebugPrintDecimal  (0);
               DebugPrintDecimal(tmp.Hour);
               SendChar(':');
			   if (tmp.Min < 10) then DebugPrintDecimal  (0);
               DebugPrintDecimal(tmp.Min);
               SendChar(':');
			   if (tmp.Sec < 10) then DebugPrintDecimal  (0);
               DebugPrintDecimal (tmp.Sec);
               J:=J+1;
             end;
				else
       	begin
       		SendChar('\');
        	SendChar(Format[J]);
      	end;
      end;
      Continue;
    end;

    SendChar(Format[J]);
    Inc(J);
  end;
end;

// Write debug information through the serial console
procedure WriteDebug (const Format: AnsiString; const Args: array of PtrUInt);
var
  CPUI: LongInt;
  Thread: PThread;
begin
  BeginCriticalSection (LockDebug);
  CPUI := GetApicID;
  Thread := Cpu[CPUI].CurrentThread;
  WriteSerial('\t CPU%d Thread#%d ',[CPUI, Int64(Thread)]);
  WriteSerial (Format, Args);
  EndCriticalSection(LockDebug);
end;



// initialize the debuging
procedure DebugInit;
begin
  // speed and more registers of serial port
  write_portb ($83, BASE_COM_PORT+3);
  write_portb (0, BASE_COM_PORT+1);
  write_portb (1, BASE_COM_PORT);
  write_portb (3, BASE_COM_PORT+3);
  WriteConsole ('Toro on /Vdebug mode/n using /VCOM1/n\n',[]);
  WriteDebug('Initialization of debuging console.\n',[]);
  //DebugTrace('Initialization of debugging',0,0,0);
  {$IFDEF DCC} System.DebugTraceProc := @DebugTrace; {$ENDIF}
end;

end.

