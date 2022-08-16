//
// GDBstub.pas
//
// This unit contains a gdbstub to enable debugging Toro by using GDB
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

unit Gdbstub;


interface

{$I Toro.inc}

uses
  Arch, Console, Memory, VirtIO, Network, VirtIOConsole;

implementation
{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushfq;cli;end;}
{$DEFINE RestoreInt := asm popfq;end;}
{$DEFINE Int3 := asm db $cc end;}

const
  QSupported : PChar = 'PacketSize=1000';
  Empty : Pchar = '';
  OK : PChar = 'OK';
  Signal05 : PChar = 'S05';
  NB_GENERAL_REG = 16;
  NB_EXTRA_REG = 2;
  MAX_NR_BREAKPOINTS = 50;

function DbgSerialGetC: XChar;
var
  r: XChar;
begin
  virtIOConsoleRead(@r, 1);
  Result := r;
end;

function DbgSerialPutC(C: XChar): XChar;
var
  t: TPacket;
begin
  t.data := @C;
  t.size := 1;
  virtIOConsoleSend(@t);
  Result := C;
end;

function DbgWrite(C: PChar; Len: LongInt): LongInt;
var
  t: TPacket;
Begin
  if Len > 0 then
  begin
    t.data := C;
    t.size := Len;
    virtIOConsoleSend(@t);
  end;
  Result := 0;
end;

function DbgRead(C: Pchar; BufLen: LongInt; Len: Longint): LongInt;
begin
  Result := 0;
  if BufLen < Len then
    Exit;
  Result := Len;
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
    if PktLen > PktBufLen then
      WriteConsoleF('Gdbstub: buffer has been overwritten\n',[]);
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

function strlen(C: PChar) : LongInt;
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

var
  dgb_regs: array[0..NB_GENERAL_REG + NB_EXTRA_REG -1] of QWORD;
  breaks: array[0..MAX_NR_BREAKPOINTS-1] of QWord;
  breaksData: array[0..MAX_NR_BREAKPOINTS-1] of Byte;
  count : Byte = 0 ;
  // buff should be per core
  buf: array[0..300] of Char;

procedure DbgHandler (Signal: Boolean; Nr: LongInt);
var
  l: array[0..100] of Char;
  Len, i, Size: LongInt;
  reg: QWORD;
  g: ^Char;
  addr: ^Byte;
  p: QWORD;
begin
  if Signal then
    DbgSendSignalPacket(@buf, sizeof(buf), Char(5));
  while true do
  begin
    DbgRecvPacket(@buf, sizeof(buf), Len);
    case buf[0] of
      'P': begin
             reg := Byte(HexStrtoQWord(@buf[1], @buf[Len]));
             i := 1;
             while buf[i] <> '=' do
               Inc(i);
             reg := Byte(HexStrtoQWord(@buf[1], @buf[i]));
             DbgDecHex(@buf[i+1], Len - i - 1, Pchar(@p), sizeof(QWORD));
             if reg < 16 then
               dgb_regs[reg] := p;
             DbgSendPacket(OK, strlen(OK));
           end;
      'p':begin
            reg := Byte(HexStrtoQWord(@buf[1], @buf[Len]));
            if reg > NB_GENERAL_REG + NB_EXTRA_REG -1 then reg := NB_GENERAL_REG + NB_EXTRA_REG -1;
            DbgEncHex(@buf[0], sizeof(buf), Pchar(@dgb_regs[reg]), sizeof(QWORD));
            DbgSendPacket(@buf[0], 8 * 2);
          end;
      'm':begin
            i := 1;
            while buf[i] <> ',' do
              Inc(i);
            reg := HexStrtoQWord(@buf[1], @buf[i]);
            Inc (i);
            Size := HexStrtoQWord(@buf[i], @buf[Len]);
            if Size > sizeof(l) then
              Size := sizeof(l);
            g := Pointer(reg);
            for i:= 0 to Size - 1 do
            begin
              if g > Pointer(MAX_ADDR_MEM) then
              begin
                l[i] := Char(0);
                break;
              end;
              l[i] := g^;
              Inc(g);
            end;
            DbgEncHex(@buf, sizeof(buf), @l, Size);
            DbgSendPacket(@buf, Size * 2);
          end;
      'g': begin
             // these are only general registers
             DbgEncHex(@buf, sizeof(buf), @dgb_regs, sizeof(dgb_regs)-NB_EXTRA_REG * sizeof(QWORD));
             DbgSendPacket(@buf, (sizeof(dgb_regs)-NB_EXTRA_REG * sizeof(QWORD)) * 2);
           end;
      'q': begin
             if strcomp(@buf[1], 'Supported') then
             begin
               DbgSendPacket(QSupported, strlen(QSupported));
             end
             else if strcomp(@buf[1], 'fThreadInfo') then
             begin
               DbgSendPacket('l', 1);
             end
             else if buf[1] = 'C' then
             begin
               DbgSendPacket(Empty, strlen(Empty));
             end
             else if strcomp(@buf[1], 'Attached') then
             begin
               DbgSendPacket('1', 1);
             end
             else if strcomp(@buf[1], 'TStatus') then
             begin
                DbgSendPacket(Empty, strlen(Empty));
             end
             else if strcomp(@buf[1], 'Symbol') then
             begin
               DbgSendPacket(OK, strlen(OK));
             end
             else if strcomp(@buf[1], 'Offsets') then
             begin
               DbgSendPacket(Empty, strlen(Empty));
             end;
             // TODO: handle the case that we do not know the command
           end;
      'z': begin
             i := 3;
             while buf[i] <> ',' do
               Inc(i);
             addr := Pointer(HexStrtoQWord(@buf[3], @buf[i]));
             for i := 0 to MAX_NR_BREAKPOINTS-1 do
             begin
               if breaks[i] = QWORD(addr) then
                 break;
             end;
             addr^ := breaksData[i];
             DbgSendPacket(OK, strlen(OK));
          end;
      'Z': begin
             i := 3;
             while buf[i] <> ',' do
               Inc(i);
             addr := Pointer(HexStrtoQWord(@buf[3], @buf[i]));
             for i := 0 to MAX_NR_BREAKPOINTS-1 do
             begin
               if breaks[i] = QWORD(addr) then
                 break;
             end;
             if breaks[i] <> QWORD(addr) then
             begin
               i := count ;
               inc(count) ;
               breaks[i] := QWORD(addr);
               breaksData[i] := addr^;
             end;
             addr^ := $cc;
             DbgSendPacket(OK, strlen(OK));
           end;
      'v': begin
           if strcomp(@buf[1], 'MustReplyEmpty') then
           begin
             DbgSendPacket(Empty, strlen(Empty));
           end else if strcomp(@buf[1], 'Cont') then
           begin
             DbgSendPacket(Empty, strlen(Empty));
           end;
          end;
      'H': begin
             if strcomp(@buf[1],'g0') then
             begin
               DbgSendPacket(OK, strlen(OK));
             end else if buf[1] = 'c' then
             begin
               DbgSendPacket(OK, strlen(OK));
             end;
           end;
      '?': begin
             DbgSendPacket(Signal05, strlen(Signal05));
           end;
      'c': begin
             dgb_regs[17] := dgb_regs[17] and (not(1 shl 8));
             break;
           end;
      's': begin
             dgb_regs[17] := dgb_regs[17] or (1 shl 8);
             if Nr = 3 then
               Dec(dgb_regs[16]);
             break;
           end;
      'D': begin
             dgb_regs[17] := dgb_regs[17] and (not(1 shl 8));
             DbgSendPacket(OK, strlen(OK));
             break;
           end;
    end;
  end;
end;

procedure Int3Handler;
begin
  DbgHandler(true, 3);
end;

procedure Int1Handler;
begin
  DbgHandler(true, 1);
end;

procedure ExceptINT1;{$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
asm
  {$IFDEF DCC} .noframe {$ENDIF}
  mov [dgb_regs], rax
  mov [dgb_regs+8], rbx
  mov [dgb_regs+8*2], rcx
  mov [dgb_regs+8*3], rdx
  mov [dgb_regs+8*4], rsi
  mov [dgb_regs+8*5], rdi
  mov [dgb_regs+8*6], rbp
  mov [dgb_regs+8*7], rsp
  mov [dgb_regs+8*8], r8
  mov [dgb_regs+8*9], r9
  mov [dgb_regs+8*10], r10
  mov [dgb_regs+8*11], r11
  mov [dgb_regs+8*12], r12
  mov [dgb_regs+8*13], r13
  mov [dgb_regs+8*14], r14
  mov [dgb_regs+8*15], r15
  // save rflags
  mov rax, [rsp + 2 * 8]
  mov [dgb_regs+8*17], rax
  // save rip
  mov rbx, rsp
  mov rax, [rbx]
  mov [dgb_regs+8*16], rax
  // protect stack
  mov r15 , rsp
  mov rbp , r15
  sub r15 , 32
  mov  rsp , r15
  xor rcx , rcx
  Call Int1Handler
  mov rsp , rbp
  // set rip
  pop rax
  mov rax, [dgb_regs+8*16]
  push rax
  // set rflags
  mov rax, qword [dgb_regs+8*17]
  mov [rsp + 2 * 8], rax
  mov rax, [dgb_regs]
  mov rbx, [dgb_regs+8]
  mov rcx, [dgb_regs+8*2]
  mov rdx, [dgb_regs+8*3]
  mov rsi, [dgb_regs+8*4]
  mov rdi, [dgb_regs+8*5]
  mov rbp, [dgb_regs+8*6]
  mov r8,  [dgb_regs+8*8]
  mov r9, [dgb_regs+8*9]
  mov r10, [dgb_regs+8*10]
  mov r11, [dgb_regs+8*11]
  mov r12, [dgb_regs+8*12]
  mov r13, [dgb_regs+8*13]
  mov r14, [dgb_regs+8*14]
  mov r15, [dgb_regs+8*15]
  iretq
end;


procedure ExceptINT3;{$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
asm
  {$IFDEF DCC} .noframe {$ENDIF}
  mov [dgb_regs], rax
  mov [dgb_regs+8], rbx
  mov [dgb_regs+8*2], rcx
  mov [dgb_regs+8*3], rdx
  mov [dgb_regs+8*4], rsi
  mov [dgb_regs+8*5], rdi
  mov [dgb_regs+8*6], rbp
  mov [dgb_regs+8*7], rsp
  mov [dgb_regs+8*8], r8
  mov [dgb_regs+8*9], r9
  mov [dgb_regs+8*10], r10
  mov [dgb_regs+8*11], r11
  mov [dgb_regs+8*12], r12
  mov [dgb_regs+8*13], r13
  mov [dgb_regs+8*14], r14
  mov [dgb_regs+8*15], r15
  // save rflags
  mov rax, [rsp+2*8]
  mov [dgb_regs+8*17], rax
  // save rip
  mov rbx, rsp
  mov rax, [rbx]
  mov [dgb_regs+8*16], rax
  // protect the stack
  mov r15 , rsp
  mov rbp , r15
  sub r15 , 32
  mov  rsp , r15
  xor rcx , rcx
  Call Int3Handler
  mov rsp , rbp
  // restore rip
  pop rax
  mov rax, [dgb_regs+8*16]
  push rax
  // restore rflags
  mov rax, qword [dgb_regs+8*17]
  mov [rsp+2*8], rax
  mov rax, [dgb_regs]
  mov rbx, [dgb_regs+8]
  mov rcx, [dgb_regs+8*2]
  mov rdx, [dgb_regs+8*3]
  mov rsi, [dgb_regs+8*4]
  mov rdi, [dgb_regs+8*5]
  mov rbp, [dgb_regs+8*6]
  mov r8,  [dgb_regs+8*8]
  mov r9,  [dgb_regs+8*9]
  mov r10, [dgb_regs+8*10]
  mov r11, [dgb_regs+8*11]
  mov r12, [dgb_regs+8*12]
  mov r13, [dgb_regs+8*13]
  mov r14, [dgb_regs+8*14]
  mov r15, [dgb_regs+8*15]
  iretq
end;

procedure GdbstubInit;
var
  i: LongInt;
begin
  CaptureInt(EXC_INT3, @ExceptINT3);
  CaptureInt(EXC_INT1, @ExceptINT1);
  for i := 0 to MAX_NR_BREAKPOINTS-1 do
     breaks[i] := 0 ;
  WriteConsoleF('Gdbstub: waiting for client ... OK\n', []);
  // triger debugging
  Int3;
end;

initialization
  GdbStubInit;
end.
