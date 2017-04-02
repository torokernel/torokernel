//
// Network.pas
//
// Manipulation of Packets and Network Interfaces.
// Implements TCP-IP Stack and socket structures.
//
// Notes :
// - Every Network resource is dedicated to one CPU, the programmer must dedicate the resource
// - Only major Sockets Syscalls are implemented at this time
//
// Changes :
//
// 26/08/2011 Important bug fixed around network interface registration.
// 17/08/2009 Multiplex-IO implemented at the level of kernel. First Version by Matias E. Vara.
// 24/03/2009 SysMuxSocketSelect(), Select() with MultiplexIO.
// 26/12/2008 Packet-Cache was removed and replaced with a most simple way. Solved bugs in Size of packets and support multiples connections.
// 31/12/2007 First Version by Matias E. Vara.
//
// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
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

unit Network;

interface

{$I Toro.inc}

uses
  Arch, Process, Console, Memory, Debug;

const
  // Sockets Types
  SOCKET_DATAGRAM = 1; // For datagrams like UDP
  SOCKET_STREAM = 2; // For connections like TCP
  MAX_SocketPORTS = 10000; // Max number of ports supported
  MAX_WINDOW = $4000; // Max Window Size
  MTU = 1200; // MAX Size of packet for TCP Stack
  USER_START_PORT = 7000; // First PORT used by GetFreePort
  SZ_SocketBitmap = (MAX_SocketPORTS - USER_START_PORT) div SizeOf(Byte)+1; // Size of Sockets Bitmaps
  // Max Time that Network Card can be Inactive with packet in a Buffer,  in ms
  // TODO: This TIMER wont be necessary
  MAX_TIME_SENDER = 50;
  WAIT_ICMP = 50;
type
  PNetworkInterface = ^TNetworkInterface;
  PPacket = ^TPacket;
  PEthHeader= ^TEthHeader;
  PArpHeader = ^TArpHeader;
  PIPHeader= ^TIPHeader;
  PTCPHeader= ^TTCPHeader;
  PUDPHeader = ^TUDPHeader;
  PSocket = ^TSocket;
  PMachine = ^TMachine;
  PICMPHeader = ^TICMPHeader;
  PNetworkService = ^TNetworkService;
  PNetworkHandler = ^TNetworkHandler;
  PBufferSender = ^TBufferSender;
  THardwareAddress = array[0..5] of Byte; // MAC Address
  TIPAddress = DWORD; // IP v4

  TEthHeader = packed record
    Destination: THardwareAddress ;
    Source : THardwareAddress ;
    ProtocolType: Word;
  end;

  TArpHeader =  packed record
    Hardware: Word;
    Protocol: Word;
    HardwareAddrLength: Byte;
    ProtocolAddrLength: Byte;
    OpCode: Word;
    SenderHardAddr: THardwareAddress ;
    SenderIpAddr: TIPAddress;
    TargetHardAddr: THardwareAddress ;
    TargetIpAddr: TIPAddress;
  end;

  TIPHeader = packed record
    VerLen       : Byte;
    TOS          : Byte;
    PacketLength : Word;
    ID           : Word;
    Flags        : Byte;
    FragmentOfs  : Byte;
    TTL          : Byte;
    Protocol     : Byte;
    Checksum     : Word;
    SourceIP     : TIPAddress;
    DestIP       : TIPAddress;
  end;

  TTCPHeader = packed record
    SourcePort, DestPort: Word;
    SequenceNumber: DWORD;
    AckNumber: DWORD;
    Header_Length: Byte;
    Flags: Byte;
    Window_Size: Word;
    Checksum: Word;
    UrgentPointer: Word;
  end;

  TUDPHeader = packed record
    ID: Word;
    SourceIP, DestIP: TIPAddress;
    SourcePort, DestPort: Word;
    PacketLength: Word;
    checksum: Word;
  end;

  TICMPHeader = packed record
    tipe: Byte;
    code: Byte;
    checksum: Word;
    id: Word;
    seq: Word;
  end;

  TPacket = record // managed by Packet-Cache
    Size: LongInt;
    Data: Pointer;
    Status: Boolean; // result of transmition
    Ready: Boolean; // only for the kernel , the packet was sent
    Delete: Boolean; // Special Packet can be deleted
    Next: PPacket;  // only for the kernel
  end;
  
  // Entry in Translation Table
  TMachine = record
    IpAddress: TIpAddress;
    HardAddress: THardwareAddress;
    Next: PMachine;
  end;
   
  TNetworkInterface = record
    Name: AnsiString; // Name of interface
    Minor: LongInt; // Internal Identificator
    MaxPacketSize: LongInt; // Max size of packet
    HardAddress: THardwareAddress; // MAC Address
    // Packets from physical layer.
    IncomingPackets: PPacket;
    OutgoingPackets: PPacket;
    // Handlers of drivers
    Start: procedure (NetInterface: PNetworkInterface);
    Send: procedure (NetInterface: PNetWorkInterface;Packet: PPacket);
    Reset: procedure (NetInterface: PNetWorkInterface);
    Stop: procedure (NetInterface: PNetworkInterface);
    CPUID: LongInt; // CPUID for which is dedicated this Network Interface Card
    TimeStamp: Int64;
    Next: PNetworkInterface;
  end;

  TNetworkDedicate = record
    NetworkInterface: PNetworkInterface; // Hardware Driver
    IpAddress: TIPAddress; // Internet Protocol Address
    Gateway: TIPAddress;
    Mask: TIPAddress;
    TranslationTable: PMachine;
    // Table of Sockets sorted by port
    // Sockets for conections
    SocketStream: array[0..MAX_SocketPORTS-1] of PNetworkService;
    SocketStreamBitmap: array[0..SZ_SocketBitmap] of Byte;
    // Sockets for Datagram
    SocketDatagram: array[0..MAX_SocketPORTS-1] of PNetworkService;
    SocketDatagramBitmap: array[0..SZ_SocketBitmap] of Byte;
  end;
  PNetworkDedicate = ^TNetworkDedicate;

  PSockAddr = ^TSockAddr;
  TSockAddr = record
    case Integer of
      0: (sin_family: Word;
          sin_port: Word;
          sin_addr: TIPAddress;
          sin_zero: array[0..7] of XChar);
      1: (sa_family: Word;
          sa_data: array[0..13] of XChar)
  end;
  TInAddr = TIPAddress;

  // Socket structure
  TSocket = record
    SourcePort,DestPort: LongInt;
    DestIp: TIPAddress;
    SocketType: LongInt;
    Mode: LongInt;
    State: LongInt;
    LastSequenceNumber: UInt32;
    LastAckNumber: LongInt;
    RemoteWinLen: UInt32;
    RemoteWinCount: UInt32;
    BufferReader: PChar;
    BufferLength: UInt32;
    Buffer: PChar;
    ConnectionsQueueLen: LongInt;
    ConnectionsQueueCount: LongInt;
    PacketReading: PPacket;
    PacketReadCount: LongInt;
    PacketReadOff: Pointer;
    NeedFreePort: Boolean;
    DispatcherEvent: LongInt;
    TimeOut:Int64;
    Counter: Int64;
    BufferSender: PBufferSender;
    AckFlag: Boolean;
    AckTimeOut: LongInt;
    WinFlag: Boolean;
    WinTimeOut: LongInt;
    WinCounter: LongInt;
	RemoteClose: Boolean;
    Next: PSocket;
  end;

  // Network Service Structure
  TNetworkService = record
    ServerSocket: PSocket;
    ClientSocket: PSocket;
  end;

  // Network Service event handler
  TNetworkHandler = record
    DoInit: procedure;
    DoAccept: function (Socket: PSocket): LongInt;
    DoTimeOUT: function (Socket: PSocket): LongInt;
    DoReceive: function (Socket: PSocket): LongInt;
    DoConnect: function (Socket: PSocket): LongInt;
    DoConnectFail: function (Socket: PSocket): LongInt;
    DoClose: function (Socket: PSocket): LongInt;
  end;

  // Structure used for send a packet at TCP Layer
  TBufferSender = record
    Packet: PPacket;
    Attempts: LongInt;
    Counter: Int64;
    NextBuffer: PBufferSender;
  end;

//
// Socket APIs
//
procedure SysRegisterNetworkService(Handler: PNetworkHandler);
function SysSocket(SocketType: LongInt): PSocket;
function SysSocketBind(Socket: PSocket; IPLocal, IPRemote: TIPAddress; LocalPort: LongInt): Boolean;
procedure SysSocketClose(Socket: PSocket);
function SysSocketConnect(Socket: PSocket): Boolean;
function SysSocketListen(Socket: PSocket; QueueLen: LongInt): Boolean;
function SysSocketPeek(Socket: PSocket; Addr: PChar; AddrLen: UInt32): LongInt;
function SysSocketRecv(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32) : LongInt;
function SysSocketSend(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32): LongInt;
function SysSocketSelect(Socket:PSocket;TimeOut: LongInt):Boolean;

procedure NetworkInit; // used by kernel

// Network Interface Driver
procedure RegisterNetworkInterface(NetInterface: PNetworkInterface);
function DequeueOutgoingPacket: PPacket; // Called by ne2000irqhandler.Ne2000Handler
procedure EnqueueIncomingPacket(Packet: PPacket); // Called by ne2000irqhandler.Ne2000Handler.ReadPacket
procedure SysNetworkSend(Packet: PPacket);
function SysNetworkRead: PPacket;
function GetLocalMAC: THardwareAddress;
function GetMacAddress(IP: TIPAddress): PMachine;
procedure _IPAddress(const Ip: array of Byte; var Result: TIPAddress);
procedure _IPAddresstoArray(const Ip: TIPAddress; var Result: array of Byte);
function ICMPSendEcho(IpDest: TIPAddress; Data: Pointer; len: longint; seq, id: word): longint;
function ICMPPoolPackets: PPacket;
function SwapWORD(n: Word): Word; {$IFDEF INLINE}inline;{$ENDIF}

// primitive for programmer to register a NIC
procedure DedicateNetwork(const Name: AnsiString; const IP, Gateway, Mask: array of Byte; Handler: TThreadFunc);

implementation

var
  DedicateNetworks: array[0..MAX_CPU-1] of TNetworkDedicate;
  NetworkInterfaces: PNetworkInterface = nil;

const
  IPv4_VERSION_LEN = $45;

  // Ethernet Packet type
  ETH_FRAME_IP = $800;
  ETH_FRAME_ARP = $806;

  // ICMP Packet type
  ICMP_ECHO_REPLY = 0;
  ICMP_ECHO_REQUEST = 8;

   // IP packet type
  IP_TYPE_ICMP = 1;
  IP_TYPE_UDP = $11;
  IP_TYPE_TCP = 6;

  // TCP flags
  TCP_SYN =2;
  TCP_SYNACK =18;
  TCP_ACK =16;
  TCP_FIN=1;
  TCP_ACKPSH = $18;
  TCP_ACKEND = TCP_ACK or TCP_FIN;
  TCP_RST = 4 ;

  MAX_ARPENTRY=100; // Max number of entries in ARP Table

  // Socket State
  SCK_BLOCKED = 0;
  SCK_LISTENING = 1;
  SCK_NEGOTIATION = 2;
  SCK_CONNECTING = 6;
  SCK_TRANSMITTING = 3;
  SCK_LOCALCLOSING = 5;
  SCK_PEER_DISCONNECTED = 9;
  SCK_CLOSED = 4;

  // Socket Mode
  MODE_SERVER = 1;
  MODE_CLIENT = 2;

  // Time for wait ACK answer, 50 miliseg per connection
  WAIT_ACK = 50;
  // Time for wait ARP Responsep
  WAIT_ARP = 50;
  // Time for wait a Remote Close , 10 seg. per connection
  WAIT_ACKFIN = 10000;

  // Times that is repeat the operation
  MAX_RETRY = 2;

  // Time for realloc memory for remote Window
  WAIT_WIN = 30000;

  // Socket Dispatcher State
  // Of sockets Clients
  DISP_ACCEPT = 1;
  DISP_WAITING = 0;
  DISP_TIMEOUT = 4;
  DISP_RECEIVE = 2;
  DISP_CONNECT = 3;
  DISP_CLOSE = 5;
  DISP_ZOMBIE = 6;
  DISP_CLOSING = 7;

var
  LastId: WORD = 0; // used for ID packets
 
// Translate IP Address to MAC Address
function LookIp(IP: TIPAddress):PMachine;
var
  CPUID: LongInt;
  Machine: PMachine;
begin
  CPUID := GetApicid;
  Machine := DedicateNetworks[CPUID].TranslationTable;
  while Machine <> nil do
  begin
    if Machine.IpAddress = IP then
    begin
      Result := Machine;
      Exit;
    end else
      Machine := Machine.Next;
  end;
  Result := nil;
end;

// Add new entry in IP-MAC Table
procedure AddTranslateIp(IP: TIPAddress; const HardAddres: THardwareAddress);
var
  CPUID: LongInt;
  Machine: PMachine;
begin
  Machine := LookIp(Ip);
  CPUID := GetApicid;
  if Machine = nil then
  begin
    Machine := ToroGetMem(SizeOf(TMachine));
    Machine.IpAddress := Ip;
    Machine.HardAddress := HardAddres;
    Machine.Next := DedicateNetworks[CPUID].TranslationTable;
    DedicateNetworks[CPUID].TranslationTable := Machine;
  end;
end;

// Convert [192.168.1.11] to native IPAddress
procedure _IPAddress(const Ip: array of Byte; var Result: TIPAddress);
begin
  Result := (Ip[3] shl 24) or (Ip[2] shl 16) or (Ip[1] shl 8) or Ip[0];
end;

procedure _IPAddresstoArray(const Ip: TIPAddress; var Result: array of Byte);
begin
  Result[0] := Ip and $ff;
  Result[1] := (Ip and $ff00) shr 8;
  Result[2] := Ip and $ff0000 shr 16;
  Result[3] := Ip and $ff000000 shr 24;
end;

// The new network interface is enqued
procedure RegisterNetworkInterface(NetInterface: PNetworkInterface);
begin
  NetInterface.IncomingPackets := nil;
  NetInterface.OutgoingPackets := nil;
  NetInterface.Next := NetworkInterfaces;
  NetInterface.CPUID := -1;
  NetworkInterfaces := NetInterface;
end;

function SwapWORD(n: Word): Word; {$IFDEF INLINE}inline;{$ENDIF}
begin
  Result := ((n and $FF00) shr 8) or ((n and $FF) shl 8);
end;

function SwapDWORD(D: DWORD): DWORD;{$IFDEF INLINE}inline;{$ENDIF}
var
  r1, r2: packed array[1..4] of Byte;
begin
  Move(D, r1, 4);
  r2[1] := r1[4];
  r2[2] := r1[3];
  r2[3] := r1[2];
  r2[4] := r1[1];
  Move(r2, D, 4);
  SwapDWORD := D;
end;

// Return a Valid Checksum Code for IP Packet
function CalculateChecksum(pip: Pointer; data: Pointer; cnt, pipcnt: word): word;
var
  pw: ^Word;
  loop: word;
  x, w: word;
  csum: LongInt;
begin
  CalculateChecksum := 0;
  csum := 0;
  if cnt = 0 then
    Exit;
  loop := cnt shr 1;
  if pip <> nil then
  begin
    pw := pip;
    x := 1;
    while x <= PipCnt div 2 do
    begin
      csum := csum + pw^;
      inc(pw);
      Inc(x);
    end;
  end;
  pw := data;
  x := 1;
  while x <= loop do
  begin
    csum := csum + pw^;
    inc(pw);
    Inc(x);
  end;
  if (cnt mod 2 = 1) then
  begin
    w := PByte(pw)^;
    csum := csum + w;
  end;
  csum := (csum mod $10000) + (csum div $10000);
  csum := csum + (csum shr 16);
  Result := Word(not csum);
end;

type
  TPseudoHeader = packed record
    SourceIP: TIPAddress;
    TargetIP: TIPAddress;
    Cero: Byte;
    Protocol: Byte;
    TCPLen: WORD;
  end;

// Calculate CheckSum code for TCP Packet
function TCP_Checksum(SourceIP, DestIp: TIPAddress; PData: PChar; Len: Word): WORD;
var
  PseudoHeader: TPseudoHeader;
begin
  // Set-up the psueudo-header }
  FillChar(PseudoHeader, SizeOf(PseudoHeader), 0);
  PseudoHeader.SourceIP := SourceIP;
  PseudoHeader.TargetIP := DestIP;
  PseudoHeader.TCPLen := Swap(Word(Len));
  PseudoHeader.Cero := 0;
  PseudoHeader.Protocol := IP_TYPE_TCP;
  // Calculate the checksum }
  TCP_Checksum := CalculateChecksum(@PseudoHeader,PData,Len, SizeOf(PseudoHeader));
end;

// Validate new Packet to Local Socket
function ValidateTCP(IpSrc:TIPAddress;SrcPort,DestPort: Word): PSocket;
var
  Service: PNetworkService;
begin
  Service := DedicateNetworks[GetApicid].SocketStream[DestPort];
  if Service = nil then
  begin // there is no connection
    Result := nil;
    Exit;
  end;
  Result := Service.ClientSocket;
  while Result <> nil do
  begin // The TCP packet is for this connection ?
    if (Result.DestIp = IpSrc) and (Result.DestPort = SrcPort) and (Result.SourcePort = DestPort) then
      Exit
    else
      Result := Result.Next;
  end;
end;

// Set a TimeOut on Socket using the Dispatcher
procedure SetSocketTimeOut(Socket:PSocket;TimeOut:Int64); inline;
begin
  Socket.TimeOut:= TimeOut*LocalCPUSpeed*1000;
  Socket.Counter := read_rdtsc;
  Socket.DispatcherEvent := DISP_WAITING;
  {$IFDEF DebugSocket}WriteDebug('SetSocketTimeOut: timeout on Socket %h\n', [PtrUInt(Socket)]);{$ENDIF}
end;

procedure TCPSendPacket(Flags: LongInt; Socket: PSocket); forward;

// Enqueue Request for Connection to Local Socket
procedure EnqueueTCPRequest(Socket: PSocket; Packet: PPacket);
var
  Buffer: Pointer;
  ClientSocket: PSocket;
  EthHeader: PEthHeader;
  IPHeader: PIPHeader;
  LocalPort: Word;
  Service: PNetworkService;
  TCPHeader: PTCPHeader;
begin
  if Socket.State <> SCK_LISTENING then
  begin
    ToroFreeMem(Packet);
    Exit;
  end;
  EthHeader:= Packet.Data;
  IPHeader:= Pointer(PtrUInt(EthHeader) + SizeOf(TEthHeader));
  TCPHeader:= Pointer(PtrUInt(IPHeader) + SizeOf(TIPHeader));
  LocalPort:= SwapWORD(TCPHeader.DestPort);
  // We have the max number of request for connections
  if Socket.ConnectionsQueueLen = Socket.ConnectionsQueueCount then
  begin
    {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: Fail connection to %d Queue is complete\n', [LocalPort]);{$ENDIF}
    ToroFreeMem(Packet);
    Exit;
  end;
  // Information about Request Machine
  // Network Service Structure
  Service := DedicateNetworks[GetApicid].SocketStream[LocalPort];
  // Alloc memory for new socket
  ClientSocket := ToroGetMem(SizeOf(TSocket));
  if ClientSocket=nil then
  begin
   ToroFreeMem(Packet);
   {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: Fail connection to %d not memory\n', [LocalPort]);{$ENDIF}
   Exit;
  end;

  // Window Buffer for new Socket
  Buffer:= ToroGetMem(MAX_WINDOW);
  if Buffer= nil then
  begin
    ToroFreeMem(ClientSocket);
    ToroFreeMem(Packet);
    {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: Fail connection to %d not memory\n', [LocalPort]);{$ENDIF}
    Exit;
  end;
  // Create a new connection
  ClientSocket.State := SCK_NEGOTIATION;
  ClientSocket.BufferLength := 0;
  ClientSocket.Buffer := Buffer;
  ClientSocket.BufferReader := ClientSocket.Buffer;
  // Enqueue the socket to Network Service Structure
  ClientSocket.Next := Service.ClientSocket;
  Service.ClientSocket := ClientSocket;
  ClientSocket.SocketType := SOCKET_STREAM;
  ClientSocket.Mode := MODE_CLIENT;
  ClientSocket.SourcePort := Socket.SourcePort;
  ClientSocket.DestPort := SwapWORD(TcpHeader.SourcePort);
  ClientSocket.DestIp := IpHeader.SourceIP;
  ClientSocket.LastSequenceNumber := 300;
  ClientSocket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber)+1 ;
  ClientSocket.RemoteWinLen := SwapWORD(TCPHeader.Window_Size);
  ClientSocket.RemoteWinCount := ClientSocket.RemoteWinLen;
  ClientSocket.NeedFreePort := False;
  ClientSocket.AckTimeOUT := 0;
  ClientSocket.BufferSender := nil;
  ClientSocket.RemoteClose := false;
  // todo: to check if it is valid this 
  ClientSocket.AckFlag := true; 
  AddTranslateIp(IpHeader.SourceIp, EthHeader.Source);
  // we don't need the packet
  ToroFreeMem(Packet);
  // Increment the queue of new connections
  Socket.ConnectionsQueueCount := Socket.ConnectionsQueueCount+1;
  // Send the SYNACK confirmation
  // The socket waits in NEGOTIATION State for the confirmation with Remote ACK
  {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: sending SYNACK in Socket %h\n', [PtrUInt(Socket)]);{$ENDIF}
  TCPSendPacket(TCP_SYNACK, ClientSocket);
  SetSocketTimeOut(ClientSocket, WAIT_ACK);
  {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: New connection to Port %d\n', [LocalPort]);{$ENDIF}
end;

// Send a packet using the local Network interface
// It's an async API , the packet is send when "ready" register is True
procedure SysNetworkSend(Packet: PPacket);
var
  CPUID: LongInt;
  NetworkInterface: PNetworkInterface;
begin
  CPUID := GetApicID;
  NetworkInterface := DedicateNetworks[CPUID].NetworkInterface;
  Packet.Ready := False;
  Packet.Status := False;
  Packet.Next:= nil;
  {$IFDEF DebugNetwork}WriteDebug('SysNetworkSend: sending packet %h\n', [PtrUInt(Packet)]);{$ENDIF}
  NetworkInterface.Send(NetworkInterface, Packet);
end;

const
  ARP_OP_REQUEST = 1;
  ARP_OP_REPLY = 2;

// Send an ARP request to translate IP Address ---> Hard Address
procedure ARPRequest(IpAddress: TIPAddress);
const
  MACBroadcast: THardwareAddress = ($ff,$ff,$ff,$ff,$ff,$ff);
  MACZero: THardwareAddress = (0,0,0,0,0,0);
var
  Packet: PPacket;
  ARPPacket: PArpHeader;
  EthPacket: PEthHeader;
  CpuID: LongInt;
begin
  Packet := ToroGetMem(SizeOf(TPacket)+SizeOf(TArpHeader)+SizeOf(TEthHeader));
  if Packet = nil then
    Exit;
  CPUID:= GetApicid;
  Packet.Data := Pointer(PtrUInt(Packet)+SizeOf(TPacket));
  Packet.Size := SizeOf(TArpHeader)+SizeOf(TEthHeader);
  Packet.Delete := true; 
  ARPPacket := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  EthPacket := Packet.Data;
  ARPPacket.Hardware := SwapWORD(1);
  ARPPacket.Protocol := SwapWORD(ETH_FRAME_IP);
  ARPPacket.HardwareAddrLength := SizeOf(THardwareAddress);
  ARPPacket.ProtocolAddrLength := SizeOf(TIPAddress);
  ARPPacket.OpCode:= SwapWORD(ARP_OP_REQUEST);
  ARPPacket.TargetHardAddr := MACZero;
  ARPPacket.TargetIpAddr:= IpAddress;
  ARPPacket.SenderHardAddr:= DedicateNetworks[CpuID].NetworkInterface.HardAddress;
  ARPPacket.SenderIPAddr := DedicateNetworks[CpuID].IpAddress;
  // Sending a broadcast packet
  EthPacket.Destination := MACBroadcast;
  EthPacket.Source:= DedicateNetworks[CpuID].NetworkInterface.HardAddress;
  EthPacket.ProtocolType := SwapWORD(ETH_FRAME_ARP);
  SysNetworkSend(Packet);
  // free the resources
  //ToroFreeMem(Packet);
end;


// Return MAC of Local Stack TCP/IP
function GetLocalMAC: THardwareAddress;
begin
  result:= DedicateNetworks[GetApicid].NetworkInterface.HardAddress;
end;

// called by: EthernetSendPacket\RouteIP
function GetMacAddress(IP: TIPAddress): PMachine;
var
  Machine: PMachine;
  I: LongInt;
begin
  //  MAC not in local table -> send ARP request
  I := 3;
  while I > 0 do
  begin
    Machine := LookIp(IP); // MAC already added ?
    if Machine <> nil then
    begin
	  {$IFDEF DebugNetwork} WriteDebug('ARP: New mac added\n', []); {$ENDIF}
      Result:= Machine;
      Exit;
    end;
    ARPRequest(IP); // Request the MAC of IP
    Sleep(WAIT_ARP); // Wait for Remote Response
    Dec(I);
  end;
  Result := nil;
end;

// Return a physical Address to correct Destination
// called by: EthernetSendPacket
function RouteIP(IP: TIPAddress) : PMachine;
var
  CPUID: LongInt;
  Net: PNetworkDedicate;
begin
  CPUID:= GetApicid;
  Net := @DedicateNetworks[CPUID];
  if (Net.Mask and IP) <> (Net.Mask and Net.Gateway) then
  begin
    // The Machine is outside , i must use a Gateway
    Result := GetMacAddress(Net.Gateway);
    Exit;
  end;
  // The IP is in the Range i will send directly to the machine
  Result := GetMacAddress(IP);
end;

// Send a packet using low layer ethernet
procedure EthernetSendPacket(Packet: PPacket);
var
  CpuID: LongInt;
  EthHeader: PEthHeader;
  IPHeader: PIPHeader;
  Machine: PMachine;
begin
  CpuID := GetApicid;
  EthHeader := Packet.Data;
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  EthHeader.Source := DedicateNetworks[CpuID].NetworkInterface.HardAddress;
  Machine := RouteIP(IPHeader.destip);
  if Machine = nil then
    Exit;
  EthHeader.Destination := Machine.HardAddress;
  EthHeader.ProtocolType := SwapWORD(ETH_FRAME_IP);
  SysNetworkSend(Packet);
end;

// Make an IP Header for send a IP Packet
procedure IPSendPacket(Packet: PPacket; IpDest: TIPAddress; Protocol: Byte);
var
  IPHeader: PIPHeader;
begin
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  FillChar(IPHeader^, SizeOf(TIPHeader), 0);
  IPHeader.VerLen := IPv4_VERSION_LEN;
  IPHeader.TOS := 0;
  IPHeader.PacketLength := SwapWORD(Packet.Size-SizeOf(TEthHeader));
  Inc(LastId);
  IPHeader.ID := SwapWORD(Word(LastID));
  IPHeader.FragmentOfs := SwapWORD(0);
  IPHeader.ttl := 128;
  IPHeader.Protocol := Protocol;
  IPHeader.SourceIP := DedicateNetworks[GetApicid].IpAddress;
  IPHeader.DestIP := IpDest;
  IPHeader.Checksum := CalculateChecksum(nil,IPHeader,Word(SizeOf(TIPHeader)),0);
  // Send a packet using ethernet layer
  EthernetSendPacket(Packet);
end;

const
 TCPPacketLen : LongInt =  SizeOf(TPacket)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader);

// Uses for System Packets like SYN, ACK or END
procedure TCPSendPacket(Flags: LongInt; Socket: PSocket);
var
  TCPHeader: PTCPHeader;
  Packet: PPacket;
begin
  Packet:= ToroGetMem(TCPPacketLen);
  if Packet = nil then
    Exit;
  Packet.Size := TCPPacketLen - SizeOf(TPacket);
  Packet.Data := Pointer(PtrUInt(Packet) + TCPPacketLen - SizeOf(TPacket));
  Packet.ready := False;
  Packet.Status := False;
  Packet.Delete := True;
  Packet.Next := nil;
  TcpHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
  FillChar(TCPHeader^, SizeOf(TTCPHeader), 0);
  {$IFDEF DebugNetwork}WriteDebug('TCPSendPacket: filling %h count: %d\n', [PtrUInt(TcpHeader), SizeOf(TTCPHeader) ]);{$ENDIF}
  TcpHeader.AckNumber := SwapDWORD(Socket.LastAckNumber);
  TcpHeader.SequenceNumber := SwapDWORD(Socket.LastSequenceNumber);
  TcpHeader.Flags := Flags;
  TcpHeader.Header_Length := (SizeOf(TTCPHeader) div 4) shl 4;
  TcpHeader.SourcePort := SwapWORD(Socket.SourcePort);
  TcpHeader.DestPort := SwapWORD(Socket.DestPort);
  TcpHeader.Window_Size := SwapWORD(MAX_WINDOW - Socket.BufferLength);
  TcpHeader.Checksum := TCP_CheckSum(DedicateNetworks[GetApicid].IpAddress, Socket.DestIp, PChar(TCPHeader), SizeOf(TTCPHeader));
  IPSendPacket(Packet, Socket.DestIp, IP_TYPE_TCP);
  // Sequence Number depends of the flags in the TCP Header
  if (Socket.State = SCK_NEGOTIATION) or (Socket.State = SCK_CONNECTING) or (Socket.State= SCK_LOCALCLOSING) or (Socket.State = SCK_PEER_DISCONNECTED) then
    Inc(Socket.LastSequenceNumber)
  else if Socket.State = SCK_TRANSMITTING then
  begin
//    Socket.LastSequenceNumber := Socket.LastSequenceNumber;
  end;
  {$IFDEF DebugNetwork}WriteDebug('TCPSendPacket: sending TCP packet for Socket %h\n', [PtrUInt(Socket)]);{$ENDIF}
end;

// Inform the Kernel that the last packet has been sent, returns the next packet to send
function DequeueOutgoingPacket: PPacket;
var
  CPUID: LongInt;
  Packet: PPacket;
begin
  CPUID := GetApicid;
  Packet := DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets;
  // wrong alarm, the queue is empty
  If Packet = nil then
  begin
    WriteConsole('Network: /RNull packet/n sent\n',[]);
    result := nil;
    exit;
  end;
  DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets := Packet.Next;
  DedicateNetworks[CPUID].NetworkInterface.TimeStamp := read_rdtsc;
  // the packet must be delete
  if Packet.Delete then
  begin
	{$IFDEF DebugNetwork}WriteDebug('DequeueOutgoingPacket: Freeing packet %h\n', [PtrUInt(Packet)]);{$ENDIF}
	ToroFreeMem(Packet);
  end;
  // someone is waiting for this packet
  Packet.Ready := True;
  Result := DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets;
end;

// Inform to Kernel that a new Packet has been received
// This has to be invoked by disabling interruption to prevent concurrent access
procedure EnqueueIncomingPacket(Packet: PPacket);
var
  PacketQueue: PPacket;
begin
  {$IFDEF DebugNetwork}WriteDebug('EnqueueIncomingPacket: new packet: %h\n', [PtrUInt(Packet)]); {$ENDIF} 
  PacketQueue := DedicateNetworks[GetApicId].NetworkInterface.IncomingPackets;
  Packet.Next := nil;
  if PacketQueue = nil then
  begin
    DedicateNetworks[GetApicId].NetworkInterface.IncomingPackets:=Packet;
  end else begin
	// we have packets in the tail
    while PacketQueue.Next <> nil do
	 PacketQueue := PacketQueue.Next;
    PacketQueue.Next := Packet;
  end;
end;

// Port is marked free in Local Socket Bitmap
// Called by FreeSocket
procedure FreePort(LocalPort: LongInt);
var
  CPUID: LongInt;
  Bitmap: Pointer;
begin
  CPUID:= GetApicid;
  Bitmap := @DedicateNetworks[CPUID].SocketStreamBitmap[0];
  Bit_Reset(Bitmap, LocalPort);
end;

// Free all Resources in Socket
// only for Client Sockets
procedure FreeSocket(Socket: PSocket);
var
  ClientSocket: PSocket;
  CPUID: LongInt;
  Service: PNetworkService;
begin
  CPUID:= GetApicID;
  // take the queue of Sockets
  Service := DedicateNetworks[CPUID].SocketStream[Socket.SourcePort];
  // Remove It
  if Service.ClientSocket = Socket then
    Service.ClientSocket := Socket.Next
  else begin
    ClientSocket := Service.ClientSocket;
    while ClientSocket.Next <> Socket do
      ClientSocket := ClientSocket.Next;
    ClientSocket.Next := Socket.Next;
  end;
  // Free port if is necessary
  if Socket.NeedFreePort then
  begin
    if Socket.SocketType = SOCKET_STREAM then
      DedicateNetworks[CPUID].SocketStream[Socket.SourcePort] := nil
    else
      DedicateNetworks[CPUID].SocketDatagram[Socket.SourcePort] := nil;
    FreePort(Socket.SourcePort);
  end;
  {$IFDEF DebugSocket} WriteDebug('FreeSocket: Freeing Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
  // Free Memory Allocated
  ToroFreeMem(Socket.Buffer); // Free the buffer Window
  ToroFreeMem(Socket); // Free Socket Structure 
end;

// Processing ARP Packets
procedure ProcessARPPacket(Packet: PPacket);
var
  CPUID: LongInt;
  ArpPacket: PArpHeader;
  EthPacket: PEthHeader;
begin
  CPUID:= GetApicid;
  ArpPacket:=Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  EthPacket:= Packet.Data;
  if SwapWORD(ArpPacket.Protocol) = ETH_FRAME_IP then
  begin
    if ArpPacket.TargetIpAddr=DedicateNetworks[CPUID].IpAddress then
    begin
      // remote host is requesting my IP
      if ArpPacket.OpCode= SwapWORD(ARP_OP_REQUEST) then
      begin
        EthPacket.Destination:= EthPacket.Source;
        EthPacket.Source:= DedicateNetworks[CPUID].NetworkInterface.HardAddress;
        ArpPacket.OpCode:= SwapWORD(ARP_OP_REPLY);
        ArpPacket.TargetHardAddr:= ArpPacket.SenderHardAddr;
        ArpPacket.TargetIpAddr:= ArpPacket.SenderIpAddr;
        ArpPacket.SenderHardAddr:= DedicateNetworks[CPUID].NetworkInterface.HardAddress;
        ArpPacket.SenderIpAddr:=DedicateNetworks[CPUID].IpAddress;
        // the packet doesn't care, cause SysNetworkSend is async, I mark it as deletable
        Packet.Delete := true;
		{$IFDEF DebugNetwork} WriteDebug('ProcessARPPacket: Sending my ip\n', []); {$ENDIF}
        SysNetworkSend(Packet);
        // reply Request of Ip Address
      end else if ArpPacket.OpCode= SwapWORD(ARP_OP_REPLY) then
      begin
        {$IFDEF DebugNetwork} WriteDebug('ProcessARPPacket: New Machine added to Translation Table\n', []); {$ENDIF}
        // some problems for Spoofing
        AddTranslateIp(ArpPacket.SenderIPAddr,ArpPacket.SenderHardAddr);
        ToroFreeMem(Packet);
      end;
    end else ToroFreeMem(Packet);
  end else ToroFreeMem(Packet);
end;

// Check the Socket State and enqueue the packet in correct queue
procedure ProcessTCPSocket(Socket: PSocket; Packet: PPacket);
var
  TCPHeader: PTCPHeader;
  IPHeader: PIPHeader;
  DataSize: UInt32;
  Source, Dest: PByte;
begin
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TETHHeader));
  TCPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TETHHeader)+SizeOf(TIPHeader));
//  DataSize := SwapWord(IPHeader.PacketLength)-SizeOf(TIPHeader)-SizeOf(TTCPHeader);
  {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h Packet %h\n', [PtrUInt(Socket),  PtrUInt(Packet)]); {$ENDIF}
  case Socket.State of
    SCK_CONNECTING: // The socket is connecting to remote host
      begin
        // It is a valid connection ?
        if (Socket.Mode = MODE_CLIENT) and (TCPHeader.Flags and TCP_SYN = TCP_SYN) then
        begin
          // Is a valid packet?
          if SwapDWORD(TCPHeader.AckNumber)-1 = 300 then
          begin
            // The connection was stablished
            Socket.DispatcherEvent := DISP_CONNECT;
            Socket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber)+1;
            Socket.LastSequenceNumber := 301;
            Socket.RemoteWinLen := SwapWORD(TCPHeader.Window_Size);
            Socket.RemoteWinCount :=Socket.RemoteWinLen;
            Socket.State := SCK_TRANSMITTING;
            Socket.BufferLength := 0;
            Socket.Buffer := ToroGetMem(MAX_WINDOW);
            Socket.BufferReader := Socket.Buffer;
			{$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h sending ACK for confirmation\n', [PtrUInt(Socket)]); {$ENDIF}
            // Confirm the connection sending a ACK
            TCPSendPacket(TCP_ACK, Socket);
          end;
        end;
        ToroFreeMem(Packet);
      end;
    SCK_PEER_DISCONNECTED:
      begin
		// we sent ENDACK, we wait for a ACK 
		if TCPHeader.flags = TCP_ACK then
		begin
			if Socket.RemoteClose then 
			begin
				FreeSocket(Socket);
				{$IFDEF DebugNetwork}WriteDebug('ProcessTCPSocket: ACK confirmed and RemoteClose so freeing Socket %h\n', [PtrUInt(Socket)]);{$ENDIF}
			end 
			else begin
			    Socket.AckFlag := True;
				Socket.DispatcherEvent := DISP_ZOMBIE;
				{$IFDEF DebugNetwork}WriteDebug('ProcessTCPSocket: ACK confirmed, waiting for FINACK %h\n', [PtrUInt(Socket)]);{$ENDIF}
			end;
		end else if (TCPHeader.flags and TCP_FIN) = TCP_FIN then
		begin
				Socket.LastAckNumber := Socket.LastAckNumber+1;
				TCPSendPacket(TCP_ACK, Socket);
				{$IFDEF DebugNetwork}WriteDebug('ProcessTCPSocket: FINACK confirmed free Socket %h\n', [PtrUInt(Socket)]);{$ENDIF}
				FreeSocket(Socket);
		end;
        ToroFreeMem(Packet);
      end;
    //SCK_LOCALCLOSING: // The Local user is closing the connection
    //  begin
    //    // we have to wait the REMOTECLOSE
        // we have to wait a FINACK
	//	{$IFDEF DebugNetwork} 
	//	    if TCPHeader.flags = TCP_ACK then
	//		begin
	///			WriteDebug('ProcessTCPSocket: ACK packet in LOCALCLOSING state Socket %h\n', [PtrUInt(Socket)]);
	//		end;
	//	{$ENDIF}
    //    Socket.State := SCK_PEER_DISCONNECTED;
    //    SetSocketTimeOut(Socket,WAIT_ACKFIN);
    //    ToroFreeMem(Packet);
    //  end;
    SCK_BLOCKED: // Server Socket is not listening remote connections
      begin
        ToroFreeMem(Packet)
      end;
    SCK_NEGOTIATION: // Socket is waiting for remote ACK confirmation
      begin
        // the connection has been established
        // The socket starts to receive data, Service Thread has got to do a SysSocketAccept()
        Socket.State := SCK_TRANSMITTING;
        Socket.DispatcherEvent := DISP_ACCEPT;
		{$IFDEF DebugNetwork}WriteDebug('ProcessTCPSocket: Socket %h in DISP_ACCEPT\n', [PtrUInt(Socket)]);{$ENDIF}
        ToroFreeMem(Packet);
      end;
    SCK_TRANSMITTING: // Client Socket is connected to remote Host
      begin
      // TODO: we aren't checking if ACK number is correct
       if TCPHeader.flags = TCP_ACK then
       begin
        Socket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber);
		Socket.AckFlag := True;
		{$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: received ACK on Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
        // TODO: to implement zero window condition check
		//
		// Are we checking zero window condition ?
		//if Socket.WinFlag then
        //begin
          // The window was refreshed
          //if SwapWord(TCPHeader.Window_Size) <> 0 then
          //  Socket.WinFlag := False;
          //Socket.WinFlag := SwapWord(TCPHeader.Window_Size) = 0; // KW 20091204 Reduced previous line of code as suggested by PAL
		 // {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: ignored ASK for Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
        //end else
        //begin
         // Sender Dispatcher is waiting for confirmation
        // Socket.AckFlag := True;
         // We have got to block the sender
         //if SwapWord(TCPHeader.Window_Size) = 0 then
         // Socket.WinFlag := True;
        //end;
       end else if TCPHeader.flags = TCP_ACKPSH then
       begin
          if SwapDWORD(TCPHeader.AckNumber) = Socket.LastSequenceNumber then
          begin
            DataSize:= SwapWord(IPHeader.PacketLength)-SizeOf(TIPHeader)-SizeOf(TTCPHeader);
            Socket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber)+DataSize;
            Source := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTCPHeader));
            Dest := Pointer(PtrUInt(Socket.Buffer)+Socket.BufferLength);
            Move(Source^, Dest^, DataSize);
			{$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Moving from %h to %h count: %d\n', [PtrUInt(Source),PtrUInt(Dest),DataSize]); {$ENDIF}
            Socket.BufferLength := Socket.BufferLength + DataSize;
			// We switch the state only if the dispatcher is waiting for an event 
            if (Socket.DispatcherEvent <> DISP_CLOSING) and (Socket.DispatcherEvent <> DISP_ZOMBIE) and (Socket.DispatcherEvent <> DISP_ACCEPT) then
			begin
				Socket.DispatcherEvent := DISP_RECEIVE;
				{$IFDEF DebugNetwork}WriteDebug('ProcessTCPSocket: Socket %h in DISP_RECEIVE\n', [PtrUInt(Socket)]);{$ENDIF}
			end;
            // we confirm the ACKPSH
            TCPSendPacket(TCP_ACK, Socket);
			{$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h sending ACK\n', [PtrUInt(Socket)]); {$ENDIF}
          end else begin
            // Invalid Sequence Number
            // sending the correct ACK and Sequence Number
            TCPSendPacket(TCP_ACK, Socket);
			{$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h sending ACK for invalid seq\n', [PtrUInt(Socket)]); {$ENDIF}
          end;
        // END of connection
        end else if (TCPHeader.flags = TCP_ACKEND) then
        begin
		  {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h received ACKFIN\n', [PtrUInt(Socket)]); {$ENDIF}
		  // we confirm the end of connection 
		  Socket.LastAckNumber := Socket.LastAckNumber+1;
		  TCPSendPacket(TCP_ACK, Socket);
		  // the dispatcher will run the close event 
		  Socket.DispatcherEvent := DISP_CLOSE;
		  // remote host closed the conection 
		  Socket.RemoteClose := true; 
		  {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h sending ACK\n', [PtrUInt(Socket)]); {$ENDIF}
        end;
        ToroFreeMem(Packet)
      end;
  end;
end;

// Validate Request to SERVER Socket
// Called by ProcessNetworksPackets\ProcessIPPacket
function ValidateTCPRequest(IpSrc: TIPAddress; LocalPort, RemotePort: Word): PSocket;
var
  Service: PNetworkService;
  Socket: PSocket;
begin
  {$IFDEF DebugNetwork} WriteDebug('ValidateTCPRequest: SYN to local port %d\n', [LocalPort]); {$ENDIF}
  Result := nil;
  Service := DedicateNetworks[GetApicid].SocketStream[LocalPort];
  if Service = nil then 
  begin 
	{$IFDEF DebugNetwork} WriteDebug('ValidateTCPRequest: no service on port %d\n', [LocalPort]); {$ENDIF}
    Exit;
  end;
  if Service.ServerSocket = nil then
  begin
    {$IFDEF DebugNetwork} WriteDebug('ValidateTCPRequest: no service listening on port %d\n', [LocalPort]); {$ENDIF}
    Exit;
  end;
    Socket:= Service.ClientSocket;
    // Is it an duplicate connection ?
    while Socket <> nil do
    begin
      if (Socket.DestIP = IPSrc) and (Socket.DestPort = RemotePort) then
      begin
	    {$IFDEF DebugNetwork} WriteDebug('ValidateTCPRequest: duplicate connection on local port %d\n', [LocalPort]); {$ENDIF}
        Exit;
    end else
      Socket:= Socket.Next;
    end;
	{$IFDEF DebugNetwork} WriteDebug('ValidateTCPRequest: SYN to local port %d OK, ServerSocket %h\n', [LocalPort, PtrUInt(Service.ServerSocket)]); {$ENDIF}
    Result := Service.ServerSocket;
end;


const
  ICMPPacketLen = SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TICMPHeader) + sizeof(TPacket);

// Send a ECHO Request
function ICMPSendEcho(IpDest: TIPAddress; Data: Pointer; len: longint; seq, id: word): longint;
var
  Packet: PPacket;
  ICMPHeader: PICMPHeader;
  Mac: PMachine;
  PData: Pointer;
  DataLen: longint;
begin
   // I get the mac from the ip
   Mac := GetMacAddress(IpDest);
   if (Mac = nil) then
   begin
    Result := 1;
    exit;
   end;
   // I get memory for the whole packet plus data
   Packet := ToroGetMem(ICMPPacketLen + len);
   If Packet=nil then
   begin
     Result := 1;
    exit;
   end;
   Packet.Data := Pointer(PtrUInt(Packet) + sizeof(TPacket));
   Packet.ready := False;
   Packet.Status := False;
   // the packet memory is free after sent
   Packet.Delete := True;
   Packet.Next := nil;
   Packet.size := ICMPPacketLen + len - sizeof(TPacket);
   ICMPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
   ICMPHeader.tipe:= ICMP_ECHO_REQUEST;
   ICMPHeader.checksum :=0 ;
   ICMPHeader.seq:=  SwapWORD(seq);
   ICMPHeader.code:= 0;
   ICMPHeader.id:= SwapWORD(id); 
   Datalen:= len + sizeof(TICMPHeader);
   PData := Pointer(PtrUInt(Packet.Data) + ICMPPacketLen - sizeof(TPacket));
   Move(Data^, PData^, len);
   ICMPHeader.Checksum := CalculateChecksum(nil,ICMPHeader,DataLen,0);
   // the packet is sent
   IPSendPacket(Packet,IPDest,IP_TYPE_ICMP); 
   // we exit sucessfully 
   Result := 0;
end;

// this points to the last ICMP packet received
var
	ICMPPollerBuffer: PPacket = nil; 

// wait for a ICMP packet and returns when it arrives
// it returns a packet that the user has to free
function ICMPPoolPackets: PPacket;
begin
  if ICMPPollerBuffer = nil then 
   sleep(WAIT_ICMP);
  result := ICMPPollerBuffer;
  ICMPPollerBuffer := nil;
end;	
	
// Manipulation of IP Packets, redirect the traffic to Sockets structures
// Called by ProcessNetworksPackets
procedure ProcessIPPacket(Packet: PPacket);
var
  IPHeader: PIPHeader;
  TCPHeader: PTCPHeader;
  Socket: PSocket;
  ICMPHeader: PICMPHeader;
  EthHeader: PEthHeader;
  DataLen: LongInt;
begin
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  case IPHeader.protocol of
    IP_TYPE_ICMP :
      begin
        ICMPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
        EthHeader := Packet.Data;
        // Request of Ping
        if ICMPHeader.tipe = ICMP_ECHO_REQUEST then
        begin
          Packet.Size := Packet.Size - 4;
		  // the kernel is in charge to free the packet
          Packet.Delete := true;
		  ICMPHeader.tipe:= ICMP_ECHO_REPLY;
          ICMPHeader.checksum:= 0 ;
          Datalen:= SwapWORD(IPHeader.PacketLength) - SizeOf(TIPHeader);
          ICMPHeader.Checksum := CalculateChecksum(nil,ICMPHeader,DataLen,0);
          AddTranslateIp(IPHeader.SourceIP,EthHeader.Source); // I'll use a MAC address of Packet
          IPSendPacket(Packet,IPHeader.SourceIP,IP_TYPE_ICMP); // sending response
		  {$IFDEF DebugNetwork} WriteDebug('icmp: ECHO REQUEST answered\n', []); {$ENDIF}
        // Ping reply 
		end else if ICMPHeader.tipe = ICMP_ECHO_REPLY then
		begin
		 	// we only enqueue the packet if it has been read 
		    if ICMPPollerBuffer = nil then 
			 ICMPPollerBuffer := Packet 
			// otherwise, we free the packet
			else ToroFreeMem(Packet);
			{$IFDEF DebugNetwork} WriteDebug('icmp: received ECHO REPLY\n', []); {$ENDIF}
		// unknow packets are just freed 
		end else ToroFreeMem(Packet);
      end;
    IP_TYPE_UDP:
      begin
        {$IFDEF DebugNetwork} WriteDebug('ip: received UDP packet %h\n', [PtrUInt(Packet)]); {$ENDIF}
        ToroFreeMem(Packet);
      end;
    IP_TYPE_TCP:
      begin
        TCPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
        {$IFDEF DebugNetwork} WriteDebug('ip: received tcp packet %h\n', [PtrUInt(Packet)]); {$ENDIF}
		if TCPHeader.Flags=TCP_SYN then
        begin
		  {$IFDEF DebugNetwork} WriteDebug('ip: received TCP_SYN packet %h\n', [PtrUInt(Packet)]); {$ENDIF}
          // Validate the REQUEST to Server Socket
          Socket:= ValidateTCPRequest(IPHeader.SourceIP,SwapWORD(TCPHeader.DestPort),SwapWORD(TCPHeader.SourcePort));
          // Enqueue the request to socket
          if Socket <> nil then
		  begin 
            {$IFDEF DebugNetwork} WriteDebug('ip: SYNC packet %h to port: %d\n', [PtrUInt(Packet), Socket.SourcePORT]); {$ENDIF}
			EnqueueTCPRequest(Socket, Packet);
		  end else
		    begin
				{$IFDEF DebugNetwork} WriteDebug('ip: SYNC packet invalid\n', [PtrUInt(Packet)]); {$ENDIF}
				ToroFreeMem(Packet);
			end;
        end else if (TCPHeader.Flags and TCP_ACK = TCP_ACK) then
        begin
          // Validate connection
          Socket:= ValidateTCP(IPHeader.SourceIP,SwapWORD(TCPHeader.SourcePort),SwapWORD(TCPHeader.DestPort));
          if Socket <> nil then
		  begin
		    {$IFDEF DebugNetwork} WriteDebug('ip: ACK packet %h to port: %d\n', [PtrUInt(Packet), Socket.SourcePORT]); {$ENDIF}
            ProcessTCPSocket(Socket,Packet);
		  end 
          else begin
            {$IFDEF DebugNetwork} WriteDebug('ip: ACK packet %h invalid\n', [PtrUInt(Packet)]); {$ENDIF}
            ToroFreeMem(Packet);
          end;
          // RST Flags
        end else if (TCPHeader.Flags and TCP_RST = TCP_RST) then
        begin
          Socket:= ValidateTCP(IPHeader.SourceIP,SwapWORD(TCPHeader.SourcePort),SwapWORD(TCPHeader.DestPort));
          // If the conection exist then socket is closed
          // If socket is in connecting to remote host the packet is not important for connection
          if (Socket <> nil) and (Socket.State <> SCK_CONNECTING) then
            Socket.State:= SCK_CLOSED;
          ToroFreeMem(Packet);
        end;
      end;
    else begin
      // Unknow Protocol
      ToroFreeMem(Packet);
    end;
  end;
end;

// Read a packet from Buffer of local Network Interface
// Need to protect call against concurrent access
// Called by ProcessNetworksPackets
function SysNetworkRead: PPacket;
var
  CPUID: LongInt;
  Packet: PPacket;
begin
  CPUID := GetApicID;
  DisableInt;
  Packet := DedicateNetworks[CPUID].NetworkInterface.IncomingPackets;
  if Packet=nil then
    Result := nil
  else begin
    DedicateNetworks[CPUID].NetworkInterface.IncomingPackets := Packet.Next;
	Packet.Next := nil;
    Result := Packet;
	{$IFDEF DebugNetwork}WriteDebug('SysNetworkRead: getting packet: %h\n', [PtrUInt(Packet)]); {$ENDIF}
  end;
  RestoreInt;
end;

// Thread function, processing new packets
function ProcessNetworksPackets(Param: Pointer): PtrInt;
var
  Packet: PPacket;
  EthPacket: PEthHeader;
  //r: Int64;
  //Net: PNetworkInterface;
  //CPUID: longint;
begin
  {$IFDEF FPC} Result := 0; {$ENDIF}
  //CPUID := GetApicid;
  // network driver initialization
  //Net := DedicateNetworks[CPUID].NetworkInterface;
  while True do
  begin
    // new packet read
    // and new block of memory is allocated if packet <> the nil
    Packet := SysNetworkRead;
    if Packet = nil then
    begin
	// TODO: Re think how to implement this
    //  if (Net.TimeStamp <> 0) and (Net.OutgoingPackets <> nil) then
    //  begin
    //    r := read_rdtsc-Net.TimeStamp;
        // Maybe the driver is in a loop, we have to inform the driver
    //    if (r > MAX_TIME_SENDER*LocalCPUSpeed*1000) then
    //      Net.Reset(Net);
    //  end;
      SysThreadSwitch;
      Continue;
    end;
    EthPacket := Packet.Data;
    case SwapWORD(EthPacket.ProtocolType) of
      ETH_FRAME_ARP:
        begin
        {$IFDEF DebugNetwork} WriteDebug('ethernet: new ARP packet %h\n', [PtrUInt(Packet)]); {$ENDIF}
          ProcessARPPacket(Packet);
        end;
      ETH_FRAME_IP:
        begin
          {$IFDEF DebugNetwork} WriteDebug('ethernet: new IP packet %h\n', [PtrUInt(Packet)]); {$ENDIF}
          ProcessIPPacket(Packet);
        end;
    else
      begin
        {$IFDEF DebugNetwork} WriteDebug('ethernet: new unknow packet %h freeing\n', [PtrUInt(Packet)]); {$ENDIF}
        ToroFreeMem(Packet);
      end;
    end;
  end;
end;

// Initialization of threads running like services on current CPU
procedure NetworkServicesInit;
var
  ThreadID: TThreadID;
begin
  if PtrUInt(BeginThread(nil, 10*1024, @ProcessNetworksPackets, nil, DWORD(-1), ThreadID)) <> 0 then
    WriteConsole('Networks Packets Service .... Thread: %d\n',[ThreadID])
  else
    WriteConsole('Networks Packets Service .... /VFailed!/n\n',[]);
end;

// Initialize the dedicated network interface
function LocalNetworkInit: Boolean;
var
  I, CPUID: LongInt;
begin
  CPUID := GetApicid;
  // cleaning  packet queue
  DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets := nil;
  DedicateNetworks[CPUID].NetworkInterface.IncomingPackets := nil;
  // initilization of Services for Packets Manipulation
  NetworkServicesInit;
  // driver internal initilization
  DedicateNetworks[CPUID].NetworkInterface.start(DedicateNetworks[CPUID].NetworkInterface);
  // cleaning the Socket table
  for I:= 0 to (MAX_SocketPORTS-1) do
  begin
    DedicateNetworks[CPUID].SocketStream[I]:=nil;
    DedicateNetworks[CPUID].SocketDatagram[I]:=nil;
  end;
  // the drivers is sending and receiving packets
  Result:= True;
end;

// Dedicate the Network Interface to CPU in CPUID
// If Handler=nil then the Network Stack is managed by the KERNEL
//
procedure DedicateNetwork(const Name: AnsiString; const IP, Gateway, Mask: array of Byte; Handler: TThreadFunc);
var
  Net: PNetworkInterface;
  Network: PNetworkDedicate;
  ThreadID: TThreadID;
  CPUID: Longint;
begin
  Net := NetworkInterfaces;
  CPUID:= GetApicid;
  {$IFDEF DebugNetwork} WriteDebug('DedicateNetwork: dedicating on CPU#d\n', [CPUID]); {$ENDIF}
  while Net <> nil do
  begin
    if (Net.Name = Name) and (Net.CPUID = -1) and (DedicateNetworks[CPUID].NetworkInterface = nil) then
    begin
      // Only this CPU will be granted access to this network interface
      Net.CPUID := CPUID;
      DedicateNetworks[CPUID].NetworkInterface := Net;
      // The User Hands the packets
      if @Handler <> nil then
      begin
        if PtrUInt(BeginThread(nil, 10*1024, @Handler, nil, DWORD(-1), ThreadID)) <> 0 then
          WriteConsole('Network Packets Service .... Thread %d\n',[ThreadID])
        else
        begin
          WriteConsole('Network Packets Service .... /RFail!/n\n',[]);
          exit;
        end;
      end else
      begin // Initialize Local Packet-Cache, the kernel will handle packets
        if not LocalNetworkInit then
        begin
          DedicateNetworks[CPUID].NetworkInterface := nil;
          Exit;
        end;
      end;
      // Loading the IP address
      // some translation from array of Byte to LongInt
      Network := @DedicateNetworks[CPUID];
      _IPAddress(IP, Network.IpAddress);
      _IPAddress(Gateway, Network.Gateway);
      _IPAddress(Mask, Network.Mask);
      WriteConsole('Network configuration :\n', []);
      WriteConsole('Local IP  ... /V%d.%d.%d.%d\n', [Network.Ipaddress and $ff,
	  (Network.Ipaddress shr 8) and $ff, (Network.Ipaddress shr 16) and $ff, (Network.Ipaddress shr 24) and $ff ]);
      WriteConsole('/nGateway   ... /V%d.%d.%d.%d\n', [Network.Gateway and $ff,
	  (Network.Gateway shr 8) and $ff, (Network.Gateway shr 16) and $ff, (Network.Gateway shr 24) and $ff ]);
	  WriteConsole('/nMask      ... /V%d.%d.%d.%d/n\n', [Network.Mask and $ff,
	  (Network.Mask shr 8) and $ff, (Network.Mask shr 16) and $ff, (Network.Mask shr 24) and $ff ]);
      {$IFDEF DebugNetwork} WriteDebug('DedicateNetwork: New Driver dedicated to CPU#%d\n', [CPUID]); {$ENDIF}
      Exit;
    end;
    Net := Net.Next;
  end;
  {$IFDEF DebugNetwork} WriteDebug('DedicateNetwork: fail, driver not found\n', []); {$ENDIF}
end;

// Initilization of Network structures
procedure NetworkInit;
var
  I: LongInt;
begin
  WriteConsole('Loading Network Stack ...\n',[]);
  // Clean tables
  for I := 0 to (MAX_CPU-1) do
  begin
    DedicateNetworks[I].NetworkInterface := nil;
    DedicateNetworks[I].TranslationTable := nil;
    // Free all ports
    FillChar(DedicateNetworks[I].SocketStreamBitmap, SZ_SocketBitmap, 0);
    FillChar(DedicateNetworks[I].SocketDatagram, MAX_SocketPORTS*SizeOf(Pointer), 0);
    FillChar(DedicateNetworks[I].SocketStream, MAX_SocketPORTS*SizeOf(Pointer), 0);
  end;
end;



//------------------------------------------------------------------------------
// Socket Implementation
//------------------------------------------------------------------------------

// Return True if the Timer expired
function CheckTimeOut(Counter, TimeOut: Int64): Boolean;
var
  ResumeTime: Int64;
begin
  ResumeTime := read_rdtsc;
  // Correction for Overflow
  if Counter < ResumeTime then
    Counter := Counter - ResumeTime
  else
    Counter := $FFFFFFFF-Counter+ResumeTime;
  if TimeOut < Counter then
    Result := True
  else
    Result := False;
end;

// Send the packets prepared in Buffer
procedure DispatcherFlushPacket(Socket: PSocket);
var
  Buffer: PBufferSender;
  DataLen: UInt32;
begin
  {$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: flushing on Socket: %h\n', [PtrUInt(Socket)]); {$ENDIF} 
  // sender Dispatcher can't send, we have to wait for remote host
  // while The WinFlag is up the timer 'll be refreshed
  if not (Socket.AckFlag) {and Socket.WinFlag} then
  begin
    // todo: to implement this correctly 
    //if CheckTimeOut(Socket.WinCounter, Socket.WinTimeOut) then
   // begin
	//  {$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: checking if remote windows was refreshed , Socket %h\n', [PtrUInt(Socket)]); {$ENDIF} 
      // we have to check if the remote window was refreshed
   //   TCPSendPacket(TCP_ACK, Socket);
      // set the timer again
   //   Socket.WinCounter := read_rdtsc;
   //   Socket.WinTimeOut := WAIT_WIN*LocalCPUSpeed*1000;
	//  {$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: checking if remote windows was refreshed , Socket %h\n', [PtrUInt(Socket)]); {$ENDIF} 
  //  end;
  	{$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: Socket %h ACK Flag is FALSE\n', [PtrUInt(Socket)]); {$ENDIF} 
    Exit;
  end;
  // the socket doesn't have packets to send
  if Socket.BufferSender = nil then
    Exit;
  // we are waiting for finishing an operation ?
  if Socket.AckTimeOUT <> 0 then
  begin
    Buffer := Socket.BufferSender;
    if Socket.AckFlag then
    begin // the packet has been sent correctly
	  {$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: Socket %h Packet %h correctly sent\n', [PtrUInt(Socket),PtrUInt(Buffer.Packet)]); {$ENDIF}
      Socket.AckFlag := False; // clear the flag
      Socket.AckTimeOut:= 0;
      DataLen := Buffer.Packet.Size - (SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader));
      Buffer := Socket.BufferSender.NextBuffer;
      ToroFreeMem(Socket.BufferSender.Packet); // Free the packet
      ToroFreeMem(Socket.BufferSender); // Free the Buffer
      Socket.LastSequenceNumber := Socket.LastSequenceNumber+DataLen;
      // preparing the next packet to send
      Socket.BufferSender := Buffer;
      //if Socket.WinFlag then
      //begin
      //  Socket.WinCounter := read_rdtsc;
      //  Socket.WinTimeOut := WAIT_WIN*LocalCPUSpeed*1000;
      //  Exit;
      //end;
      if Buffer = nil then
        Exit; // no more packet
    end else
    begin
      // TimeOut expired ?
      if not CheckTimeOut(Socket.BufferSender.Counter,Socket.AckTimeOut) then
	  begin
	    {$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: CheckTimeOut exiting Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
        Exit;
	  end;
      // Hardware problem !!!
      // we need to re-calculate the RDTSC register counter
      // the timer will be recalculated until the packet has been sent
      // The packet is still queued in Network Buffer
      if not(Socket.BufferSender.Packet.Ready) then
      begin
        Socket.BufferSender.Counter := read_rdtsc;
        Exit;
      end;
      // number of attemps
      if Buffer.Attempts = 0 then
      begin
        // We lost the connection
        Socket.State := SCK_BLOCKED ;
        Socket.AckTimeOut := 0;
        // We have to CLOSE
        Socket.DispatcherEvent := DISP_CLOSE ;
		{$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: 0 attemps Socket %h in state BLOCKED\n', [PtrUInt(Socket)]); {$ENDIF}
      end else
        Dec(Buffer.Attempts);
    end;
  end;
  Socket.ACKFlag := False;
  Socket.AckTimeOut := WAIT_ACK*LocalCPUSpeed*1000;
  Socket.BufferSender.Counter := read_rdtsc;
  IPSendPacket(Socket.BufferSender.Packet, Socket.DestIp, IP_TYPE_TCP);
  {$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: Socket %h sending packet %h\n', [PtrUInt(Socket), PtrUInt(Socket.BufferSender.Packet)]); {$ENDIF}
end;

// Dispatch every ready Socket to its associated Network Service
procedure NetworkDispatcher(Handler: PNetworkHandler);
var
  CountTime: Int64;
  NextSocket: PSocket;
  ResumeTime: Int64;
  Service: PNetworkService;
  Socket: PSocket;
begin
  Service := GetCurrentThread.NetworkService; // Get Network Service structure
  NextSocket := Service.ClientSocket; // Get Client queue
  // we will execute a handler for every socket depending of the EVENT
  while NextSocket <> nil do
  begin
    Socket := NextSocket;
	NextSocket := Socket.Next;
	{$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h Handler: %h, Dispatcher Event: %d, Buffer Sender: %h Socket state: %d\n', [PtrUInt(Socket),PtrUInt(Handler),Socket.DispatcherEvent, PtrUInt(Socket.BufferSender), Socket.State]); {$ENDIF} 
    case Socket.DispatcherEvent of
      DISP_ACCEPT :
        begin // new connection
			{$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h Handler: %h, ACCEPT, Buffer Sender: %h\n', [PtrUInt(Socket),PtrUInt(Handler),PtrUInt(Socket.BufferSender)]); {$ENDIF} 
			Handler.DoAccept(Socket);
	    end;
	  DISP_CLOSING :
		begin
			// we keep sending until the queue is empty 
			{$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h Handler: %h Buffer Sender: %h in DISP_CLOSING\n', [PtrUInt(Socket),PtrUInt(Handler),PtrUInt(Socket.BufferSender)]); {$ENDIF} 
			if Socket.BufferSender = nil then
			begin
				{$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h Handler: %h Buffer Sender: %h closing\n', [PtrUInt(Socket),PtrUInt(Handler),PtrUInt(Socket.BufferSender)]); {$ENDIF} 
				Socket.State := SCK_PEER_DISCONNECTED;
				SetSocketTimeOut(Socket, WAIT_ACK);
				// Send ACKFIN to remote host
				TCPSendPacket(TCP_ACK or TCP_FIN, Socket);
				// we need the dispatcher anymore
				Socket.DispatcherEvent := DISP_ZOMBIE;
			end;
		end;
      DISP_WAITING:
        begin // The sockets is waiting for an external event
          ResumeTime:= read_rdtsc;
          // Correction for Overflow
          if Socket.Counter < ResumeTime then
            CountTime:= Socket.Counter - ResumeTime
          else
            CountTime:= $ffffffff-Socket.Counter+ResumeTime;
          // the TimeOut has expired
          if Socket.TimeOut < CountTime then
          begin
            // if client connection lost, need to reconnect
            // In ConnectFail event, need to call connect()
            if Socket.State = SCK_CONNECTING then
            begin
              Socket.State := SCK_BLOCKED;
              Handler.DoConnectFail(Socket)
            end  else if Socket.State = SCK_LOCALCLOSING then
            begin
			  {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h, SCK_LOCALCLOSING, freeing \n', [PtrUInt(Socket)]); {$ENDIF} 
              // we lost the connection, free the socket
              FreeSocket(Socket)
            end else if Socket.State = SCK_PEER_DISCONNECTED then
            begin
              // ACK timer expired
              if Socket.RemoteClose then 
			  begin
				    // I free the socket since peer did not answer the ACK 
					FreeSocket(Socket);
					{$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h, SCK_PEER_DISCONNECTED, freeing\n', [PtrUInt(Socket)]); {$ENDIF} 
			  end else begin
					// I go zombie since peer did not answer the ACK
					Socket.DispatcherEvent := DISP_ZOMBIE;
					{$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h, SCK_PEER_DISCONNECTED, going zombie\n', [PtrUInt(Socket)]); {$ENDIF} 
			  end;
            end else if Socket.State = SCK_NEGOTIATION then
            begin
              // The ACK never came  , we 'll close the connection
              FreeSocket(Socket);
            end else
            begin
              Socket.DispatcherEvent := DISP_TIMEOUT;
              Handler.DoTimeOut(Socket)
            end
          end;
        end;
      DISP_RECEIVE: Handler.DoReceive(Socket); // Has the socket new data?
      DISP_CLOSE: Handler.DoClose(Socket); // Peer socket disconnected
      DISP_CONNECT: Handler.DoConnect(Socket);
    end;
    DispatcherFlushPacket(Socket); // Send the packets in the buffer
    {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Flushed %h\n', [PtrUInt(Socket.BufferSender)]); {$ENDIF} 
  end;
end;

// Do all internal job of service
function DoNetworkService(Handler: PNetworkHandler): LongInt;
begin
  Handler.DoInit; // Initilization of Service
  {$IFDEF DebugSocket} WriteDebug('DoNetworkService: DoInit in Handler: %h\n', [PtrUInt(Handler)]); {$ENDIF} 
  while True do
  begin
    NetworkDispatcher(Handler); // Fetch event for socket and dispatch
    SysThreadSwitch;
  end;
  Result := 0;
end;

// Register a Network service, this is a system thread
procedure SysRegisterNetworkService(Handler: PNetworkHandler);
var
  Service: PNetworkService;
  Thread: PThread;
  ThreadID: TThreadID; // FPC was using ThreadVar ThreadID
begin
  Service:= ToroGetMem(SizeOf(TNetworkService));
  if Service = nil then
    Exit;
  // Create a Thread to make the job of service, it is created on LOCAL CPU
  ThreadID := BeginThread(nil, 10*1024, @DoNetworkService, Handler, DWORD(-1), ThreadID);
  Thread := Pointer(ThreadID);
  if Thread = nil then
  begin
    ToroFreeMem(Service);
    Exit;
  end;
  // Enqueue the Service Network structure
  Thread.NetworkService := Service;
  Service.ServerSocket := nil;
  Service.ClientSocket := nil;
  {$IFDEF DebugSocket} WriteDebug('SysRegisterNetworkService: Thread %d, Handler: %h\n', [ThreadID,PtrUInt(Handler)]); {$ENDIF} 
end;

// Return a Pointer to a new Socket
function SysSocket(SocketType: LongInt): PSocket;
var
  Socket: PSocket;
begin
  Socket := ToroGetMem(SizeOf(TSocket));
  if Socket = nil then
  begin
    Result := nil;
	{$IFDEF DebugSocket} WriteDebug('SysSocket: fail not enough memory\n', []); {$ENDIF}
    Exit;
  end;
  // It doesn't need the dispatcher at the moment
  Socket.DispatcherEvent := DISP_ZOMBIE;
  Socket.State := 0;
  Socket.SocketType := SocketType;
  Socket.BufferLength:= 0;
  Socket.Buffer:= nil;
  Socket.AckFlag := False;
  Socket.AckTimeOut := 0;
  Socket.BufferSender := nil;
  Socket.RemoteClose := false;
  FillChar(Socket.DestIP, 0, SizeOf(TIPAddress));
  Socket.DestPort := 0 ;
  Result := Socket;
  {$IFDEF DebugSocket} WriteDebug('SysSocket: New Socket Type %d, Buffer Sender: %d\n', [SocketType, PtrUInt(Socket.BufferSender)]); {$ENDIF}
end;

// Configure the Socket , this is call is not necesary because the user has access to Socket Structure
// is implemented only for compatibility. IpLocal is ignored
function SysSocketBind(Socket: PSocket; IPLocal, IPRemote: TIPAddress; LocalPort: LongInt): Boolean;
begin
  Socket.SourcePort := LocalPort;
  Socket.DestIP := IPRemote;
  Result := True;
end;

// Return a free port from Local Socket Bitmap
function GetFreePort: LongInt;
var
  CPUID, J: LongInt;
  Bitmap: Pointer;
begin
  CPUID:= GetApicid;
  Bitmap := @DedicateNetworks[CPUID].SocketStreamBitmap[0];
  // looking for free ports in Bitmap
  for J := 0 to MAX_SocketPorts-USER_START_PORT do
  begin
    if not Bit_Test(bitmap, J) then
    begin
      Bit_Set(bitmap, J);
      Result := J + USER_START_PORT;
      Exit;
    end;
  end;
  // We don't have free ports
  Result := USER_START_PORT-1;
end;

// Connect to Remote host
function SysSocketConnect(Socket: PSocket): Boolean;
var
  CPUID: LongInt;
  Service: PNetworkService;
begin
  CPUID:= GetApicid;
  Socket.Buffer := ToroGetMem(MAX_WINDOW);
  // we haven't got memory
  if Socket.Buffer = nil then
  begin
    Result:=False;
    Exit;
  end;
  Socket.SourcePort := GetFreePort;
  // we haven't got free ports
  if Socket.SourcePort < USER_START_PORT then
  begin
    ToroFreeMem(Socket.Buffer);
    Socket.SourcePort:= 0 ;
    Result := False;
    Exit;
  end;
  // Configure Client Socket
  Socket.State := SCK_CONNECTING;
  Socket.mode := MODE_CLIENT;
  Socket.NeedFreePort := True;
  Socket.BufferLength := 0;
  Socket.BufferLength:=0;
  Socket.BufferReader:= Socket.Buffer;
  // Enqueue the Thread Service structure to array of ports
  Service := GetCurrentThread.NetworkService;
  DedicateNetworks[CPUID].SocketStream[Socket.SourcePort]:= Service ;
  // Enqueue the socket
  Socket.Next := Service.ClientSocket;
  Service.ClientSocket := Socket;
  {$IFDEF DebugNetwork} WriteDebug('SysSocketConnect: Connecting from Port %d to Port %d\n', [Socket.SourcePort, Socket.DestPort]); {$ENDIF}
  // SYN is sended , request of connection
  Socket.LastAckNumber := 0;
  Socket.LastSequenceNumber := 300;
  TcpSendPacket(TCP_SYN, Socket);
  // we have got to set a TimeOut for wait the ACK confirmation
  SetSocketTimeOut(Socket,WAIT_ACK);
  Result := True;
end;

// Close connection to Remote Host
// Just for Client Sockets
procedure SysSocketClose(Socket: PSocket);
begin
	DisableInt;
	{$IFDEF DebugSocket} WriteDebug('SysSocketClose: Closing Socket %h in port %d, Buffer Sender %h, Dispatcher %d\n', [PtrUInt(Socket),Socket.SourcePort, PtrUInt(Socket.BufferSender),Socket.DispatcherEvent]); {$ENDIF}
	// is there something to send?
	if Socket.BufferSender = nil then 
	begin
		// we send the ACKFIN and we wait for ACK
		Socket.State := SCK_PEER_DISCONNECTED;
		// we have to wait the ACK of remote host
		SetSocketTimeOut(Socket, WAIT_ACK);
		// Send ACKFIN to remote host
		TCPSendPacket(TCP_ACK or TCP_FIN, Socket);
		{$IFDEF DebugSocket} WriteDebug('SysSocketClose: send FINACK in Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
	end else 
	begin
		// the dispatcher will flush the buffer sender
		Socket.DispatcherEvent := DISP_CLOSING;
		{$IFDEF DebugSocket} WriteDebug('SysSocketClose: Socket %h in DISP_CLOSING\n', [PtrUInt(Socket)]); {$ENDIF}
	end;
	RestoreInt;
end;

// Prepare the Socket for receive connections , the socket is in BLOCKED State
function SysSocketListen(Socket: PSocket; QueueLen: LongInt): Boolean;
var
  CPUID: LongInt;
  Service: PNetworkService;
begin
  CPUID := GetApicid;
  Result := False;
  // SysSocketListen() is only for TCP.
  if Socket.SocketType <> SOCKET_STREAM then
    Exit;
  // Listening port always are above to USER_START_PORT
  if Socket.SourcePORT >= USER_START_PORT then
    Exit;
  Service := DedicateNetworks[CPUID].SocketStream[Socket.SourcePort];
  // The port is busy
  if (Service <> nil) then
   Exit;
  // Enqueue the Server Socket to Thread Network Service structure
  Service:= GetCurrentThread.NetworkService;
  Service.ServerSocket := Socket;
  DedicateNetworks[CPUID].SocketStream[Socket.SourcePort]:= Service;
 // socket is waiting for new connections
  Socket.State := SCK_LISTENING;
  Socket.Mode := MODE_SERVER;
  Socket.NeedfreePort := False;
  // Max Number of remote conenctions pendings
  Socket.ConnectionsQueueLen := QueueLen;
  Socket.ConnectionsQueueCount := 0;
  Socket.DestPort:=0;
  Result := True;
  {$IFDEF DebugSocket} WriteDebug('SysSocketListen: Socket installed in Local Port: %d, Buffer Sender: %h\n', [Socket.SourcePort,PtrUInt(Socket.BufferSender)]); {$ENDIF}
end;

// Read Data from Buffer and save it in Addr , The data continue into the buffer
function SysSocketPeek(Socket: PSocket; Addr: PChar; AddrLen: UInt32): LongInt;
var
  FragLen: LongInt;
begin
  {$IFDEF DebugNetwork} WriteDebug('SysSocketPeek BufferLength: %d\n', [Socket.BufferLength]); {$ENDIF}
  Result := 0;
  if (Socket.State <> SCK_TRANSMITTING) or (AddrLen=0) or (Socket.Buffer+Socket.BufferLength=Socket.BufferReader) then
  begin
    {$IFDEF DebugNetwork} WriteDebug('SysSocketPeek -> Exit\n', []); {$ENDIF}
    Exit;
  end;
  while (AddrLen > 0) and (Socket.State = SCK_TRANSMITTING) do
  begin
    if Socket.BufferLength > AddrLen then
    begin
      FragLen := AddrLen;
      AddrLen := 0;
    end else begin
      FragLen := Socket.BufferLength;
      AddrLen := 0;
    end;
    Move(Socket.BufferReader^, Addr^, FragLen);
    {$IFDEF DebugNetwork} WriteDebug('SysSocketPeek:  %q bytes from port %d to port %d\n', [PtrUInt(FragLen), Socket.SourcePort, Socket.DestPort]); {$ENDIF}
    Result := Result + FragLen;
  end;
end;

// Read Data from Buffer and save it in Addr
function SysSocketRecv(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32): LongInt;
var
  FragLen: LongInt;
begin
  {$IFDEF DebugNetwork} WriteDebug('SysSocketRecv: BufferLength: %d\n', [Socket.BufferLength]); {$ENDIF}
  Result := 0;
  if (Socket.State <> SCK_TRANSMITTING) or (AddrLen=0) or (Socket.Buffer+Socket.BufferLength = Socket.BufferReader) then
  begin
    {$IFDEF DebugNetwork} WriteDebug('SysSocketRecv -> Exit\n', []); {$ENDIF}
    Exit;
  end;
  while (AddrLen > 0) and (Socket.State = SCK_TRANSMITTING) do
  begin
    if Socket.BufferLength > AddrLen then
    begin
      FragLen := AddrLen;
      AddrLen := 0;
    end else begin
      FragLen := Socket.BufferLength;
      AddrLen := 0;
    end;
    Move(Socket.BufferReader^, Addr^, FragLen);
    {$IFDEF DebugNetwork} WriteDebug('SysSocketRecv: Receiving from %h to %h count: %d\n', [PtrUInt(Socket.BufferReader), PtrUInt(Addr), FragLen]); {$ENDIF}
    Result := Result + FragLen;
    Socket.BufferReader := Socket.BufferReader + FragLen;
    // The buffer was read, inform sender that it can send data again
    if Socket.BufferReader = (Socket.Buffer+MAX_WINDOW) then
    begin
      {$IFDEF DebugNetwork} WriteDebug('SysSocketRecv: TCPSendPacket TCP_ACK\n', []); {$ENDIF}
      Socket.BufferReader := Socket.Buffer;
      Socket.BufferLength := 0;
    end;
  end;
end;

// The Socket waits for notification, and returns when a new event is received
// External events are REMOTECLOSE, RECEIVE or TIMEOUT
// API reserved for Socket Client must be called from event handler
function SysSocketSelect(Socket: PSocket; TimeOut: LongInt): Boolean;
begin
  Result:= True;
  // The socket has a remote closing
  if Socket.State = SCK_LOCALCLOSING then
  begin
    Socket.DispatcherEvent := DISP_CLOSE;
    Exit;
  end;
  // We have data in a Reader Buffer ?
  if Socket.BufferReader < Socket.Buffer+Socket.BufferLength then
  begin
    Socket.DispatcherEvent := DISP_RECEIVE;
    Exit;
  end;
  // Set a TIMEOUT for wait a remote event
  SetSocketTimeOut(Socket, TimeOut);
end;

// Send data to Remote Host using a Client Socket
// every packet is sended with ACKPSH bit  , with the maximus size  possible.
function SysSocketSend(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32): LongInt;
var
  Buffer: PBufferSender;
  Dest: PByte;
  FragLen: UInt32;
  P: PChar;
  Packet: PPacket;
  TCPHeader: PTCPHeader;
  TempBuffer: PBufferSender;
begin
  P := Addr;
  Result := AddrLen;
  {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Socket: %h Addr: %d Size: %d, BufferSender: %h\n',[PtrUInt(Socket),PtrUInt(Addr),AddrLen,PtrUInt(Socket.BufferSender)]);{$ENDIF}
  while (Addrlen>0) do
  begin
    // every packet has FragLen bytes
    if Addrlen > MTU then
      FragLen:= MTU
    else
      FragLen:= Addrlen;
    // we can only send if the remote host can receiv
    if Fraglen > Socket.RemoteWinCount then
      Fraglen := Socket.RemoteWinCount;
    Socket.RemoteWinCount := Socket.RemoteWinCount - Fraglen; // Decrement Remote Window Size
    // Refresh the remote window size
    if Socket.RemoteWinCount = 0 then
      Socket.RemoteWinCount:= Socket.RemoteWinLen ;
    // we need a new packet
    Packet := ToroGetMem(SizeOf(TPacket)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader)+FragLen);
    // we need a new packet structure
    Buffer := ToroGetMem(SizeOf(TBufferSender));
    // TODO : the syscall may retur nil
    Packet.Data := Pointer(PtrUInt(Packet) + SizeOf(TPacket));
    Packet.Size := SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader)+FragLen;
    Packet.ready := False;
    Packet.Delete := False;
    Packet.Next := nil;
    // Fill TCP paramters
    TcpHeader:= Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
    FillChar(TCPHeader^, SizeOf(TTCPHeader), 0);
    // Copy user DATA to new packet
    Dest := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader));
    {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Moving from %h to %h len %d\n',[PtrUInt(P),PtrUInt(Dest),FragLen]);{$ENDIF}
	Move(P^, Dest^, FragLen);
    TcpHeader.AckNumber := SwapDWORD(Socket.LastAckNumber);
    TcpHeader.SequenceNumber := SwapDWORD(Socket.LastSequenceNumber);
    TcpHeader.Flags := TCP_ACKPSH;
    TcpHeader.Header_Length := (SizeOf(TTCPHeader) div 4) shl 4;
    TcpHeader.SourcePort := SwapWORD(Socket.SourcePort);
    TcpHeader.DestPort := SwapWORD(Socket.DestPort);
    // Local Window Size
    TcpHeader.Window_Size := SwapWORD(MAX_WINDOW - Socket.BufferLength);
    TcpHeader.Checksum := TCP_CheckSum(DedicateNetworks[GetApicid].IpAddress, Socket.DestIp, PChar(TCPHeader), FragLen+SizeOf(TTCPHeader));
    // Buffer Sender structure, the dispatcher works with that structure
    Buffer.Packet := Packet;
    Buffer.NextBuffer := nil;
    Buffer.Attempts := 2;
    // Enqueue Buffer
    {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enqueing sender Buffer\n',[PtrUInt(P),PtrUInt(Dest),FragLen]);{$ENDIF}
	if Socket.BufferSender = nil then
	begin
      Socket.BufferSender := Buffer;
	  {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enquing first %h\n',[PtrUInt(Socket.BufferSender)]);{$ENDIF}
    end
	else
    begin
	  {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enquing in last buffer %h\n',[PtrUInt(Socket.BufferSender)]);{$ENDIF}
      TempBuffer := Socket.BufferSender;
      while TempBuffer.NextBuffer <> nil do
        TempBuffer := TempBuffer.NextBuffer;
      TempBuffer.NextBuffer := Buffer;
	  {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enqued last sender Buffer\n',[]);{$ENDIF}
    end;
	{$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enqued sender Buffer\n',[]);{$ENDIF}
    // Next data to send
    AddrLen := Addrlen - FragLen;
    P := P+FragLen;
  end;
//{$IFDEF DebugSocket} WriteDebug('SysSocketSend: END\n',[]);{$ENDIF}
end;

end.



