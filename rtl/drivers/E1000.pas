//
// E1000.pas
//
// This units contains the driver for the Intel e1000 network card.
//
// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
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

unit E1000;

interface

{$I ..\Toro.inc}
{$IFDEF EnableDebug}
        //{$DEFINE DebugE1000}
{$ENDIF}


uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  FileSystem,
  Pci,
  Arch, Console, Network, Process, Memory;

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}

type
  PE1000 = ^TE1000;
  PE1000RxDesc = ^TE1000RxDesc;
  PE1000TxDesc =  ^TE1000TxDesc;
  TE1000 = record
    Driverinterface: TNetworkInterface;
    IRQ: LongInt;
    EepromDoneBit: LongInt;
    EepromAddrOff: LongInt;
    Regs: Pointer;
    RxDescCount: LongInt;
    TxDescCount: LongInt;
    RxDesc: PE1000RxDesc;
    RxBufferSize: LongInt;
    TxBufferSize: LongInt;
    RxBuffer: Pointer;
    TxBuffer: Pointer;
    TxDesc: PE1000TxDesc;
    NextPacket: LongInt;
  end;

  TE1000RxDesc = record
    Buffer: DWORD;
    Buffer_h: DWORD;
    Length: word;
    Checksum: word;
    Status: Byte;
    Errors: Byte;
    Special: word;
  end;

  TE1000TxDesc = record
    Buffer: DWORD;
    Buffer_h: DWORD;
    Length: word;
    ChecksumOff: Byte;
    Command: Byte;
    Status: Byte;
    ChecksumSt: Byte;
    Special: word;
   end;

const
   E1000_REG_STATUS = $8;
   E1000_REG_CTRL = 0;
   E1000_REG_FCAL = $28;
   E1000_REG_FCAH = $2c;
   E1000_REG_FCT = $30;
   E1000_REG_FCTTV = $170;
   E1000_REG_MTA =$5200;
   E1000_REG_CRCERRS =$4000;
   E1000_REG_EERD = $14;
   E1000_REG_RAL = $5400;
   E1000_REG_RAH = $5404;
   E1000_REG_RCTL =$100;
   E1000_REG_TCTL =$400;

   E1000_REG_CTRL_RST = 1 shl 26;
   E1000_REG_CTRL_ASDE = 1 shl 5;
   E1000_REG_CTRL_SLU = 1 shl 6;
   E1000_REG_CTRL_LRST = 1 shl 3;
   E1000_REG_CTRL_PHY_RST = LongInt(1 shl 31);
   E1000_REG_CTRL_ILOS = 1 shl 7;
   E1000_REG_CTRL_VME = 1 shl 30;

   E1000_REG_EERD_START = 1 shl 0;
   E1000_REG_EERD_DATA = $ffff shl 16;

   E1000_REG_RAH_AV = LongInt(1 shl 31);

   E1000_REG_RDBAL = $2800;
   E1000_REG_RDBAH = $2804;
   E1000_REG_RDLEN = $2808;
   E1000_REG_RCTL_EN = 1 shl 1;
   E1000_REG_RXDCTL_ENABLE = 1 shl 25;
   // 256 bytes
   E1000_REG_RCTL_BSIZE = ((1 shl 16) or (1 shl 17));
   E1000_REG_RXDCTL = $2828;
   E1000_REG_TDBAL = $3800;
   E1000_REG_TDBAH = $3804;
   E1000_REG_TDLEN = $3808;
   E1000_REG_TDH = $3810;
   E1000_REG_TDT = $3818;
   E1000_REG_RDH = $2810;
   E1000_REG_RDT = $2818;
   E1000_REG_RDTR = $2820;
   E1000_REG_TCTL_PSP = 1 shl 3;
   E1000_REG_TCTL_EN  = 1 shl 1;

   E1000_REG_IMS = $d0;
   E1000_REG_IMS_LSC =1 shl 2;
   E1000_REG_IMS_RXO = 1 shl 6;
   E1000_REG_IMS_RXT = 1 shl 7;
   E1000_REG_IMS_TXDW = 1 shl 0;
   E1000_REG_IMS_TXQE = 1 shl 1;

   E1000_REG_ICR = $c0;
   E1000_REG_ICR_LSC = 1 shl 2;

   E1000_REG_ICR_TXQE = 1 shl 1;
   E1000_REG_ICR_TXDW = 1 shl 0;

   E1000_REG_ICR_RXT = 1 shl 7;
   E1000_REG_ICR_RXO = 1 shl 6;

   E1000_RXDESC_NR = 256;
   E1000_TXDESC_NR = 256;

   E1000_IOBUF_SIZE = 2048;

   E1000_TX_CMD_EOP = 1 shl 0;
   E1000_TX_CMD_FCS = 1 shl 1;
   E1000_TX_CMD_RS = 1 shl 3;

   E1000_RX_STATUS_EOP = 1 shl 1;
   E1000_RX_STATUS_DONE = 1 shl 0;

   E1000_REG_RCTL_UPE = 1 shl 3;
   E1000_REG_RCTL_MPE = 1 shl 4;
   E1000_REG_RCTL_BAM = 1 shl 15;
   E1000_RCTL_SECRC = 1 shl 26;

// driver supports only 1 ethernet card
var
  NicE1000: TE1000;

function E1000ReadRegister(Net: PE1000; reg: LongInt): LongInt;
var
  r: ^DWORD;
begin
  r := Pointer(PtrUInt(Net.Regs)+reg);
  Result := r^;
end;

procedure E1000WriteRegister(Net: PE1000; Reg, Value: LongInt);
var
  r: ^DWORD;
begin
  r := Pointer(PtrUInt(Net.Regs)+Reg);
  r^ := Value;
end;

procedure e1000SetRegister(Net: PE1000; Reg, Value: LongInt);
var
  Data: LongInt;
begin
  Data:= E1000ReadRegister(Net, Reg);
  E1000WriteRegister(Net, Reg, Data or Value);
end;

procedure e1000UnsetRegister(Net: PE1000; Reg, Value: LongInt);
var
  Data: LongInt;
begin
  Data:= E1000ReadRegister(Net, Reg);
  E1000WriteRegister(Net,Reg, Data and not(Value));
end;

procedure E1000Reset(Net: PE1000);
begin
   E1000SetRegister(Net, E1000_REG_CTRL, E1000_REG_CTRL_RST);
   DelayMicro(1000);
end;

function EepromEerd(Net: PE1000; Reg: LongInt): Word;
var
  tmp: LongInt;
begin
  E1000WriteRegister(Net, E1000_REG_EERD,(Reg shl Net^.EepromAddrOff) or E1000_REG_EERD_START);
  tmp := E1000ReadRegister(Net, E1000_REG_EERD);
  while ((tmp and Net^.EepromDoneBit) = 0) do
  begin
    DelayMicro(1);
    tmp := E1000ReadRegister(Net, E1000_REG_EERD);
  end;
  Result := tmp shr 16;
end;

procedure e1000Start(net: PNetworkInterface);
{$IFDEF DebugE1000}
var
  CPU: byte;
begin
  CPU := GetApicid;
{$ELSE}
begin
{$ENDIF}
  IrqOn(NicE1000.IRQ);
  {$IFDEF DebugE1000} WriteDebug('e1000: starting on CPU%d\n', [CPU]); {$ENDIF}
end;

procedure e1000Stop(net: PNetworkInterface);
begin
  IrqOff(NicE1000.IRQ);
end;

type
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;

// This procedure makes all the job of sending packets
// It is limited to send one packet every time.
// TODO: To improve this by sending a bunch of packets
procedure DoSendPacket(Net: PNetworkInterface);
var
  Tail, I, Head, Next: LongInt;
  Desc: PE1000TxDesc;
  Data, P: PByteArray;
begin
  DisableINT;
  Head := E1000ReadRegister(@NicE1000, E1000_REG_TDH);
  Tail := E1000ReadRegister(@NicE1000, E1000_REG_TDT);
  Next := (Tail + 1) mod NicE1000.TxDescCount;

  // transmission queue is full
  if (Head = Next) then
  begin
    {$IFDEF DebugE1000} WriteDebug('e1000: DoSendPacket with Head = Next, Exiting\n', []); {$ENDIF}
    Exit;
  end;

  Desc := NicE1000.TxDesc;
  inc(Desc, Tail);

  Data := Pointer(PtrUInt(NicE1000.TxBuffer) + (Tail*E1000_IOBUF_SIZE));
  P := net.OutgoingPackets.data;

  // TODO : we are not checking if the packet size is longer that the buffer
  for I:= 0 to net.OutgoingPackets.size - 1 do
    Data^[I] := P^[I];

  Desc.Status  := E1000_RX_STATUS_DONE;
  Desc.Length  := net.OutgoingPackets.size;
  Desc.Command := E1000_TX_CMD_EOP or E1000_TX_CMD_FCS or E1000_TX_CMD_RS;
  E1000WriteRegister(@NicE1000, E1000_REG_TDT,  Next);
  RestoreInt;
end;

procedure e1000Send(Net: PNetworkInterface; Packet: PPacket);
var
  PacketQueue: PPacket;
begin
  PacketQueue := Net.OutgoingPackets;
  if PacketQueue = nil then
  begin
    Net.OutgoingPackets := Packet;
    {$IFDEF DebugE1000}
     if (Net.OutgoingPacketTail <> nil) then
     begin
       WriteDebug('e1000: Net.OutgoingPackets=nil but Net.OutgoingPacketTail <> nil\n\n', []);
     end;
    {$ENDIF}
    Net.OutgoingPacketTail := Packet;
    DoSendPacket(Net);
  end else
  begin
    DisableInt;
    Net.OutgoingPacketTail.Next := Packet;
    Net.OutgoingPacketTail := Packet;
    RestoreInt;
  end;
end;

Type
  TarrayofLongInt = ^arrayofLongInt;
  arrayofLongInt = array[0..1] of LongInt;

function e1000initbuf(Net: PE1000): Boolean;
var
  I: LongInt;
  tmp: TarrayofLongInt;
  RxBuff: PE1000RxDesc;
  TxBuff: PE1000TxDesc;
  r: ^char;
begin
  Net.RxDescCount := E1000_RXDESC_NR;
  Net.TxDescCount := E1000_TXDESC_NR;

  Net.RxDesc := ToroGetMem(Net.RxDescCount*SizeOf(TE1000RxDesc) + 16);

  if Net.RxDesc = nil then
  begin
    Result := False;
    Exit;
  end;

  // aligned RxDesc address
  if (PtrUInt(Net.RxDesc) mod 16 <> 0) then
  begin
    Net.RxDesc := PE1000RxDesc(PtrUInt(Net.RxDesc) + 16 - PtrUInt(Net.RxDesc) mod 16);
  end;

  {$IFDEF DebugE1000} WriteDebug('e1000: RxDesc base address: %d\n', [PtrUInt(Net.RxDesc)]); {$ENDIF}

  r := pointer(Net.RxDesc) ;
  for I := 0 to (Net.RxDescCount*SizeOf(TE1000RxDesc)+16)-1 do
    r[I] := #0;

  Net.RxBufferSize := E1000_RXDESC_NR * E1000_IOBUF_SIZE;

  // TODO: this memory should not be aligned?
  Net.RxBuffer := ToroGetMem(Net.RxBufferSize+16);

  if Net.RxBuffer = nil then
  begin
    ToroFreeMem(Net.RxDesc);
    Result := False;
    Exit;
  end;

  // aligned RxDesc address
  if (PtrUInt(Net.RxBuffer) mod 16 <> 0) then
    Net.RxBuffer := Pointer(PtrUInt(Net.RxBuffer) + 16 - PtrUInt(Net.RxBuffer) mod 16);

  {$IFDEF DebugE1000} WriteDebug('e1000: RxBuffer base address: %d\n', [PtrUInt(Net.RxBuffer)]); {$ENDIF}

  // setup RX descriptors
  RxBuff := Net.RxDesc;
  for I := 0 to E1000_RXDESC_NR-1 do
  begin
    RxBuff.Buffer := DWORD(PtrUInt(Net.RxBuffer) + (I * E1000_IOBUF_SIZE));
    RxBuff.status := 0;
    Inc(RxBuff);
  end;

  Net.TxDesc := ToroGetMem(Net.TxDescCount * SizeOf(TE1000TxDesc) + 16);
  if Net.TxDesc = nil then
  begin
    ToroFreeMem(Net.RxBuffer);
    ToroFreeMem(Net.RxDesc);
    Result := False;
    Exit;
  end;

  // aligned TxDesc address
  if (PtrUInt(Net.TxDesc) mod 16 <> 0) then
    Net.TxDesc := PE1000TxDesc(PtrUInt(Net.TxDesc) + 16 - PtrUInt(Net.TxDesc) mod 16);

  {$IFDEF DebugE1000} WriteDebug('e1000: TxDesc base address: %d\n', [PtrUInt(Net.TxDesc)]); {$ENDIF}

  r := pointer(Net.TxDesc) ;
  for I := 0 to (Net.TxDescCount*SizeOf(TE1000TxDesc))-1 do
    r[I] := #0;

  Net.TxBufferSize := E1000_TXDESC_NR * E1000_IOBUF_SIZE;
  Net.TxBuffer := ToroGetMem(Net.TxBufferSize + 16);

  if Net.TxBuffer = nil then
  begin
    ToroFreeMem(Net.TxDesc);
    ToroFreeMem(Net.RxBuffer);
    ToroFreeMem(Net.RxDesc);
    Result := False;
    Exit;
  end;

  // aligned TxBuffer address
  if (PtrUInt(Net.TxBuffer) mod 16 <> 0) then
  begin
    Net.TxBuffer := Pointer(PtrUInt(Net.TxBuffer) + 16 - PtrUInt(Net.TxBuffer) mod 16);
  end;

  // Setup TX descriptors
  TxBuff := Net.TxDesc;
  for I := 0 to E1000_TXDESC_NR-1 do
    begin
    TxBuff.Buffer := DWORD(PtrUInt(Net.TxBuffer) + (I * E1000_IOBUF_SIZE));
    TxBuff.Command := 0;
    Inc(TxBuff);
    end;

  // Setup the receive ring registers.
  tmp := @Net.RxDesc;
  e1000WriteRegister(Net, E1000_REG_RDBAL, tmp[0]);
  e1000WriteRegister(Net, E1000_REG_RDBAH, tmp[1]);
  e1000WriteRegister(Net, E1000_REG_RDLEN, Net.RxDescCount *SizeOf(TE1000RxDesc));
  e1000WriteRegister(Net, E1000_REG_RDH,   0);
  e1000WriteRegister(Net, E1000_REG_RDT, Net.RxDescCount -1);

  // No delay time for reception ints
  e1000WriteRegister(Net, E1000_REG_RDTR , 0);

  // set packet size
  e1000UnsetRegister(Net, E1000_REG_RCTL, E1000_REG_RCTL_BSIZE);

  // No loopback
  e1000UnsetRegister(Net, E1000_REG_RCTL, (1 shl 7) or (1 shl 6));

  // enable reception, disable unicast promiscous, broadcast accept mode
  e1000SetRegister(Net, E1000_REG_RCTL, E1000_REG_RCTL_EN {or E1000_REG_RCTL_UPE} or E1000_REG_RCTL_BAM or E1000_RCTL_SECRC );

  // Setup the transmit ring registers.
  tmp := @Net.TxDesc;
  E1000WriteRegister(Net, E1000_REG_TDBAL, tmp[0]);
  E1000WriteRegister(Net, E1000_REG_TDBAH, tmp[1]);
  E1000WriteRegister(Net, E1000_REG_TDLEN, Net.TxDescCount * SizeOf(TE1000TxDesc));
  E1000WriteRegister(Net, E1000_REG_TDH,   0);
  E1000WriteRegister(Net, E1000_REG_TDT, 0);
  E1000SetRegister(Net, E1000_REG_TCTL,  E1000_REG_TCTL_EN or E1000_REG_TCTL_PSP);

  Result := True;
end;


// Read a packet from net card and enque it to the outgoing packet list
// This is called only by the interruption handler
procedure ReadPacket(Net: PE1000);
var
  Tail, Current, I: LongInt;
  {$IFDEF DebugE1000} Head: LongInt;{$ENDIF}
  RxDesc: PE1000RxDesc;
  Packet: PPacket;
  Data, P: PByteArray;
  DropFlag: Boolean; // this flag is used to drop packets
begin
  DropFlag:= false;
  // Find the head, tail and current descriptors
  {$IFDEF DebugE1000} Head := E1000ReadRegister(Net, E1000_REG_RDH); {$ENDIF}
  Tail := E1000ReadRegister(Net, E1000_REG_RDT);
  Current  := (Tail + 1) mod Net.RxDescCount;
  RxDesc := Net.RxDesc;
  Inc(RxDesc, Current);

  {$IFDEF DebugE1000}
          WriteDebug('e1000: new packet, head: %d, tail: %d\n', [Head,Tail]);
          WriteDebug('e1000: new packet, status: %d\n', [RxDesc.Status]);
  {$ENDIF}

  // this never should happen
  if (RxDesc.Status and E1000_RX_STATUS_DONE) = 0 then
  begin
    {$IFDEF DebugE1000} WriteDebug('e1000: new packet, E1000_RX_STATUS_DONE Exiting\n', []); {$ENDIF}
    DropFlag := True;
  end;

  // this driver does not hable such a kind of packets
  if (RxDesc.Status and  E1000_RX_STATUS_EOP) = 0 then
  begin
    {$IFDEF DebugE1000} WriteDebug('e1000: new packet, E1000_RX_STATUS_EOP Exiting\n', []); {$ENDIF}
    DropFlag := True;
  end;

  if DropFlag then
  begin
    // reset the descriptor
    RxDesc.Status := E1000_RX_STATUS_DONE;
    // incrementing the tail
    E1000WriteRegister(Net, E1000_REG_RDT, (Tail + 1) mod Net.RxDescCount);
    {$IFDEF DebugE1000} WriteDebug('e1000: packet has been drop\n', []); {$ENDIF}
    Exit;
  end;

  // get memory for new packet
  Packet := ToroGetMem(RxDesc.Length+SizeOf(TPacket));

  if Packet = nil then
  begin
    RxDesc.Status := E1000_RX_STATUS_DONE;
    E1000WriteRegister(Net, E1000_REG_RDT, (Tail + 1) mod Net.RxDescCount);
    {$IFDEF DebugE1000} WriteDebug('e1000: no more memory, dropping packets\n', []); {$ENDIF}
    Exit;
  end;

  Packet.data := Pointer(PtrUInt(Packet) + SizeOf(TPacket));
  Packet.size := RxDesc.Length;
  Packet.Delete := False;
  Packet.Ready := False;
  Packet.Next := nil;

  Data := Packet.data;
  P := Pointer(PtrUInt(Net.RxBuffer) + ((Tail + 1) mod Net.RxDescCount) * E1000_IOBUF_SIZE);
  {$IFDEF DebugE1000} WriteDebug('e1000: new packet, Size: %d\n', [RxDesc.Length]); {$ENDIF}
  for I := 0 to RxDesc.Length-1 do
    Data^[I] := P^[I];

  RxDesc.Status := E1000_RX_STATUS_DONE;
  E1000WriteRegister(Net, E1000_REG_RDT, (Tail + 1) mod Net.RxDescCount);
  EnqueueIncomingPacket(Packet);
end;

// Read all the packets in the reception ring
procedure EmptyReadRing(Net: PE1000);
var
  Tail, Head, Diff: LongInt;
begin
  Head := E1000ReadRegister(Net, E1000_REG_RDH);
  Tail := E1000ReadRegister(Net, E1000_REG_RDT);
  If (Head < Tail) then
     diff  := Net.RxDescCount - Tail + Head - 1
  else
     diff  := Head - Tail - 1;
  {$IFDEF DebugE1000} WriteDebug('e1000: EmptyReadRing will read %d packets\n', [diff]); {$ENDIF}
  while diff <> 0 do
  begin
    // ReadPacket() moves tail
    ReadPacket(Net);
    // we recalculate Tail and we continue getting packets from the ring
    Head := E1000ReadRegister(Net, E1000_REG_RDH);
    Tail := E1000ReadRegister(Net, E1000_REG_RDT);
    If (Head < Tail) then
    diff  := Net.RxDescCount - Tail + Head - 1
    else
       diff  := Head - Tail - 1;
  end;
end;

procedure e1000Handler;
var
  Packet: PPacket;
  Cause: LongInt;
begin
  // Read the Interrupt Cause Read register
  Cause := E1000ReadRegister(@NicE1000, E1000_REG_ICR);
  {$IFDEF DebugE1000} WriteDebug('e1000: Interruption, cause=%d\n', [cause]); {$ENDIF}
  if Cause <> 0 then
  begin
    // link signal
    if (cause and E1000_REG_ICR_LSC) <> 0  then
    begin
      {$IFDEF DebugE1000} WriteDebug('e1000: Link interruption\n', []); {$ENDIF}
    end;
    // packets received
    if ((cause and (E1000_REG_ICR_RXO or E1000_REG_ICR_RXT)) <> 0) then
    begin
      {$IFDEF DebugE1000} WriteDebug('e1000: new packet received\n', []); {$ENDIF}
      EmptyReadRing(@NicE1000);
    end;
    // packets transmitted
    if ((cause and (E1000_REG_ICR_TXQE or E1000_REG_ICR_TXDW)) <> 0) then
    begin
      {$IFDEF DebugE1000} WriteDebug('e1000: Packet transmitted\n', []); {$ENDIF}
      Packet := DequeueOutgoingPacket;
      if Packet <> nil then
        DoSendPacket(@NicE1000.DriverInterface);
    end;
  end;
  eoi;
end;

procedure e1000irqhandler; {$IFDEF FPC} [nostackframe]; assembler; {$ENDIF}
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
 mov r15 , rsp
 mov rbp , r15
 sub r15 , 32
 mov  rsp , r15
 xor rcx , rcx
 Call e1000handler
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

procedure DetectE1000onPCI;
var
  I: LongInt;
  Net: PNetworkInterface;
  PciCard: PBusDevInfo;
  wd: word;
  lowadd: ^dword;
  highadd: ^word;
begin
  PciCard := PCIDevices;
  {$IFDEF DebugE1000} WriteDebug('e1000: scanning pci bus for e1000 driver\n', []); {$ENDIF}
  DisableInt;
  while PciCard <> nil do
  begin
    if (PciCard.mainclass = $02) and (PciCard.subclass = $00) then
    begin
      if (PciCard.vendor = $8086) and (PciCard.device = $100E) then
      begin
        NicE1000.IRQ:= PciCard.irq;
        NicE1000.Regs:= Pointer(PtrUInt(PCIcard.io[0]));
        {$IFDEF DebugE1000} WriteDebug('e1000: found e1000 device, Irq: %d, Regs: %h\n', [PciCard.irq, PCIcard.io[0]]); {$ENDIF}

        // Enable bus mastering for this device
        PciSetMaster(PciCard);

        // specific for E1000_DEV_ID_82540EM
        NicE1000.eepromdonebit := 1 shl 4;
        NicE1000.eepromaddroff := 8;

        // Reset network card
        e1000Reset(@NicE1000);

        // Link is set up
        e1000SetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_ASDE or E1000_REG_CTRL_SLU);
        e1000UnsetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_LRST);
        e1000UnsetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_PHY_RST);
        e1000UnsetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_ILOS);

        // Flow control is disabled
        // TODO: qemu logs says this is invalid write
        e1000WriteRegister(@NicE1000, E1000_REG_FCAL, 0);
        e1000WriteRegister(@NicE1000, E1000_REG_FCAH, 0);
        e1000WriteRegister(@NicE1000, E1000_REG_FCT,  0);
        e1000WriteRegister(@NicE1000, E1000_REG_FCTTV, 0);

        // VLAN is disable
        e1000UnsetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_VME);

        // Initialize statistics registers
        for I := 0 to 63 do
          e1000WriteRegister(@NicE1000, E1000_REG_CRCERRS + (I * 4), 0);

        // Configure the MAC address
        // read the MAC from the eeprom
        for I:=0 to 2 do
          begin
          wd := EepromEerd (@NicE1000,I);
          NicE1000.Driverinterface.HardAddress[I*2]:= wd and $ff;
          NicE1000.Driverinterface.HardAddress[(I*2+1)]:= (wd and $ff00) shr 8;
        end;

        lowadd := @NicE1000.Driverinterface.HardAddress[0];
        highadd := @NicE1000.Driverinterface.HardAddress[4];

        // Set receive address
        e1000WriteRegister(@NicE1000, E1000_REG_RAL, lowadd^);
        e1000WriteRegister(@NicE1000, E1000_REG_RAH, highadd^);
        e1000SetRegister(@NicE1000,   E1000_REG_RAH,   E1000_REG_RAH_AV);

        // Clear Multicast Table Array (MTA)
        for I := 0 to 127 do
          e1000WriteRegister(@NicE1000, E1000_REG_MTA + (I * 4), 0);

        WriteConsoleF('e1000: /Vdetected/n, Irq:%d\n',[PciCard.irq]);
        WriteConsoleF('e1000: mac /V%d:%d:%d:%d:%d:%d/n\n', [NicE1000.Driverinterface.HardAddress[0], NicE1000.Driverinterface.HardAddress[1],NicE1000.Driverinterface.HardAddress[2], NicE1000.Driverinterface.HardAddress[3], NicE1000.Driverinterface.HardAddress[4], NicE1000.Driverinterface.HardAddress[5]]);
        {$IFDEF DebugE1000} WriteDebug('e1000: mac %d:%d:%d:%d:%d:%d\n', [NicE1000.Driverinterface.HardAddress[0], NicE1000.Driverinterface.HardAddress[1],NicE1000.Driverinterface.HardAddress[2], NicE1000.Driverinterface.HardAddress[3], NicE1000.Driverinterface.HardAddress[4], NicE1000.Driverinterface.HardAddress[5]]); {$ENDIF}

        if e1000initbuf(@NicE1000) then
        begin
          WriteConsoleF('e1000: buffer init ... /VOk/n\n',[]);
          {$IFDEF DebugE1000} WriteDebug('e1000: initbuffer() sucesses\n', []); {$ENDIF}
        end
        else
        begin
          WriteConsoleF('e1000: buffer init ... /RFault/n\n',[]);
          {$IFDEF DebugE1000} WriteDebug('e1000: initbuffer() fails, Exiting\n', []); {$ENDIF}
          Continue;
        end;

        // enable interrupt
        e1000SetRegister(@NicE1000, E1000_REG_IMS, E1000_REG_IMS_LSC or E1000_REG_IMS_RXO or E1000_REG_IMS_RXT or E1000_REG_IMS_TXQE or E1000_REG_IMS_TXDW);

        // clear any spurius irq
        E1000ReadRegister(@NicE1000, E1000_REG_ICR);

        // get link status
        i := e1000ReadRegister(@NicE1000, E1000_REG_STATUS);
        if (i and 3 <> 0) then
        begin
          WriteConsoleF('e1000: link is /VUp/n, speed: %d\n', [(i and (3 shl 6)) shr 6]);
          {$IFDEF DebugE1000} WriteDebug('e1000: Link Up, speed: %d\n', [(i and (3 shl 6)) shr 6]); {$ENDIF}
        end
        else
        begin
          WriteConsoleF('e1000: link is /RDown/n, speed: %d\n', [(i and (3 shl 6)) shr 6]);
          {$IFDEF DebugE1000} WriteDebug('e1000: Link Down, speed: %d\n', [(i and (3 shl 6)) shr 6]); {$ENDIF}
        end;
        CaptureInt(32+NicE1000.IRQ, @e1000irqhandler);
        Net := @NicE1000.Driverinterface;
        Net.Name := 'e1000';
        Net.MaxPacketSize := E1000_IOBUF_SIZE;
        Net.start := @e1000Start;
        Net.send := @e1000Send;
        Net.stop := @e1000Stop;
        Net.Reset := @e1000Reset;
        Net.TimeStamp := 0;
        RegisterNetworkInterface(Net);
        end;
      end;
    PciCard := PciCard.Next;
    end;
    RestoreInt;
    {$IFDEF DebugE1000} WriteDebug('e1000: scan ended\n', []); {$ENDIF}
end;

initialization
  DetectE1000onPCI;

end.
