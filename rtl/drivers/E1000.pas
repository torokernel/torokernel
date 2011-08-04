//
// e1000.pas
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

uses Arch, Console, Debug, Filesystem, Network, Process, Memory;


implementation


type
  Pe1000interface = ^Te1000interface;
  Pe1000rxdesc = ^Te1000rxdesc;
  Pe1000txdesc =  ^Te1000txdesc;

  Te1000interface = record
    Driverinterface: TNetworkInterface;
    irq: LongInt;
    eepromdonebit: longint;
    eepromaddroff: longint;
    regs: pointer;
    rxdesccount: longint;
    txdesccount: longint;
    rxdesc: Pe1000rxdesc;
    rxbuffersize: longint;
    txbuffersize: longint;
    rxbuffer: pointer;
    txbuffer: pointer;
    txdesc: Pe1000txdesc;
    NextPacket: LongInt;
  end;


   Te1000rxdesc = record
     buffer: dword;
     buffer_h: dword;
     length: word;
     checksum: word;
     status: byte;
     errors: byte;
     special: word;
   end;

   Te1000txdesc = record
     buffer: dword;
     buffer_h: dword;
     length: word;
     checksum_off: byte;
     command: byte;
     status: byte;
     checksum_st: byte;
     special: word;
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
e1000card: Te1000interface; // Support currently 1 ethernet card




// read e1000 register
function e1000ReadRegister(net: Pe1000interface;reg: longint): longint;
 var
 r: ^dword;
begin
  r:= net.regs + reg;
  e1000ReadRegister:= r^;
end;


// write e1000 register
procedure e1000WriteRegister(net: Pe1000interface;reg, value: longint);
 var
 r: ^dword;
begin
  r:= net^.regs + reg;
  r^ := value;
end;

// set a bit
procedure e1000SetRegister(net: Pe1000interface;reg, value:longint);
var
 data: longint;
begin
  data:= e1000ReadRegister(net, reg);
  e1000WriteRegister(net,reg, data or value);
end;

// unset a bit
procedure e1000UnsetRegister(net: Pe1000interface;reg, value:longint);
var
 data: longint;
begin
  data:= e1000ReadRegister(net, reg);
  e1000WriteRegister(net,reg, data and not(value));
end;



procedure e1000Reset(net: Pe1000interface);
begin
  e1000SetRegister(net, E1000_REG_CTRL, E1000_REG_CTRL_RST);
  //delay(1); // 1 micro
end;

function EepromEerd(net: Pe1000interface;reg: longint): word;
var
 data: word;
begin
  // Request EEPROM read.
  e1000WriteRegister(net, E1000_REG_EERD,(reg shl net^.eepromaddroff) or E1000_REG_EERD_START);
  // Wait until ready.
  // ojo aca puede haber un error
  while ((e1000ReadRegister(net, E1000_REG_EERD) and net^.eepromdonebit)=1) do;
  data := ((e1000ReadRegister(net, E1000_REG_EERD) and E1000_REG_EERD_DATA)) shr 16;
  EepromEerd:= data;
end;

// The card starts to work
procedure e1000Start(net: PNetworkInterface);
begin
  // initialize network driver
end;


// The card stop to work
procedure e1000Stop(net: PNetworkInterface);
begin
end;



type
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;

// Internal Job of NetworkSend
procedure DoSendPacket(Net: PNetworkInterface);
var
 head, tail, j: longint;
 desc: Pe1000txdesc;
 data,p: PByteArray;
begin
  // I need protection from Local IRQ
  DisabledINT;
  head := e1000ReadRegister(@e1000card, E1000_REG_TDH);
  tail := e1000ReadRegister(@e1000card, E1000_REG_TDT);
  desc := e1000card.txdesc;
  inc(desc, tail);
  data := e1000card.txbuffer +(tail * E1000_IOBUF_SIZE);
  p := net.OutgoingPackets.data;
  // Copy bytes to TX queue buffers
  // maybe it is slowly
  for j:= 0 to  (net.OutgoingPackets.size-1) do
    begin
    data^[j] := p^[j];
    end;
  // Mark this descriptor ready.
  desc.status  := 0;
  desc.command := 0;
  desc.length  := net.OutgoingPackets.size;
  //
  // TODO: We are using the Minimun size per packer
  // this marks the end of the packet, maybe I am wrong
  desc.command := E1000_TX_CMD_EOP or E1000_TX_CMD_FCS or E1000_TX_CMD_RS;
  // Increment tail and Start transmission
  // aca falta algo con respecto a tail
  inc(tail);
  e1000WriteRegister(@e1000card, E1000_REG_TDT,  tail);
  EnabledINT;
end;


//
// Send a packet
//
procedure e1000Send(net: PNetworkInterface;Packet: PPacket);
var
  PacketQueue: PPacket;
begin
  // Queue the packet
  PacketQueue := Net.OutgoingPackets;
  if PacketQueue = nil then
  begin
   // I have to enque it
   net.OutgoingPackets := Packet;
   // Send Directly
   DoSendPacket(net);
  end
  else begin
  // It is a FIFO queue
    while PacketQueue.next <> nil do
     PacketQueue:=PacketQueue.next;
    PacketQueue.next :=Packet;
  end;
end;





//
// init RX and TX buffers
//
function e1000initbuf(net: Pe1000interface): boolean;
var
 i: longint;
 rxbuffp: Pe1000rxdesc;
 txbuffp: Pe1000txdesc;
begin
  // Number of descriptors
  net.rxdesccount := E1000_RXDESC_NR;
  net.txdesccount := E1000_TXDESC_NR;

  // allocate RX descriptors
  net.rxdesc := ToroGetMem(net.rxdesccount*sizeof(Te1000rxdesc));

  // we have memory?
  if (net.rxdesc = nil) then
  begin
    result:= false;
    exit;
  end;

  // allocate 2048-byte buffers
  net.rxbuffersize := E1000_RXDESC_NR * E1000_IOBUF_SIZE;
  net.rxbuffer := ToroGetMem(net.rxbuffersize);

  // Setup RX descriptors
  rxbuffp := net.rxdesc;
  for i := 0 to (E1000_RXDESC_NR-1) do
    begin
      rxbuffp.buffer := dword(net.rxbuffer + (i * E1000_IOBUF_SIZE));
      inc(rxbuffp);
    end;

  // allocate TX descriptors
  net.txdesc := ToroGetMem(net.txdesccount * sizeof(Te1000txdesc));

  // we have memory?
  if (net.txdesc = nil) then
  begin
    ToroFreeMem(net.rxdesc);
    result:= false;
    exit;
  end;

  // allocate 2048-byte buffers
  net.txbuffersize := E1000_TXDESC_NR * E1000_IOBUF_SIZE;
  net.txbuffer := ToroGetMem(net.txbuffersize);

  // Setup TX descriptors
  txbuffp := net.txdesc;
  for i := 0 to (E1000_TXDESC_NR-1) do
    begin
      txbuffp.buffer := dword(net.txbuffer + (i * E1000_IOBUF_SIZE));
      inc(txbuffp);
    end;

  // Setup the receive ring registers.
  e1000WriteRegister(net, E1000_REG_RDBAL, longint(net.rxdesc) );
  e1000WriteRegister(net, E1000_REG_RDBAH, 0);
  e1000WriteRegister(net, E1000_REG_RDLEN, net.rxdesccount *sizeof(te1000rxdesc));
  e1000WriteRegister(net, E1000_REG_RDH,   0);
  e1000WriteRegister(net, E1000_REG_RDT,   net.rxdesccount - 1);
  e1000UnsetRegister(net, E1000_REG_RCTL,  E1000_REG_RCTL_BSIZE);
  e1000SetRegister(net,   E1000_REG_RCTL,  E1000_REG_RCTL_EN);

  // Setup the transmit ring registers.
  e1000WriteRegister(net, E1000_REG_TDBAL, longint(net.txdesc));
  e1000WriteRegister(net, E1000_REG_TDBAH, 0);
  e1000WriteRegister(net, E1000_REG_TDLEN, net.txdesccount * sizeof(te1000txdesc));
  e1000WriteRegister(net, E1000_REG_TDH,   0);
  e1000WriteRegister(net, E1000_REG_TDT,   0);
  e1000SetRegister(net, E1000_REG_TCTL,  E1000_REG_TCTL_EN or E1000_REG_TCTL_PSP);
end;


// Read a packet from net card and enque it to Outgoing Packet list
procedure ReadPacket(net: Pe1000interface);
var
  head, tail, cur, j: LongInt;
  desc: Pe1000rxdesc;
  Packet: PPacket;
  data,p: PByteArray;
begin
  // Find the head, tail and current descriptors
  head := e1000ReadRegister(net, E1000_REG_RDH);
  tail := e1000ReadRegister(net, E1000_REG_RDT);
  cur  := (tail + 1) mod net.rxdesccount;
  desc := net.rxdesc;
  inc(desc,cur);

  if (desc.status and  E1000_RX_STATUS_EOP) = 0 then
  begin
    // I have to do something here
  end;

  // Alloc memory for new packet
  Packet := ToroGetMem(desc.length+SizeOf(TPacket));
  Packet.data:= pointer(Packet + SizeOf(TPacket));
  Packet.size:= desc.length;
  // copy to a buffer
  data := packet.data;
  p := pointer(desc.buffer);
  // maybe it is slowly
  for j:= 0 to  (desc.length-1) do
    begin
    data^[j] := p^[j];
    end;
  desc.status := 0;
  // increment tail
  e1000WriteRegister(net, E1000_REG_RDT, (tail + 1) mod net.rxdesccount);
  // report to kernel
  EnqueueIncomingPacket(Packet);
end;

var
   r:boolean = true;

// e1000 Irq Handler
procedure e1000Handler;
var
  Packet: PPacket;
  cause: LongInt;
begin
  // Read the Interrupt Cause Read register
  cause:= e1000ReadRegister(@e1000card, E1000_REG_ICR);
  if (cause and E1000_REG_ICR_LSC) <> 0  then
  begin
  // link
  end else if (cause and (E1000_REG_ICR_RXO or E1000_REG_ICR_RXT)) <> 0 then
  begin
  // receiv
    ReadPacket(@e1000card);
    printk_('new packet\n',0);
  end else if ((cause and E1000_REG_ICR_TXQE) <> 0 ) or ((cause and E1000_REG_ICR_TXDW) <> 0) then
  begin
    // packet sent
    // Inform Kernel Last packet has been sent, and fetch the next packet to send
    if r then r:= false else
    begin
    Packet := DequeueOutgoingPacket;
    // We have got to send more packet ?
    if Packet <> nil then
      DoSendPacket(@e1000card.DriverInterface);
    end;
    end;
  eoi;
end;


procedure e1000irqhandler; [nostackframe]; assembler;
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

// Look for e1000 card in PCI bus and register it.
// Currently support for one NIC
procedure PCICardInit;
var
  PCIcard: PBusDevInfo;
  net: PNetworkInterface;
  i: longint;
  wd: word;
begin
  PCIcard:= PCIDevices;
  while PCIcard <> nil do
  begin
    // looking for ethernet network card
    if (PCIcard.mainclass = $02) and (PCIcard.subclass = $00) then
    begin
      // looking for e1000 card
      if (PCIcard.vendor = $8086) and (PCIcard.device = $100E) then
      begin
        e1000card.irq:= PCIcard.irq;
        // manually, I have to fix this
        e1000card.regs:= $0F2020000;//pointer(PCIcard.io[0])
        // work just for $100e card
        e1000card.eepromdonebit := 1 shl 4;
	e1000card.eepromaddroff := 8;
        // reset network card
        e1000Reset(@e1000card);
        // initialization procedure as intel say
        e1000SetRegister(@e1000card, E1000_REG_CTRL, E1000_REG_CTRL_ASDE or E1000_REG_CTRL_SLU);
        e1000UnsetRegister(@e1000card, E1000_REG_CTRL, E1000_REG_CTRL_LRST);
        e1000UnsetRegister(@e1000card, E1000_REG_CTRL, E1000_REG_CTRL_PHY_RST);
        e1000UnsetRegister(@e1000card, E1000_REG_CTRL, E1000_REG_CTRL_ILOS);
        e1000WriteRegister(@e1000card, E1000_REG_FCAL, 0);
        e1000WriteRegister(@e1000card, E1000_REG_FCAH, 0);
        e1000WriteRegister(@e1000card, E1000_REG_FCT,  0);
        e1000WriteRegister(@e1000card, E1000_REG_FCTTV, 0);
        e1000UnsetRegister(@e1000card, E1000_REG_CTRL, E1000_REG_CTRL_VME);
        // Clear Multicast Table Array (MTA)
        for i:= 0 to 127 do
          e1000WriteRegister(@e1000card, E1000_REG_MTA + i, 0);
        // Initialize statistics registers
        for i:= 0 to 63 do
          e1000WriteRegister(@e1000card, E1000_REG_CRCERRS + (i * 4), 0);
        // read the MAC from the eeprom
        for i:=0 to 2 do
          begin
           wd := EepromEerd (@e1000card,i);
           e1000card.Driverinterface.HardAddress[i*2]:= wd and $ff;
           e1000card.Driverinterface.HardAddress[(i*2+1)]:= (wd and $ff00) shr 8;
          end;
        // set receiv address
        e1000WriteRegister(@e1000card, E1000_REG_RAL, e1000card.Driverinterface.HardAddress[0]);
        e1000WriteRegister(@e1000card, E1000_REG_RAH, e1000card.Driverinterface.HardAddress[4]);
        e1000SetRegister(@e1000card,   E1000_REG_RAH,   E1000_REG_RAH_AV);
        e1000SetRegister(@e1000card,   E1000_REG_RCTL,  E1000_REG_RCTL_MPE);
        WriteConsole('e1000 /Vdetected/n, Irq:%d\n',[PCIcard.irq]);
        WriteConsole('e1000 mac /V%d:%d:%d:%d:%d:%d/n\n', [e1000card.Driverinterface.HardAddress[0], e1000card.Driverinterface.HardAddress[1],e1000card.Driverinterface.HardAddress[2], e1000card.Driverinterface.HardAddress[3], e1000card.Driverinterface.HardAddress[4], e1000card.Driverinterface.HardAddress[5]]);
        // buffer initialization
        if e1000initbuf(@e1000card) then
         WriteConsole('e1000 buffer init ... /VOk/n\n',[])
        else
        WriteConsole('e1000 buffer init ... /RFault/n\n',[]);
        Irq_On(e1000card.irq);
        // capture de interrupt
        CaptureInt(32+e1000card.irq, @e1000irqhandler);
        // enable interrupts
        e1000SetRegister(@e1000card,E1000_REG_IMS,E1000_REG_IMS_LSC or E1000_REG_IMS_RXO or E1000_REG_IMS_RXT or E1000_REG_IMS_TXQE or E1000_REG_IMS_TXDW);
        net := @e1000card.Driverinterface;
        net.Name:= 'e1000';
        net.MaxPacketSize:= E1000_IOBUF_SIZE;
        net.start:= @e1000Start;
        net.send:= @e1000Send;
        net.stop:= @e1000Stop;
        net.Reset:= @e1000Reset;
        net.TimeStamp := 0;
        // don´t forget to register the nec
        RegisterNetworkInterface(net);
        end;
      end;
    PCIcard := PCIcard.next;
    end;
end;

initialization
PCICardInit;
end.
