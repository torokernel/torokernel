//
// ne2000.pas
//
// Driver for ne2000 Network Card.
// For the moment just detect one card.
//
// Changes:
//
// 06/03/2011: Fixed bug in the initialization.
// 27/12/2009: Bug Fixed in Initilization process.
// 24/12/2008: Bug in Read procedure. In One irq I must read all the packets in the internal buffer
//             of ne2000. It is a circular buffer.Some problems if Buffer Overflow happens .
// 24/12/2007: Bug in size of Packets was solved.
// 10/11/2007: Rewritten the ISR
// 10/07/2007: Some bugs have been fixed.
// 17/06/2007: First Version by Matias Vara.
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
// All Rights Reserved
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

unit ne2000;

interface


{$I ..\Toro.inc}
{//$DEFINE DebugNE2000}

uses Arch, Console, Debug, Filesystem, Network, Process, Memory;


implementation

type
  PNe2000 = ^TNe2000;
  TNe2000 = record
    DriverInterface: TNetworkInterface;
    irq: LongInt;
    iobase: LongInt;
    NextPacket: LongInt;
  end;

const
  // Max Size of Packet in bytes
  MAX_PACKET_SIZE = 1500;

  COMMAND = 0;
  PAGESTART = 1;
  PAGESTOP = 2;
  BOUNDARY = 3;
  TRANSMITSTATUS =4;
  TRANSMITPAGE =4;
  TRANSMITBYTECOUNT0 =5;
  NCR =5;
  TRANSMITBYTECOUNT1 =6;
  INTERRUPTSTATUS =7;
  CURRENT=7;
  REMOTESTARTADDRESS0=8;
  CRDMA0=8;
  REMOTESTARTADDRESS1=9;
  CRDMA1=9;
  REMOTEBYTECOUNT0=10;
  REMOTEBYTECOUNT1=11;
  RECEIVESTATUS=12;
  RECEIVECONFIGURATION=12;
  TRANSMITCONFIGURATION=13;
  FAE_TALLY=13;
  DATACONFIGURATION=14;
  CRC_TALLY=14;
  INTERRUPTMASK=15;
  MISS_PKT_TALLY=15;
  IOPORT=16;

  dcr= $58;
  NE_RESET=$1f;
  NE_DATA=$10;
  TRANSMITBUFFER=$40;
  PSTART=$46;
  PSTOP=$80;

  // Some Ethernet commands
  E8390_START =2;
  E8390_TRANS =4;
  E8390_RREAD =8;
  E8390_RWRITE =$10;
  E8390_NODMA=$20;
  //E8390_PAGE0=0;

var
  Ne2000Card: TNe2000; // Support currently 1 ethernet card

// The card starts to work
procedure Ne2000Start(Net: PNetworkInterface);
begin
  // initialize network driver
end;

procedure WritePort(Data: Byte; Port: Word);
begin
  NOP; NOP; NOP;
  Write_Portb(Data,Port);
  NOP; NOP; NOP;
end;

function ReadPort(Port: Word):byte;
begin
  NOP; NOP; NOP;
  Result := Read_Portb(Port);
  NOP; NOP; NOP;
end;

// The card stop to work
procedure Ne2000Stop(Net: PNetworkInterface);
begin
end;

type
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;

// Internal Job of NetworkSend
procedure DoSendPacket(Net: PNetworkInterface);
var
  Size, I: LongInt;
  Data: PByteArray;
  Packet: PPacket;
begin
  // The first packet is sent
  Packet := Net.OutgoingPackets;
  Size:= Packet.size;
  WritePort(Size and $ff, Ne2000Card.iobase+REMOTEBYTECOUNT0);
  WritePort(Size shr 8, Ne2000Card.iobase+REMOTEBYTECOUNT1);
  WritePort(0, Ne2000Card.iobase+REMOTESTARTADDRESS0);
  WritePort(TRANSMITBUFFER, Ne2000Card.iobase+REMOTESTARTADDRESS1);
  WritePort(E8390_RWRITE or E8390_START, Ne2000Card.iobase+COMMAND);
  Data := Packet.Data;
  for I := 0 to (Size-1) do
    WritePort(Data^[I], Ne2000Card.iobase+NE_DATA);
  WritePort(TRANSMITBUFFER, Ne2000Card.iobase+TRANSMITPAGE);
  WritePort(size, Ne2000Card.iobase+TRANSMITBYTECOUNT0);
  WritePort(size shr 8, Ne2000Card.iobase+TRANSMITBYTECOUNT1);
  WritePort(E8390_NODMA or E8390_TRANS or E8390_START, Ne2000Card.iobase+COMMAND);
end;

// Send a Packet
procedure Ne2000Send(net: PNetworkInterface; Packet: PPacket);
var
  PacketQueue: PPacket;
begin
  DisabledINT; // Protection from Local Access
  PacketQueue := Net.OutgoingPackets; // Queue of packets
  if PacketQueue = nil then
  begin
   net.OutgoingPackets := Packet; // Enqueue the packet
   DoSendPacket(net); // Send immediately
  end else
  begin // It is a FIFO queue
    while PacketQueue.next <> nil do
      PacketQueue := PacketQueue.Next;
    PacketQueue.Next := Packet;
  end;
  EnabledINT;
end;

// Configure the card.
procedure InitNe2000(Net: PNe2000);
var
  I: LongInt;
  Buffer: array[0..31] of Byte;
begin
  // Reset driver
  WritePort(ReadPort(Net.iobase+NE_RESET), Net.iobase+NE_RESET);
  while ReadPort(Net.iobase+INTERRUPTSTATUS) and $80 = 0 do
    NOP;
  WritePort($ff,Net.iobase+INTERRUPTSTATUS);
  WritePort($21,Net.iobase+COMMAND);
  WritePort(dcr,Net.iobase+DATACONFIGURATION);
  WritePort($20,Net.iobase+REMOTEBYTECOUNT0);
  WritePort(0,Net.iobase+REMOTEBYTECOUNT1);
  WritePort(0,Net.iobase+REMOTESTARTADDRESS0);
  WritePort(0,Net.iobase+REMOTESTARTADDRESS1);
  WritePort(E8390_RREAD or E8390_START,Net.iobase+COMMAND);
  WritePort($e,Net.iobase+RECEIVECONFIGURATION);
  WritePort(4,Net.iobase+TRANSMITCONFIGURATION);
  // Read EEPROM
  for I := 0 to 31 do
    Buffer[I]:= ReadPort(Net.iobase+IOPORT);
  WritePort($40, Net.iobase+TRANSMITPAGE);
  WritePort($46 ,Net.iobase+PAGESTART);
  WritePort($46, Net.iobase+BOUNDARY);
  WritePort($60, Net.iobase+PAGESTOP);
  // Enable IRQ
  WritePort($1f, Net.iobase+INTERRUPTMASK);
  WritePort($61, Net.iobase+COMMAND);
  // Program the Ethernet Address
  WritePort($61, Net.iobase+COMMAND);
  WritePort(Buffer[0], Net.iobase+COMMAND + $1);
  WritePort(Buffer[2], Net.iobase+COMMAND + $2);
  WritePort(Buffer[4], Net.iobase+COMMAND + $3);
  WritePort(Buffer[6], Net.iobase+COMMAND + $4);
  WritePort(Buffer[8], Net.iobase+COMMAND + $5);
  WritePort(Buffer[10], Net.iobase+COMMAND + $6);
  // Program multicast address
  WritePort($ff, Net.iobase+COMMAND + $8);
  WritePort($ff, Net.iobase+COMMAND + $9);
  WritePort($ff, Net.iobase+COMMAND + $a);
  WritePort($ff, Net.iobase+COMMAND + $b);
  WritePort($ff, Net.iobase+COMMAND + $c);
  WritePort($ff, Net.iobase+COMMAND + $d);
  WritePort($ff, Net.iobase+COMMAND + $e);
  WritePort($ff, Net.iobase+COMMAND + $f);
  // save Ethernet Number
  for I := 0 to 5 do
    Net.DriverInterface.Hardaddress[I] := Buffer[I*2];
  WritePort(dcr, Net.iobase+DATACONFIGURATION);
  Net.NextPacket := PSTART + 1;
  WritePort(Net.NextPacket, Net.iobase+CURRENT);
  // Ne2000 Start!
  WritePort($22, Net.iobase+COMMAND);
  WritePort(0, Net.iobase+TRANSMITCONFIGURATION);
  WritePort($0C, Net.iobase+RECEIVECONFIGURATION);
end;

// Read a packet from net card and enque it to Outgoing Packet list
procedure ReadPacket(Net: PNe2000);
var
  Curr: Byte;
  Data: PByteArray;
  rsr, Next, Count, Len: LongInt;
  Packet: PPacket;
begin
  // curr has the last packet in ne2000 internal buffer
  WritePort(E8390_START or E8390_NODMA or $40 ,Net.iobase+COMMAND);
  curr := ReadPort(Net.iobase+CURRENT);
  WritePort(E8390_START or E8390_NODMA ,Net.iobase+COMMAND);
  // we must read all the packet in the buffer
  while curr <> Net.NextPacket do
  begin
    WritePort(4, Net.iobase+REMOTEBYTECOUNT0);
    WritePort(0, Net.iobase+REMOTEBYTECOUNT1);
    WritePort(0, Net.iobase+REMOTESTARTADDRESS0);
    WritePort(Net.NextPacket, Net.iobase+REMOTESTARTADDRESS1);
    WritePort(E8390_RREAD or E8390_START,Net.iobase+COMMAND);
    rsr:= ReadPort(Net.iobase+NE_DATA);
    Next:= ReadPort(Net.iobase+NE_DATA);
    Len:= ReadPort(Net.iobase+NE_DATA);
    Len:= Len + ReadPort(Net.iobase+NE_DATA) shl 8;
    WritePort($40,Net.iobase+INTERRUPTSTATUS);
    if (rsr and 31 = 1) and (Next >= PSTART) and (Next <= PSTOP) and (Len <= 1532) then
    begin
      // Alloc memory for new packet
      Packet := ToroGetMem(Len+SizeOf(TPacket));
      Packet.Data := Pointer(PtrUInt(Packet) + SizeOf(TPacket));
      Packet.Size := Len;
      Data := Packet.Data;
      WritePort(Len, Net.iobase+REMOTEBYTECOUNT0);
      WritePort(Len shr 8, Net.iobase+REMOTEBYTECOUNT1);
      WritePort(4, Net.iobase+REMOTESTARTADDRESS0);
      WritePort(Net.NextPacket, Net.iobase+REMOTESTARTADDRESS1);
      WritePort(E8390_RREAD or E8390_START, Net.iobase+COMMAND);
      // read the packet
      for Count:= 0 to Len-1 do
        Data^[Count] := ReadPort(Net.iobase+NE_DATA);
      WritePort($40, Net.iobase+INTERRUPTSTATUS);
      if Next = PSTOP then
        Net.NextPacket := PSTART
      else
        Net.NextPacket := Next;
      EnqueueIncomingPacket(Packet);
    end;
    if Net.NextPacket = PSTART then
      WritePort(PSTOP-1, Net.iobase+BOUNDARY)
    else
      WritePort(Net.NextPacket-1, Net.iobase+BOUNDARY);
    // getting the position on the internal buffer
    WritePort(E8390_START or E8390_NODMA or $40 ,Net.iobase+COMMAND);
    curr := ReadPort(Net.iobase+CURRENT);
    WritePort(E8390_START or E8390_NODMA ,Net.iobase+COMMAND);
  end;
end;

// Kernel raised some error -> Resend the last packet
procedure Ne2000Reset(Net: PNetWorkInterface);
begin
  DisabledInt;
  DoSendPacket(Net);
  EnabledInt;
end;

// Ne2000 Irq Handler
procedure Ne2000Handler;
var
  Packet: PPacket;
  Status: LongInt;
begin
  Status := ReadPort(Ne2000Card.iobase + INTERRUPTSTATUS);
  if Status and 1 <> 0 then
  begin
    WritePort(Status,Ne2000Card.iobase + INTERRUPTSTATUS);
    ReadPacket(@Ne2000Card); // Transfer the packet to Packet Cache
    {$IFDEF DebugNe2000} DebugTrace('Ne2000IrqHandle: Packet readed', 0, 0, 0); {$ENDIF}
  end else if Status and $A <> 0 then
  begin
    WritePort(Status, Ne2000Card.iobase + INTERRUPTSTATUS);
    Packet := DequeueOutgoingPacket; // Inform Kernel Last packet has been sent, and fetch the next packet to send
    // We have got to send more packet ?
    if Packet <> nil then
      DoSendPacket(@Ne2000Card.DriverInterface);
    {$IFDEF DebugNe2000} DebugTrace('Ne2000IrqHandle: Packet Transmited', 0, 0, 0); {$ENDIF}
  end;
  eoi;
end;

// capture ne2000 irq and jump to ne2000Handler
// interruptions are disabled in the handler
procedure ne2000irqhandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
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
  push r13
  push r14
  // protect the stack
  mov r15 , rsp
  mov rbp , r15
  sub r15 , 32
  mov  rsp , r15
  xor rcx , rcx
  // call handler
  Call ne2000handler
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

// Look for ne2000 card in PCI bus and register it.
// Currently support for one NIC
procedure PCICardInit;
var
  Net: PNetworkInterface;
  PCIcard: PBusDevInfo;
begin
  PCIcard := PCIDevices;
  while PCIcard <> nil do
  begin
    // looking for ethernet network card
    if (PCIcard.MainClass = $02) and (PCIcard.SubClass = $00) then
    begin
      // looking for ne2000 card
      if (PCIcard.Vendor = $10ec) and (PCIcard.Device = $8029) then
      begin
      ne2000card.irq:=PCIcard.irq;
      ne2000card.iobase:=PCIcard.IO[0];
      Net := @ne2000card.Driverinterface;
      Net.Name:= 'ne2000';
      Net.MaxPacketSize:= MAX_PACKET_SIZE;
      Net.start:= @ne2000Start;
      Net.send:= @ne2000Send;
      Net.stop:= @ne2000Stop;
      Net.Reset:= @ne2000Reset;
      Net.TimeStamp := 0;
      WriteConsole('ne2000 network card: /Vdetected/n on PCI bus',[]);
      InitNe2000(@ne2000card);
      Irq_On(ne2000card.irq);
      CaptureInt(32+ne2000card.irq, @ne2000irqhandler);
      RegisterNetworkInterface(Net);
      WriteConsole(', MAC:/V%d:%d:%d:%d:%d:%d/n\n', [Net.Hardaddress[0], Net.Hardaddress[1],
      Net.Hardaddress[2], Net.Hardaddress[3], Net.Hardaddress[4], Net.Hardaddress[5]]);
      Exit; // Support only 1 NIC in this version
    end;
      end;
    PCIcard := PCIcard.Next;
  end;
end;

initialization
  PCICardInit;
  
end.
