//
// Console.pas
//
// This unit contains the functions that handle the console.
//
// Copyright (c) 2003-2020 Matias Vara <matiasevara@gmail.com>
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

unit Gdbstub;


interface

{$I Toro.inc}

uses
  Arch, Console, Memory, VirtIO;

procedure GdbstubInit;

implementation

type
  PDbgState = ^TDbgState;

  TDbgState = record 
    signum: LongInt;
    reg: array[0..30] of LongInt;
end;

function DbgSerialGetC: XChar;
var
  R: XChar;
begin
  ReadFromSerial(r);
  Result := R;
end;

function DbgSerialPutC(C: XChar): XChar;
begin
  PutCtoSerial(C);
  Result := C;
end;

function DbgWrite(C: PChar; Len: LongInt): LongInt;
begin
  while Len > 0 do
  begin
    DbgSerialPutC(C^);
    Inc(C);
    Dec(Len);
  end;
  Result := 0;
end;

// TODO: falta cuando falla de leer todo
function DbgRead(C: Pchar; BufLen: LongInt; Len: Longint): LongInt;
begin
  Result := 0;
  if BufLen < Len then
    Exit;
  while Len > 0 do
  begin
    C^ := DbgSerialGetC;
    Inc(C);
    Dec(Len);
  end; 
end;

function DbgChecksum(buf: PChar; len: LongInt): Byte;
var
  csum: Byte;
begin
  csum := 0;
  while len > 0 do
  begin
    Inc(csum, Byte(buf^));
    Inc(buf);
    Dec(len);
  end;
  Result := csum;
end;

function DbgGetDigit(val: LongInt): Char;
begin
  if (val >= 0) and (val <= $f) then
    Result := HEX_CHAR[val]
  else
    Result := Char(-1);
end;

function DbgEncHex(buff: PChar; buf_len: LongInt; data: PChar; data_len: LongInt): LongInt;
var
  pos: LongInt;
begin
  Result := -1;

  if buf_len < data_len * 2 Then
    Exit;
 
  for pos := 0 to data_len - 1 do
  begin
    buff^ := DbgGetDigit((Byte(data[pos]) shr 4) and $f);
    Inc(buff);
    buff^ := DbgGetDigit(Byte(data[pos]) and $f);
    Inc(buff);
  end;
  Result := data_len *2;
end;

function DbgRecvAck: LongInt;
var
  response: Char;
begin
  response := DbgSerialGetC;
  if response = '+' then
  begin
    Result := 0;
  end else if response = '-' then
  begin
    Result := 1;
  end else
  begin
    Result := -1;
  end;
end;

function DbgSendPacket(PktData: PChar; PktLen: Longint): LongInt;
var
  buf: array[0..2] of Char;
  csum: Char;
begin
  
  // send packet start
  DbgSerialPutC('$');
  
  // send packet
  DbgWrite(PktData, Pktlen);
  
  // send checksum
  buf[0] := '#';
  csum := Char(DbgChecksum(PktData, PktLen));

  DbgEncHex(Pointer(@buf)+1, sizeof(buf)-1, @csum, 1);
  DbgWrite(buf, sizeof(buf));

  Result := DbgRecvAck;
end;

function DbgSendSignalPacket(buf: PChar; buf_len: LongInt; signal: Char): LongInt;
var
  size: LongInt;
  status: LongInt;
begin
  Result := -1;
  if buf_len < 4 Then
    Exit;
  buf[0] := 'S';
  status := DbgEncHex(@buf[1], buf_len-1, @signal, 1);
  if status = -1 Then
    Exit;
  size := 1 + status;
  Result := DbgSendPacket(buf, size);
end;

procedure DbgSendOKPacket;
begin
  DbgSendPacket('OK', 2);
end;

function DbgGetVal (digit: Byte; base: LongInt): Byte;
var
  value: Byte;
begin
  if (digit >= Byte('0')) and (digit <= Byte('9')) then
    value := digit - Byte('0')
  else if (digit >= Byte('a')) and (digit <= Byte('f')) then
    value := digit - Byte('a') + $a
  else if (digit >= Byte('A')) and (digit <= Byte('F')) then
    value := digit - Byte('A') + $a;
  Result := value;
end;

function DbgDecHex(buf: PChar; buf_len: LongInt; data:PChar; data_len: LongInt): LongInt;
var
  pos: LongInt;
  tmp: Byte;
begin
  if buf_len <> data_len*2 then
    Exit;
  for pos := 0 to data_len - 1 do
  begin
    tmp := DbgGetVal(Byte(buf^), 16);
    Inc(buf);
    data[pos] := Char(tmp shl 4);
    tmp := DbgGetVal(Byte(buf^), 16);
    Inc(buf);                  
    data[pos] := Char(Byte(data[pos]) or tmp);
  end;
  Result := 0
end;

procedure DbgRecvPacket(PktBuf: PChar; PktBufLen: LongInt; out PktLen: LongInt);
var
  data: Char;
  expected_csum, actual_csum: Byte;
  buf: array[0..1] of Char;
begin
  actual_csum := 0;
  
  while true do
  begin
    data := DbgSerialGetC;
    if data = '$' then
      break;
  end;
                                    
  PktLen := 0;
  
  while true do
  begin
    data := DbgSerialGetC;
    if data = '#' then
      break
    else 
    begin
      PktBuf[PktLen] := data;
      Inc(PktLen); 
    end;
  end;  
    
  DbgRead(buf, sizeof(buf), 2);
  DbgDecHex(buf, 2, @expected_csum, 1);
  
  actual_csum := DbgChecksum(PktBuf, PktLen);
  
  if actual_csum <> expected_csum then
  begin
    DbgSerialPutC('-');
    Exit;
  end;

  DbgSerialPutC('+');
end;

// the - in features is to not send the registers
// maybe is better to reduce the number of features
const
  QSupported : PChar = 'PacketSize=1000'; //;qXfer:features:read-;vContSupported+;multiprocess-';
  Empty : Pchar = '';
  OK : PChar = 'OK';
  Signal05 : PChar = 'S05';//thread:p01.01';

function Jaja(C: PChar) : LongInt;
var r: LongInt;
begin
  r := 0;
  while C^ <> #0 do
  begin
    Inc(C);
    Inc(r);
  end;
  Result := r;
end;

function strcomp(P1, P2: PChar): Boolean;
begin
  Result := False;
  while (P1^ = P2^) and (P2^ <> #0) do
  begin
    Inc(P1);
    Inc(P2);
  end;
  if P2^ = #0 then
    Result := True;
end;

const
  NB_REG = 16;

var
  dgb_regs: array[0..15] of QWORD;
  breaks: array[0..4] of QWord;
  breaksData: array[0..4] of Byte;
  count : Byte = 0 ;

procedure DbgHandler (Signal: Boolean);
var
  buf: array[0..255] of Char;
  l: array[0..255] of Char;
  Len, i, Size: LongInt;
  reg: QWORD;
  g: ^Char;
  addr: ^DWORD;
begin
  if Signal then
    DbgSendSignalPacket(@buf, sizeof(buf), Char(5)); 
  while true do
  begin
    DbgRecvPacket(@buf, sizeof(buf), Len);
    case buf[0] of
      'p':begin
            reg := HexStrtoQWord(@buf[1], @buf[Len]);
            // TODO: fix this
            if reg > 15 then reg := 15;
            DbgEncHex(@buf, sizeof(buf), @dgb_regs[reg], 8);
            DbgSendPacket(@buf, 8 * 2);
          end;
      'm':begin
            i := 1;
            while buf[i] <> ',' do
              Inc(i);
            reg := HexStrtoQWord(@buf[1], @buf[i]);
            Inc (i);
            Size := HexStrtoQWord(@buf[i], @buf[Len]);
            g := Pointer(reg);
            for i:= 0 to size - 1 do
            begin
              l[i] := g^;
              Inc(g);
            end;  
            DbgEncHex(@buf, sizeof(buf), @l, Size);
            DbgSendPacket(@buf, Size * 2);
          end;
      'g': begin
             DbgEncHex(@buf, sizeof(buf), @dgb_regs, sizeof(dgb_regs));
             DbgSendPacket(@buf, sizeof(dgb_regs) * 2);
           end;
      'q': begin
             if strcomp(@buf[1], 'Supported') then
             begin
               DbgSendPacket(QSupported, Jaja(QSupported));
             end
             else if strcomp(@buf[1], 'fThreadInfo') then
             begin
               DbgSendPacket('l', 1);
             end
             else if buf[1] = 'C' then
             begin
               DbgSendPacket(Empty, Jaja(Empty));
             end
             else if strcomp(@buf[1], 'Attached') then
             begin
               DbgSendPacket('1', 1);
             end
             else if strcomp(@buf[1], 'TStatus') then
             begin
                DbgSendPacket(Empty, Jaja(Empty));
             end
             else if strcomp(@buf[1], 'Symbol') then
             begin
               DbgSendPacket(OK, Jaja(OK)); 
             end;
             // TODO: handle the case that we do not know the command
           end;
      'z': begin
             i := 3;
             while buf[i] <> ',' do
               Inc(i);
             addr := Pointer(HexStrtoQWord(@buf[3], @buf[i]));
             for i := 0 to 4 do
             begin
               if breaks[i] = QWORD(addr) then
                 break;
             end;
             addr^ := (addr^ and $ffffff00) or breaksData[i];
             DbgSendPacket(OK, Jaja(OK)); 
          end;
      'Z': begin
             i := 3;
             while buf[i] <> ',' do
               Inc(i);
             addr := Pointer(HexStrtoQWord(@buf[3], @buf[i]));
             for i := 0 to 4 do
             begin
               if breaks[i] = QWORD(addr) then
                 break;
             end;
             if breaks[i] <> QWORD(addr) then
             begin
               i := count ;
               inc(count) ;
               breaks[i] := QWORD(addr);
             end;
             breaksData[i] := Byte(addr^ and $ffffff00);
             addr^ := (addr^ and $ffffff00) or $cc;
             DbgSendPacket(OK, Jaja(OK));
           end;
      'v': begin
           if strcomp(@buf[1], 'MustReplyEmpty') then
           begin
             DbgSendPacket(Empty, Jaja(Empty));   
           end else if strcomp(@buf[1], 'Cont') then
           begin
             DbgSendPacket(Empty, Jaja(Empty));
           end;
          end;
      'H': begin
             if strcomp(@buf[1],'g0') then
             begin
               DbgSendPacket(OK, Jaja(OK)); 
             end else if buf[1] = 'c' then
             begin
               DbgSendPacket(OK, Jaja(OK));
             end;
           end;
      '?': begin
             DbgSendPacket(Signal05, Jaja(Signal05));
           end;
      'c':begin
            break
          end;
    end;
  end;
end;

procedure Int3Handler;
begin
  DbgHandler(true);
end;

procedure ExceptINT3;{$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
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
  // save state registers
  mov dgb_regs[0], rax
  mov dgb_regs[1], rbx
  mov dgb_regs[2], rcx
  mov dgb_regs[3], rdx
  mov dgb_regs[4], rsi
  mov dgb_regs[5], rdi
  mov dgb_regs[6], rbp
  mov dgb_regs[7], rsp
  mov dgb_regs[8], r8
  mov dgb_regs[9], r9
  mov dgb_regs[10], r10
  mov dgb_regs[11], r11
  mov dgb_regs[12], r12
  mov dgb_regs[13], r13
  mov dgb_regs[14], r14
  mov dgb_regs[15], r15
  mov r15 , rsp
  mov rbp , r15
  sub r15 , 32
  mov  rsp , r15
  xor rcx , rcx
  Call Int3Handler
  mov rsp , rbp
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

procedure GdbstubInit;
var
  buf: array[0..255] of Char;
  Len: LongInt;
  // 16 registers of 64 bits
  regs: array[0..NB_REG-1] of QWord;
  nbuf: array[0..((NB_REG * 8 * 2)-1)] of Char;
  addr: ^DWORD;
begin
  // disable console
  HeadLess := true;
  CaptureInt(EXC_INT3, @ExceptINT3); 

  while true do
  begin
    if DbgSerialGetC = '+' then
      break;
  end;
 
  DbgHandler(false);

  {
  // qstatus
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket(Empty, Jaja(Empty));

  //Thread Info
  // l
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket('l', 1);

  // Hc-1
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket(OK, Jaja(OK));

  // qC
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket(Empty, Jaja(Empty));

  // qAttached
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket('1', 1);
  {
  // qOffset
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket(Empty, Jaja(Empty));

  // send registers
  // if you negociate QStartNoAckMode+ you do not require to ack each packet
  DbgRecvPacket(@buf, sizeof(buf), Len);

  DbgEncHex(@nbuf, sizeof(nbuf), @regs, sizeof(regs));
  DbgSendPacket(@nbuf, sizeof(nbuf));

  // este es el 10
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgEncHex(@nbuf, sizeof(nbuf), @regs[0], sizeof(QWORD));
  DbgSendPacket(@nbuf, 8 * 2);

  // ThreadInfo
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket('l', 1);

  // m0,1
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgEncHex(@nbuf, sizeof(nbuf), @regs[0], 1);
  DbgSendPacket(@nbuf, 2);
  
  // m0,1
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgEncHex(@nbuf, sizeof(nbuf), @regs[0], 1);
  DbgSendPacket(@nbuf, 2);

  // m0,9
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgEncHex(@nbuf, sizeof(nbuf), @regs[0], 9);
  DbgSendPacket(@nbuf, 9 * 2); 

  // $qSymbol
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket(OK, Jaja(OK));  
    
  // here the initialization has finished
  // here we need to loop by reading commands until user does continue
  // then we break and we continue kernel execution
  // 
  // start the breakpoint 
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgEncHex(@nbuf, sizeof(nbuf), @regs[0], 40);
  DbgSendPacket(@nbuf, 40 * 2);

  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgEncHex(@nbuf, sizeof(nbuf), @regs[0], 18);
  DbgSendPacket(@nbuf, 18 * 2);

  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgEncHex(@nbuf, sizeof(nbuf), @regs[0], 6);
  DbgSendPacket(@nbuf, 6 * 2);
  
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgEncHex(@nbuf, sizeof(nbuf), @regs[0], 1);
  DbgSendPacket(@nbuf, 1 * 2);

  // this contain the breakpoint
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket(OK, Jaja(OK));
  
  //$Z0,42abc0,1 
  addr := Pointer(HexStrtoQWord(@buf[3], @buf[9]));
  breaks := byte(addr^ and $ffffff00);
  addr^ := (addr^ and $ffffff00) or $cc;
   
  // vCont?
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket(Empty, Jaja(Empty));

  // Hc-0
  DbgRecvPacket(@buf, sizeof(buf), Len);
  DbgSendPacket(OK, Jaja(OK));

  // c command
  DbgRecvPacket(@buf, sizeof(buf), Len);}
end;

end.
