//
// E1000.pas
//
// Driver for Intel 1000 PRO network card.
//
// Changes:
//
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

unit E1000;

interface

{$I ..\Toro.inc}
// {$DEFINE DebugE1000}


uses
  {$IFDEF DEBUG} Debug, {$ENDIF}
  FileSystem, // required only for PciDetect, TODO: move this code to a new unit Pci.pas or in Arch.pas
  Arch, Console, Network, Process, Memory;

implementation

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

   E1000_REG_CTRL_RST =	1 shl 26;
   E1000_REG_CTRL_ASDE = 1 shl 5;
   E1000_REG_CTRL_SLU = 1 shl 6;
   E1000_REG_CTRL_LRST = 1 shl 3;
   E1000_REG_CTRL_PHY_RST = 1 shl 31;
   E1000_REG_CTRL_ILOS	= 1 shl 7;
   E1000_REG_CTRL_VME	= 1 shl 30;

   E1000_REG_EERD_START = 1 shl 0;
   E1000_REG_EERD_DATA	= $ffff shl 16;

   E1000_REG_RCTL_MPE	= 1 shl 4;
   E1000_REG_RAH_AV	= 1 shl 31;

   E1000_REG_RDBAL = $2800;
   E1000_REG_RDBAH = $2804;
   E1000_REG_RDLEN = $2808;
   E1000_REG_RCTL_EN = 1 shl 1;
   E1000_REG_RCTL_BSIZE	= ((1 shl 16) or (1 shl 17));
   E1000_REG_TDBAL = $3800;
   E1000_REG_TDBAH = $3804;
   E1000_REG_TDLEN = $3808;
   E1000_REG_TDH = $3810;
   E1000_REG_TDT = $3818;
   E1000_REG_RDH = $2810;
   E1000_REG_RDT = $2818;
   E1000_REG_TCTL_PSP =	1 shl 3;
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

   E1000_RX_STATUS_EOP	= 1 shl 1;

var
  NicE1000: TE1000; // Support currently 1 ethernet card

// read e1000 register
function E1000ReadRegister(Net: PE1000; reg: LongInt): LongInt;
var
  r: ^DWORD;
begin
  r := Pointer(PtrUInt(Net.Regs)+reg);
  Result := r^;
end;

// write e1000 register
procedure E1000WriteRegister(Net: PE1000; Reg, Value: LongInt);
var
  r: ^DWORD;
begin
  r := Pointer(PtrUInt(Net.Regs)+Reg);
  r^ := Value;
end;

// set a bit
procedure E1000SetRegister(Net: PE1000; Reg, Value:LongInt);
var
  Data: LongInt;
begin
  Data:= E1000ReadRegister(Net, Reg);
  E1000WriteRegister(Net, Reg, Data or Value);
end;

// unset a bit
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
  //delay(1); // 1 micro
end;

function EepromEerd(Net: PE1000; Reg: LongInt): Word;
begin
  // Request EEPROM read.
  E1000WriteRegister(Net, E1000_REG_EERD,(Reg shl Net^.EepromAddrOff) or E1000_REG_EERD_START);
  // Wait until ready.
  while (E1000ReadRegister(Net, E1000_REG_EERD) and Net^.EepromDoneBit) = 1 do ;
  Result := ((E1000ReadRegister(Net, E1000_REG_EERD) and E1000_REG_EERD_DATA)) shr 16;
end;

// Kernel starts the card
procedure e1000Start(net: PNetworkInterface);
var
  CPU: byte;
begin
  CPU := GetApicid;
  IrqOn(NicE1000.IRQ);
  // enable the interruption
  e1000SetRegister(@NicE1000, E1000_REG_IMS, E1000_REG_IMS_LSC or E1000_REG_IMS_RXO or E1000_REG_IMS_RXT or E1000_REG_IMS_TXQE or E1000_REG_IMS_TXDW);
end;

// Kernel stops the card
procedure e1000Stop(net: PNetworkInterface);
begin
end;

type
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;

// Internal Job of NetworkSend
procedure DoSendPacket(Net: PNetworkInterface; Isirq: boolean);
var
  Tail, I: LongInt;
  Desc: PE1000TxDesc;
  Data, P: PByteArray;
begin
  // the kernel is calling, we need protection
  If not(Isirq) then
   DisabledINT;
  E1000ReadRegister(@NicE1000, E1000_REG_TDH);
  Tail := E1000ReadRegister(@NicE1000, E1000_REG_TDT);
  Desc := NicE1000.TxDesc;
  inc(Desc, Tail);
  Data := Pointer(PtrUInt(NicE1000.TxBuffer) + (Tail*E1000_IOBUF_SIZE));
  P := net.OutgoingPackets.data;
  // copy bytes to TX queue buffers
  // TODO : we are not checking if the packet size is longer that the buffer!!
  // suppousin than the size is less than BUFFER_SIZE
  for I:= 0 to  (net.OutgoingPackets.size-1) do
    Data^[I] := P^[I];
  // mark this descriptor ready
  Desc.Status  := 0;
  Desc.Command := 0;
  Desc.Length  := net.OutgoingPackets.size;
  // TODO: We are using just a Buffer per packet
  // this marks the end of the packet, maybe I am wrong
  Desc.Command := E1000_TX_CMD_EOP or E1000_TX_CMD_FCS or E1000_TX_CMD_RS;
  // increment tail and Start transmission
  E1000WriteRegister(@NicE1000, E1000_REG_TDT,  (Tail+1) mod NicE1000.TxDescCount);
  // Irq on again
  If not(Isirq) then
   EnabledINT;
end;

// Send a packet
procedure e1000Send(Net: PNetworkInterface; Packet: PPacket);
var
  PacketQueue: PPacket;
begin
  // queue the packet
  PacketQueue := Net.OutgoingPackets;
  if PacketQueue = nil then
  begin
   // i have to enque it
    Net.OutgoingPackets := Packet;
   // send Directly
    DoSendPacket(Net,false);
  end else
  begin
    // we need local protection
    DisabledInt;
    // it is a FIFO queue
    while PacketQueue.Next <> nil do
      PacketQueue := PacketQueue.Next;
    PacketQueue.Next := Packet;
    EnabledInt;
  // end protection
  end;
end;

// Init RX and TX buffers
function e1000initbuf(Net: PE1000): Boolean;
var
  I: LongInt;
  RxBuff: PE1000RxDesc;
  TxBuff: PE1000TxDesc;
  r: ^char;
begin
  // number of descriptors
  Net.RxDescCount := E1000_RXDESC_NR;
  Net.TxDescCount := E1000_TXDESC_NR;
  // allocate RX descriptors
  Net.RxDesc := ToroGetMem(Net.RxDescCount*SizeOf(TE1000RxDesc));
  if Net.RxDesc = nil then
  begin // not enough memory
    Result := False;
    Exit;
  end;
  // fill with zeros
  r := pointer(Net.RxDesc) ;
  for I := 0 to   ((Net.RxDescCount*SizeOf(TE1000RxDesc))-1) do
    r[I] := #0;
  // allocate 2048-Byte buffers
  Net.RxBufferSize := E1000_RXDESC_NR * E1000_IOBUF_SIZE;
  Net.RxBuffer := ToroGetMem(Net.RxBufferSize);
  if Net.RxBuffer = nil then
  begin // not enough memory
    ToroFreeMem(Net.RxDesc);
    Result := False;
    Exit;
  end;
  // setup RX descriptors
  RxBuff := Net.RxDesc;
  for I := 0 to E1000_RXDESC_NR-1 do
    begin
    RxBuff.Buffer := DWORD(PtrUInt(Net.RxBuffer) + (I * E1000_IOBUF_SIZE));
    inc(RxBuff);
    end;
  Net.TxDesc := ToroGetMem(Net.TxDescCount * SizeOf(TE1000TxDesc));
  if Net.TxDesc = nil then
  begin // not enough memory
    ToroFreeMem(Net.RxBuffer);
    ToroFreeMem(Net.RxDesc);
    Result := False;
    Exit;
  end;
  // fill with zeros
  r := pointer(Net.TxDesc) ;
  for I := 0 to   ((Net.TxDescCount*SizeOf(TE1000RxDesc))-1) do
   r[I] := #0;
  // allocate 2048-Byte buffers
  Net.TxBufferSize := E1000_TXDESC_NR * E1000_IOBUF_SIZE;
  Net.TxBuffer := ToroGetMem(Net.TxBufferSize);
  if Net.TxBuffer = nil then
  begin // not enough memory
    ToroFreeMem(Net.TxDesc);
    ToroFreeMem(Net.RxBuffer);
    ToroFreeMem(Net.RxDesc);
    Result := False;
    Exit;
  end;
  // Setup TX descriptors
  TxBuff := Net.TxDesc;
  for I := 0 to E1000_TXDESC_NR-1 do
    begin
    TxBuff.Buffer := DWORD(PtrUInt(Net.TxBuffer) + (I * E1000_IOBUF_SIZE));
    Inc(TxBuff);
    end;
  // Setup the receive ring registers.
  E1000WriteRegister(Net, E1000_REG_RDBAL, LongInt(Net.RxDesc) );
  E1000WriteRegister(Net, E1000_REG_RDBAH, 0);
  E1000WriteRegister(Net, E1000_REG_RDLEN, Net.RxDescCount *SizeOf(TE1000RxDesc));
  E1000WriteRegister(Net, E1000_REG_RDH,   0);
  E1000WriteRegister(Net, E1000_REG_RDT,   Net.RxDescCount - 1);
  e1000UnsetRegister(Net, E1000_REG_RCTL,  E1000_REG_RCTL_BSIZE);
  E1000SetRegister(Net,   E1000_REG_RCTL,  E1000_REG_RCTL_EN);
  // Setup the transmit ring registers.
  E1000WriteRegister(Net, E1000_REG_TDBAL, LongInt(Net.TxDesc));
  E1000WriteRegister(Net, E1000_REG_TDBAH, 0);
  E1000WriteRegister(Net, E1000_REG_TDLEN, Net.TxDescCount * SizeOf(TE1000TxDesc));
  E1000WriteRegister(Net, E1000_REG_TDH,   0);
  E1000WriteRegister(Net, E1000_REG_TDT,   0);
  E1000SetRegister(Net, E1000_REG_TCTL,  E1000_REG_TCTL_EN or E1000_REG_TCTL_PSP);
  Result := True;
end;

// Read a packet from net card and enque it to Outgoing Packet list
procedure ReadPacket(Net: PE1000);
var
  Tail, Current, I: LongInt;
  RxDesc: PE1000RxDesc;
  Packet: PPacket;
  Data, P: PByteArray;
begin
  // Find the head, tail and current descriptors
  E1000ReadRegister(Net, E1000_REG_RDH);
  Tail := E1000ReadRegister(Net, E1000_REG_RDT);
  Current  := (Tail + 1) mod Net.RxDescCount;
  RxDesc := Net.RxDesc;
  Inc(RxDesc, Current);
  if (RxDesc.Status and  E1000_RX_STATUS_EOP) = 0 then
  begin
    // I have to do something here
  end;
  // Alloc memory for new packet
  Packet := ToroGetMem(RxDesc.Length+SizeOf(TPacket));
  // we haven't got memory ---> missing packets
  if Packet = nil then
  begin
   // incrementing the tail
   E1000WriteRegister(Net, E1000_REG_RDT, (Tail + 1) mod Net.RxDescCount);
   WriteConsole('e1000 /Rmising packets/n\n',[]);
   exit;
  end;
  Packet.data:= Pointer(PtrUInt(Packet) + SizeOf(TPacket));
  Packet.size:= RxDesc.Length;
  // copying to the buffer
  Data := Packet.data;
  P := Pointer(RxDesc.Buffer);
  for I:= 0 to RxDesc.Length-1 do
    Data^[I] := P^[I];
  RxDesc.Status := 0;
  // incrementing the tail
  E1000WriteRegister(Net, E1000_REG_RDT, (Tail + 1) mod Net.RxDescCount);
  // report to kernel
  EnqueueIncomingPacket(Packet);
end;

// E1000 Irq Handler
procedure e1000Handler;
var
  Packet: PPacket;
  cause: LongInt;
begin
  // Read the Interrupt Cause Read register
  cause:= E1000ReadRegister(@NicE1000, E1000_REG_ICR);
  if (cause and E1000_REG_ICR_LSC) <> 0  then
  begin
  // link
  end else if (cause and (E1000_REG_ICR_RXO or E1000_REG_ICR_RXT)) <> 0 then
  begin
    // received packet
    ReadPacket(@NicE1000);
    printk_('recibido!\n',0);
    {$IFDEF DebugE1000} DebugTrace('e1000Handler - Packet received', 0, 0, 0); {$ENDIF}
  end else if ((cause and E1000_REG_ICR_TXQE) <> 0 ) or ((cause and E1000_REG_ICR_TXDW) <> 0) then
  begin
    // inform the kernel that last packet has been sent, and fetch the next packet to send
    Packet := DequeueOutgoingPacket;
    printk_('Enviado!\n',0);
    // there are more packets?
    if Packet <> nil then
        DoSendPacket(@NicE1000.DriverInterface,true);
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
 push r13
 push r14
 // protect the stack
 mov r15 , rsp
 mov rbp , r15
 sub r15 , 32
 mov  rsp , r15
 xor rcx , rcx
 // call handler
 Call e1000handler
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

// Search for e1000 card in PCI bus and register it.
// Currently support for one NIC
procedure PCICardInit;
var
  I: LongInt;
  Net: PNetworkInterface;
  PciCard: PBusDevInfo;
  wd: word;
begin
  PciCard := PCIDevices;
  while PciCard <> nil do
  begin
    // looking for ethernet network card
    if (PciCard.mainclass = $02) and (PciCard.subclass = $00) then
    begin
      // looking for e1000 card
      if (PciCard.vendor = $8086) and (PciCard.device = $100E) then
      begin
        NicE1000.IRQ:= PciCard.irq;
        // manually, I have to fix this
        NicE1000.Regs:= Pointer($0F2020000); //Pointer(PCIcard.io[0])
        // work just for $100e card
        NicE1000.eepromdonebit := 1 shl 4;
	NicE1000.eepromaddroff := 8;
        // reset network card
        e1000Reset(@NicE1000);
        // initialization procedure as intel say
        e1000SetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_ASDE or E1000_REG_CTRL_SLU);
        e1000UnsetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_LRST);
        e1000UnsetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_PHY_RST);
        e1000UnsetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_ILOS);
        e1000WriteRegister(@NicE1000, E1000_REG_FCAL, 0);
        e1000WriteRegister(@NicE1000, E1000_REG_FCAH, 0);
        e1000WriteRegister(@NicE1000, E1000_REG_FCT,  0);
        e1000WriteRegister(@NicE1000, E1000_REG_FCTTV, 0);
        e1000UnsetRegister(@NicE1000, E1000_REG_CTRL, E1000_REG_CTRL_VME);
        // Clear Multicast Table Array (MTA)
        for I := 0 to 127 do
          e1000WriteRegister(@NicE1000, E1000_REG_MTA + I, 0);
        // Initialize statistics registers
        for I := 0 to 63 do
          e1000WriteRegister(@NicE1000, E1000_REG_CRCERRS + (I * 4), 0);
        // read the MAC from the eeprom
        for I:=0 to 2 do
          begin
          wd := EepromEerd (@NicE1000,I);
          NicE1000.Driverinterface.HardAddress[I*2]:= wd and $ff;
          NicE1000.Driverinterface.HardAddress[(I*2+1)]:= (wd and $ff00) shr 8;
        end;
        // set receive address
        e1000WriteRegister(@NicE1000, E1000_REG_RAL, dword(@NicE1000.Driverinterface.HardAddress[0]));
        e1000WriteRegister(@NicE1000, E1000_REG_RAH, word(@NicE1000.Driverinterface.HardAddress[4]));
        e1000SetRegister(@NicE1000,   E1000_REG_RAH,   E1000_REG_RAH_AV);
        e1000SetRegister(@NicE1000,   E1000_REG_RCTL,  E1000_REG_RCTL_MPE);
        WriteConsole('e1000: /Vdetected/n, Irq:%d\n',[PciCard.irq]);
        WriteConsole('e1000: mac /V%d:%d:%d:%d:%d:%d/n\n', [NicE1000.Driverinterface.HardAddress[0], NicE1000.Driverinterface.HardAddress[1],NicE1000.Driverinterface.HardAddress[2], NicE1000.Driverinterface.HardAddress[3], NicE1000.Driverinterface.HardAddress[4], NicE1000.Driverinterface.HardAddress[5]]);
        // buffer initialization
        if e1000initbuf(@NicE1000) then
         WriteConsole('e1000: buffer init ... /VOk/n\n',[])
        else
        WriteConsole('e1000: buffer init ... /RFault/n\n',[]);
        // capture de interrupt
        CaptureInt(32+NicE1000.IRQ, @e1000irqhandler);
        Net := @NicE1000.Driverinterface;
        Net.Name:= 'e1000';
        Net.MaxPacketSize:= E1000_IOBUF_SIZE;
        Net.start:= @e1000Start;
        Net.send:= @e1000Send;
        Net.stop:= @e1000Stop;
        Net.Reset:= @e1000Reset;
        Net.TimeStamp := 0;
        // regist network driver
        RegisterNetworkInterface(Net);
        end;
      end;
    PciCard := PciCard.Next;
    end;
end;

initialization
	PCICardInit;

end.
