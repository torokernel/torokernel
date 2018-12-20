//
// Network.pas
//
// This unit implements the Stack TCP/IP and Socket management.
//
// Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
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
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Process, Console, Memory;

const
  SOCKET_DATAGRAM = 1;
  SOCKET_STREAM = 2;
  MAX_SocketPORTS = 20000;
  MAX_WINDOW = $4000;
  MTU = 1200;
  USER_START_PORT = 10000;
  SZ_SocketBitmap = (MAX_SocketPORTS - USER_START_PORT) div SizeOf(Byte)+1;
  WAIT_ICMP = 50;
  ServiceStack = 10*1024;

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
  THardwareAddress = array[0..5] of Byte;
  TIPAddress = DWORD;

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

  TPacket = record
    Size: LongInt;
    Data: Pointer;
    Status: Boolean;
    Ready: Boolean;
    Delete: Boolean;
    Next: PPacket;
  end;

  TMachine = record
    IpAddress: TIpAddress;
    HardAddress: THardwareAddress;
    Next: PMachine;
  end;

  TNetworkInterface = record
    Name: AnsiString;
    Minor: LongInt;
    MaxPacketSize: LongInt;
    HardAddress: THardwareAddress;
    IncomingPacketTail: PPacket;
    IncomingPackets: PPacket;
    OutgoingPacketTail: PPacket;
    OutgoingPackets: PPacket;
    Start: procedure (NetInterface: PNetworkInterface);
    Send: procedure (NetInterface: PNetWorkInterface;Packet: PPacket);
    Reset: procedure (NetInterface: PNetWorkInterface);
    Stop: procedure (NetInterface: PNetworkInterface);
    CPUID: LongInt;
    TimeStamp: Int64;
    Next: PNetworkInterface;
  end;

  PTANetworkService = ^TANetworkService;
  TANetworkService = array[0..0] of PNetworkService;

  TNetworkDedicate = record
    NetworkInterface: PNetworkInterface;
    IpAddress: TIPAddress;
    Gateway: TIPAddress;
    Mask: TIPAddress;
    TranslationTable: PMachine;
    SocketStream: PTANetworkService;
    SocketStreamBitmap: array[0..SZ_SocketBitmap] of Byte;
    SocketDatagram: PTANetworkService;
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
    TimeOut: Int64;
    BufferSenderTail: PBufferSender;
    BufferSender: PBufferSender;
    AckFlag: Boolean;
    AckTimeOut: LongInt;
    WinFlag: Boolean;
    WinTimeOut: LongInt;
    WinCounter: LongInt;
    RemoteClose: Boolean;
    UserDefined: Pointer;
    Next: PSocket;
  end;

  TNetworkService = record
    ServerSocket: PSocket;
    ClientSocket: PSocket;
  end;

  TInitProc = procedure;
  TSocketProc = function (Socket: PSocket): LongInt;
  TNetworkHandler = record
    DoInit: TInitProc;
    DoAccept: TSocketProc;
    DoTimeOut: TSocketProc;
    DoReceive: TSocketProc;
    DoConnect: TSocketProc;
    DoConnectFail: TSocketProc;
    DoClose: TSocketProc;
  end;

  TBufferSender = record
    Packet: PPacket;
    Attempts: LongInt;
    NextBuffer: PBufferSender;
  end;

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
procedure NetworkInit;
procedure RegisterNetworkInterface(NetInterface: PNetworkInterface);
function DequeueOutgoingPacket: PPacket;
procedure EnqueueIncomingPacket(Packet: PPacket);
procedure SysNetworkSend(Packet: PPacket);
function SysNetworkRead: PPacket;
function GetLocalMAC: THardwareAddress;
function GetMacAddress(IP: TIPAddress): PMachine;
procedure _IPAddress(const Ip: array of Byte; var Result: TIPAddress);
procedure _IPAddresstoArray(const Ip: TIPAddress; out Result: array of Byte);
procedure IPStrtoArray(Ip: Pchar; out Result: array of Byte);
function ICMPSendEcho(IpDest: TIPAddress; Data: Pointer; len: Longint; seq, id: word): Longint;
function ICMPPoolPackets: PPacket;
function SwapWORD(n: Word): Word; {$IFDEF INLINE}inline;{$ENDIF}
procedure DedicateNetwork(const Name: AnsiString; const IP, Gateway, Mask: array of Byte; Handler: TThreadFunc);

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}

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
  TCP_SYN = 2;
  TCP_SYNACK = 18;
  TCP_ACK = 16;
  TCP_FIN = 1;
  TCP_ACKPSH = $18;
  TCP_ACKEND = TCP_ACK or TCP_FIN;
  TCP_RST = 4 ;

  MAX_ARPENTRY = 100; // Max number of entries in ARP Table

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

  WAIT_ACK = 50;
  WAIT_ARP = 50;
  WAIT_ACKFIN = 10000;
  MAX_RETRY = 2;
  WAIT_WIN = 30000;

  // Socket Dispatcher State
  DISP_WAITING = 0;
  DISP_ACCEPT = 1;
  DISP_RECEIVE = 2;
  DISP_CONNECT = 3;
  DISP_TIMEOUT = 4;
  DISP_CLOSE = 5;
  DISP_ZOMBIE = 6;
  DISP_CLOSING = 7;

var
  LastId: WORD = 0;

// Translate IP to MAC
// TODO: use a faster data structure, e.g., hash table or array
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

procedure AddTranslateIp(IP: TIPAddress; const HardAddres: THardwareAddress);
var
  CPUID: LongInt;
  Machine, PrevMachine: PMachine;
begin
  Machine := LookIp(Ip);
  CPUID := GetApicid;
  if Machine = nil then
  begin
    Machine := ToroGetMem(SizeOf(TMachine));
    if Machine = nil then
    begin
      Machine := DedicateNetworks[CPUID].TranslationTable;
      PrevMachine := Machine;
      Panic (Machine = nil, 'AddTranslateIp: Run out of memory');
      while Machine.Next <> nil do
      begin
        PrevMachine := Machine;
        Machine := Machine.Next;
      end;
      PrevMachine.Next := nil;
      Machine.Next := DedicateNetworks[CPUID].TranslationTable;
      DedicateNetworks[CPUID].TranslationTable := Machine;
      Machine.IpAddress := Ip;
      Machine.HardAddress := HardAddres;
      Exit;
    end;
    Machine.IpAddress := Ip;
    Machine.HardAddress := HardAddres;
    Machine.Next := DedicateNetworks[CPUID].TranslationTable;
    DedicateNetworks[CPUID].TranslationTable := Machine;
  end;
end;

procedure _IPAddress(const Ip: array of Byte; var Result: TIPAddress);
begin
  Result := (Ip[3] shl 24) or (Ip[2] shl 16) or (Ip[1] shl 8) or Ip[0];
end;

procedure _IPAddresstoArray(const Ip: TIPAddress; out Result: array of Byte);
begin
  Result[0] := Ip and $ff;
  Result[1] := (Ip and $ff00) shr 8;
  Result[2] := Ip and $ff0000 shr 16;
  Result[3] := Ip and $ff000000 shr 24;
end;

// Ip can be null char ending or space char ending
procedure IPStrtoArray(Ip: Pchar; out Result: array of Byte);
var
  Count, Value: byte;
begin
  Count := 0;
  Value := 0;
  while (Ip^ <> #0) and (Ip^ <> ' ') do
  begin
    if Ip^ = '.' then
    begin
      Result[Count] := Value;
      Value := 0;
      Inc(Count);
    end else
    begin
      Value := Value * 10;
      Value := Value + (Byte(Ip^) - Byte('0'));
    end;
    Inc(Ip);
  end;
  Result[Count] := Value;
end;

procedure RegisterNetworkInterface(NetInterface: PNetworkInterface);
begin
  NetInterface.IncomingPackets := nil;
  NetInterface.IncomingPacketTail := nil;
  NetInterface.OutgoingPackets := nil;
  NetInterface.OutgoingPacketTail := nil;
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

function CalculateChecksum(pip: Pointer; data: Pointer; cnt, pipcnt: word): word;
var
  pw: ^Word;
  loop: word;
  x, w: word;
  csum: DWord;
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

function TCP_Checksum(SourceIP, DestIp: TIPAddress; PData: PChar; Len: Word): WORD;
var
  PseudoHeader: TPseudoHeader;
begin
  FillChar(PseudoHeader, SizeOf(PseudoHeader), 0);
  PseudoHeader.SourceIP := SourceIP;
  PseudoHeader.TargetIP := DestIP;
  PseudoHeader.TCPLen := Swap(Word(Len));
  PseudoHeader.Cero := 0;
  PseudoHeader.Protocol := IP_TYPE_TCP;
  Result := CalculateChecksum(@PseudoHeader, PData, Len, SizeOf(PseudoHeader));
end;

function ValidateTCP(IpSrc:TIPAddress;SrcPort,DestPort: Word): PSocket;
var
  Service: PNetworkService;
begin
  Service := DedicateNetworks[GetApicid].SocketStream[DestPort];
  if Service = nil then
  begin
    Result := nil;
    Exit;
  end;
  Result := Service.ClientSocket;
  while Result <> nil do
  begin
    if (Result.DestIp = IpSrc) and (Result.DestPort = SrcPort) and (Result.SourcePort = DestPort) then
      Exit
    else
      Result := Result.Next;
  end;
end;

procedure SetSocketTimeOut(Socket: PSocket; TimeOut: Int64); inline;
begin
  Socket.TimeOut := read_rdtsc + TimeOut * LocalCPUSpeed * 1000;
  Socket.DispatcherEvent := DISP_WAITING;
  {$IFDEF DebugSocket}WriteDebug('SetSocketTimeOut: Socket %h, SocketTimeOut: %d, TimeOut: %d\n', [PtrUInt(Socket), Socket.TimeOut, TimeOut]);{$ENDIF}
end;

procedure TCPSendPacket(Flags: LongInt; Socket: PSocket); forward;

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
  if Socket.ConnectionsQueueLen = Socket.ConnectionsQueueCount then
  begin
    {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: Fail connection to %d Queue is complete\n', [LocalPort]);{$ENDIF}
    ToroFreeMem(Packet);
    Exit;
  end;
  Service := DedicateNetworks[GetApicid].SocketStream[LocalPort];
  ClientSocket := ToroGetMem(SizeOf(TSocket));
  if ClientSocket = nil then
  begin
   ToroFreeMem(Packet);
   {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: Fail connection to %d not memory\n', [LocalPort]);{$ENDIF}
   Exit;
  end;
  Buffer:= ToroGetMem(MAX_WINDOW);
  if Buffer= nil then
  begin
    ToroFreeMem(ClientSocket);
    ToroFreeMem(Packet);
    {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: Fail connection to %d not memory\n', [LocalPort]);{$ENDIF}
    Exit;
  end;
  ClientSocket.State := SCK_NEGOTIATION;
  ClientSocket.BufferLength := 0;
  ClientSocket.Buffer := Buffer;
  ClientSocket.BufferReader := ClientSocket.Buffer;
  ClientSocket.Next := Service.ClientSocket;
  Service.ClientSocket := ClientSocket;
  ClientSocket.SocketType := SOCKET_STREAM;
  ClientSocket.DispatcherEvent := DISP_ZOMBIE;
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
  ClientSocket.BufferSenderTail := nil;
  ClientSocket.RemoteClose := False;
  ClientSocket.AckFlag := True;
  AddTranslateIp(IpHeader.SourceIp, EthHeader.Source);
  ToroFreeMem(Packet);
  Inc(Socket.ConnectionsQueueCount);
  {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: sending SYNACK in Socket %h for new Socket Client %h\n', [PtrUInt(Socket), PtrUInt(ClientSocket)]);{$ENDIF}
  TCPSendPacket(TCP_SYNACK, ClientSocket);
  SetSocketTimeOut(ClientSocket, WAIT_ACK);
  {$IFDEF DebugNetwork}WriteDebug('EnqueueTCPRequest: new socket %h to Port %d, Queue: %d\n', [PtrUInt(ClientSocket), LocalPort, Socket.ConnectionsQueueCount]);{$ENDIF}
end;

procedure SysNetworkSend(Packet: PPacket);
var
  CPUID: LongInt;
  NetworkInterface: PNetworkInterface;
begin
  CPUID := GetApicID;
  NetworkInterface := DedicateNetworks[CPUID].NetworkInterface;
  Packet.Ready := False; // the packet has been sent when Ready = True
  Packet.Status := False;
  Packet.Next := nil;
  {$IFDEF DebugNetwork}WriteDebug('SysNetworkSend: sending packet %h\n', [PtrUInt(Packet)]);{$ENDIF}
  NetworkInterface.Send(NetworkInterface, Packet);
  {$IFDEF DebugNetwork}WriteDebug('SysNetworkSend: sent packet %h\n', [PtrUInt(Packet)]);{$ENDIF}
end;

const
  ARP_OP_REQUEST = 1;
  ARP_OP_REPLY = 2;

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
  Packet.Delete := True;
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
  EthPacket.Destination := MACBroadcast;
  EthPacket.Source:= DedicateNetworks[CpuID].NetworkInterface.HardAddress;
  EthPacket.ProtocolType := SwapWORD(ETH_FRAME_ARP);
  SysNetworkSend(Packet);
end;

function GetLocalMAC: THardwareAddress;
begin
  Result := DedicateNetworks[GetApicid].NetworkInterface.HardAddress;
end;

function GetMacAddress(IP: TIPAddress): PMachine;
var
  Machine: PMachine;
  I: LongInt;
begin
  I := 3;
  while I > 0 do
  begin
    {$IFDEF DebugNetwork} WriteDebug('GetMacAddress: Attempt %d for IP: %h\n', [I, PtrUInt(IP)]); {$ENDIF}
    Machine := LookIp(IP); // MAC already added ?
    if Machine <> nil then
    begin
     {$IFDEF DebugNetwork} WriteDebug('GetMacAddress: MAC found in cache, IP:%h\n', [PtrUInt(IP)]); {$ENDIF}
      Result:= Machine;
      Exit;
    end;
    ARPRequest(IP); // Request the MAC of IP
    Sleep(WAIT_ARP); // Wait for Remote Response
    Dec(I);
  end;
  {$IFDEF DebugNetwork} WriteDebug('GetMacAddress: IP: %h not found\n', [PtrUInt(IP)]); {$ENDIF}
  Result := nil;
end;

function RouteIP(IP: TIPAddress) : PMachine;
var
  CPUID: LongInt;
  Net: PNetworkDedicate;
begin
  CPUID:= GetApicid;
  Net := @DedicateNetworks[CPUID];
  {$IFDEF DebugNetwork} WriteDebug('RouteIP: Getting MAC for IP: %h\n', [PtrUInt(IP)]); {$ENDIF}
  if (Net.Mask and IP) <> (Net.Mask and Net.Gateway) then
  begin
    {$IFDEF DebugNetwork} WriteDebug('RouteIP: MAC is gateway\n', []); {$ENDIF}
    Result := GetMacAddress(Net.Gateway);
    Exit;
  end;
  {$IFDEF DebugNetwork} WriteDebug('RouteIP: MAC is local\n', []); {$ENDIF}
  Result := GetMacAddress(IP);
end;

procedure EthernetSendPacket(Packet: PPacket);
var
  CpuID: LongInt;
  EthHeader: PEthHeader;
  IPHeader: PIPHeader;
  Machine: PMachine;
begin
  {$IFDEF DebugNetwork} WriteDebug('EthernetSendPacket: packet sending %h\n', [PtrUInt(Packet)]);{$ENDIF}
  CpuID := GetApicid;
  EthHeader := Packet.Data;
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  EthHeader.Source := DedicateNetworks[CpuID].NetworkInterface.HardAddress;
  Machine := RouteIP(IPHeader.destip);
  if Machine = nil then
  begin
    {$IFDEF DebugNetwork}WriteDebug('EthernetSendPacket: Route to IP not found\n', []);{$ENDIF}
    Exit;
  end;
  EthHeader.Destination := Machine.HardAddress;
  EthHeader.ProtocolType := SwapWORD(ETH_FRAME_IP);
  SysNetworkSend(Packet);
  {$IFDEF DebugNetwork} WriteDebug('EthernetSendPacket: packet sent %h\n', [PtrUInt(Packet)]);{$ENDIF}
end;

procedure IPSendPacket(Packet: PPacket; IpDest: TIPAddress; Protocol: Byte);
var
  IPHeader: PIPHeader;
begin
  {$IFDEF DebugNetwork}WriteDebug('IPSendPacket: sending packet %h\n', [PtrUInt(Packet)]);{$ENDIF}
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
  EthernetSendPacket(Packet);
  {$IFDEF DebugNetwork}WriteDebug('IPSendPacket: packet sent %h\n', [PtrUInt(Packet)]);{$ENDIF}
end;

const
 TCPPacketLen : LongInt =  SizeOf(TPacket)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader);

procedure TCPSendPacket(Flags: LongInt; Socket: PSocket);
var
  TCPHeader: PTCPHeader;
  Packet: PPacket;
begin
  Packet := ToroGetMem(TCPPacketLen);
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
  if (Socket.State = SCK_NEGOTIATION) or (Socket.State = SCK_CONNECTING) or (Socket.State= SCK_LOCALCLOSING) or (Socket.State = SCK_PEER_DISCONNECTED) then
    Inc(Socket.LastSequenceNumber)
  else if Socket.State = SCK_TRANSMITTING then
  begin
//    Socket.LastSequenceNumber := Socket.LastSequenceNumber;
  end;
  {$IFDEF DebugNetwork}WriteDebug('TCPSendPacket: sending TCP packet for Socket %h\n', [PtrUInt(Socket)]);{$ENDIF}
end;

// Inform the Kernel that the last packet has been sent, returns the next packet to be sent
function DequeueOutgoingPacket: PPacket;
var
  CPUID: LongInt;
  Packet: PPacket;
begin
  CPUID := GetApicid;
  Packet := DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets;
  If Packet = nil then
  begin
    {$IFDEF DebugNetwork}WriteDebug('DequeueOutgoingPacket: OutgoingPackets = NULL\n', []);{$ENDIF}
    Result := nil;
    Exit;
  end;
  DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets := Packet.Next;
  if Packet.Next = nil then
  begin
     DedicateNetworks[CPUID].NetworkInterface.OutgoingPacketTail := nil
  end;
  DedicateNetworks[CPUID].NetworkInterface.TimeStamp := read_rdtsc;
  if Packet.Delete then
  begin
    {$IFDEF DebugNetwork}WriteDebug('DequeueOutgoingPacket: Freeing packet %h\n', [PtrUInt(Packet)]);{$ENDIF}
    ToroFreeMem(Packet);
  end;
  Packet.Ready := True;
  Result := DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets;
end;

procedure ProcessARPPacket(Packet: PPacket); forward;

// Inform the Kernel that a new Packet has arrived
// Disable interruption to prevent concurrent access
procedure EnqueueIncomingPacket(Packet: PPacket);
var
  PacketQueue: PPacket;
  EthPacket : PEthHeader;
begin
  {$IFDEF DebugNetwork}WriteDebug('EnqueueIncomingPacket: new packet: %h\n', [PtrUInt(Packet)]); {$ENDIF}
  EthPacket := Packet.Data;
  if SwapWORD(EthPacket.ProtocolType) = ETH_FRAME_ARP then
  begin
      {$IFDEF DebugNetwork}WriteDebug('EnqueueIncomingPacket: new ARP packet: %h\n', [PtrUInt(Packet)]); {$ENDIF}
      ProcessARPPacket(Packet);
      Exit;
  end;
  PacketQueue := DedicateNetworks[GetApicId].NetworkInterface.IncomingPackets;
  Packet.Next := nil;
  if PacketQueue = nil then
  begin
    DedicateNetworks[GetApicId].NetworkInterface.IncomingPackets := Packet;
    {$IFDEF DebugNetwork}
      if DedicateNetworks[GetApicId].NetworkInterface.IncomingPacketTail <> nil then
      begin
        WriteDebug('EnqueueIncomingPacket: IncomingPacketTail <> nil\n', []);
      end;
    {$ENDIF}
  end else
  begin
    DedicateNetworks[GetApicId].NetworkInterface.IncomingPacketTail.Next := Packet;
  end;
  DedicateNetworks[GetApicId].NetworkInterface.IncomingPacketTail := Packet
end;

procedure FreePort(LocalPort: LongInt);
var
  CPUID: LongInt;
  Bitmap: Pointer;
begin
  CPUID:= GetApicid;
  Bitmap := @DedicateNetworks[CPUID].SocketStreamBitmap[0];
  Bit_Reset(Bitmap, LocalPort);
end;

procedure FreeSocket(Socket: PSocket);
var
  ClientSocket: PSocket;
  CPUID: LongInt;
  Service: PNetworkService;
  tmp, tmp2: PBufferSender;
begin
  CPUID:= GetApicID;
  {$IFDEF DebugSocket} WriteDebug('FreeSocket: Freeing Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
  Service := DedicateNetworks[CPUID].SocketStream[Socket.SourcePort];
  if Service.ClientSocket = Socket then
    Service.ClientSocket := Socket.Next
  else
  begin
    ClientSocket := Service.ClientSocket;
    while ClientSocket.Next <> Socket do
      ClientSocket := ClientSocket.Next;
    ClientSocket.Next := Socket.Next;
  end;
  if Socket.NeedFreePort then
  begin
    if Socket.SocketType = SOCKET_STREAM then
      DedicateNetworks[CPUID].SocketStream[Socket.SourcePort] := nil
    else
      DedicateNetworks[CPUID].SocketDatagram[Socket.SourcePort] := nil;
    FreePort(Socket.SourcePort);
  end;
  if Socket.BufferSender <> nil then
  begin
    tmp := Socket.BufferSender;
    while tmp <> nil do
    begin
      ToroFreeMem(tmp.Packet);
      tmp2 := tmp.NextBuffer;
      ToroFreeMem(tmp);
      tmp := tmp2;
    end;
    {$IFDEF DebugSocket} WriteDebug('FreeSocket: Freeing Socket %h, Buffer Sender not empty\n', [PtrUInt(Socket)]); {$ENDIF}
  end;
  ToroFreeMem(Socket.Buffer);
  ToroFreeMem(Socket);
end;

procedure ProcessARPPacket(Packet: PPacket);
var
  CPUID: LongInt;
  ArpPacket: PArpHeader;
  EthPacket: PEthHeader;
begin
  CPUID := GetApicid;
  ArpPacket := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  EthPacket := Packet.Data;
  if SwapWORD(ArpPacket.Protocol) = ETH_FRAME_IP then
  begin
    if ArpPacket.TargetIpAddr = DedicateNetworks[CPUID].IpAddress then
    begin
      if ArpPacket.OpCode = SwapWORD(ARP_OP_REQUEST) then
      begin
        EthPacket.Destination := EthPacket.Source;
        EthPacket.Source := DedicateNetworks[CPUID].NetworkInterface.HardAddress;
        ArpPacket.OpCode := SwapWORD(ARP_OP_REPLY);
        ArpPacket.TargetHardAddr := ArpPacket.SenderHardAddr;
        ArpPacket.TargetIpAddr := ArpPacket.SenderIpAddr;
        ArpPacket.SenderHardAddr:= DedicateNetworks[CPUID].NetworkInterface.HardAddress;
        ArpPacket.SenderIpAddr :=DedicateNetworks[CPUID].IpAddress;
        Packet.Delete := True;
        {$IFDEF DebugNetwork} WriteDebug('ProcessARPPacket: Sending my ip\n', []); {$ENDIF}
        SysNetworkSend(Packet);
      end else if ArpPacket.OpCode = SwapWORD(ARP_OP_REPLY) then
      begin
        {$IFDEF DebugNetwork} WriteDebug('ProcessARPPacket: New Machine added to Translation Table\n', []); {$ENDIF}
        AddTranslateIp(ArpPacket.SenderIPAddr,ArpPacket.SenderHardAddr);
        ToroFreeMem(Packet);
      end;
    end else ToroFreeMem(Packet);
  end else ToroFreeMem(Packet);
end;

procedure ProcessTCPSocket(Socket: PSocket; Packet: PPacket);
var
  TCPHeader: PTCPHeader;
  IPHeader: PIPHeader;
  DataSize: UInt32;
  Source, Dest: PByte;
begin
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TETHHeader));
  TCPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TETHHeader)+SizeOf(TIPHeader));
  {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h Packet %h\n', [PtrUInt(Socket),  PtrUInt(Packet)]); {$ENDIF}
  case Socket.State of
    SCK_CONNECTING:
      begin
        if (Socket.Mode = MODE_CLIENT) and (TCPHeader.Flags and TCP_SYN = TCP_SYN) then
        begin
          if SwapDWORD(TCPHeader.AckNumber)-1 = 300 then
          begin
            Socket.DispatcherEvent := DISP_CONNECT;
            Socket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber)+1;
            Socket.LastSequenceNumber := 301;
            Socket.RemoteWinLen := SwapWORD(TCPHeader.Window_Size);
            Socket.RemoteWinCount :=Socket.RemoteWinLen;
            Socket.State := SCK_TRANSMITTING;
            Socket.BufferLength := 0;
            // TODO: this should be allocated before the connection is stablished
            Socket.Buffer := ToroGetMem(MAX_WINDOW);
            Socket.BufferReader := Socket.Buffer;
            {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h sending ACK for confirmation\n', [PtrUInt(Socket)]); {$ENDIF}
            TCPSendPacket(TCP_ACK, Socket);
          end;
        end;
        ToroFreeMem(Packet);
      end;
    SCK_PEER_DISCONNECTED:
      begin
        if TCPHeader.Flags and TCP_RST = TCP_RST then
        begin
          FreeSocket(Socket);
          {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: RST+ACK in SCK_DISCONNECTED so freeing Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
        end else
        if TCPHeader.Flags and TCP_ACK = TCP_ACK then
        begin
          if Socket.RemoteClose then
          begin
            FreeSocket(Socket);
            {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: ACK confirmed and RemoteClose so freeing Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
          end else begin
            if TCPHeader.Flags and TCP_FIN <> TCP_FIN then
            begin
              Socket.AckFlag := True;
              Socket.DispatcherEvent := DISP_ZOMBIE;
              {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: ACK confirmed, waiting for FINACK %h\n', [PtrUInt(Socket)]); {$ENDIF}
            end;
          end;
        end;
        if (TCPHeader.Flags and TCP_FIN = TCP_FIN) and not Socket.RemoteClose then
        begin
          Inc(Socket.LastAckNumber);
          TCPSendPacket(TCP_ACK, Socket);
          {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: FINACK confirmed free Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
          FreeSocket(Socket);
        end;
        ToroFreeMem(Packet);
      end;
    SCK_LOCALCLOSING:
      begin
        if TCPHeader.Flags and TCP_RST = TCP_RST then
        begin
          {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: RST confirmed and LocalClose so freeing Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
           FreeSocket(Socket);
        end;
      end;
    SCK_BLOCKED:
      begin
        ToroFreeMem(Packet)
      end;
    SCK_NEGOTIATION:
      begin
        if TCPHeader.Flags and TCP_FIN = TCP_FIN then
        begin
          {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h received ACKFIN during SCK_NEGOTIATION\n', [PtrUInt(Socket)]); {$ENDIF}
          Inc(Socket.LastAckNumber);
          TCPSendPacket(TCP_ACK, Socket);
          Socket.State:= SCK_LOCALCLOSING;
          Socket.RemoteClose := True;
          Socket.DispatcherEvent:= DISP_ACCEPT;
        end else
        begin
          Socket.State := SCK_TRANSMITTING;
          Socket.DispatcherEvent := DISP_ACCEPT; // invoke Accept()
          {$IFDEF DebugNetwork}WriteDebug('ProcessTCPSocket: Socket %h in DISP_ACCEPT\n', [PtrUInt(Socket)]);{$ENDIF}
        end;
        ToroFreeMem(Packet);
      end;
    SCK_TRANSMITTING:
      begin
        if TCPHeader.Flags and TCP_ACK = TCP_ACK then
        begin
          DataSize:= SwapWord(IPHeader.PacketLength)-SizeOf(TIPHeader)-SizeOf(TTCPHeader);
          Socket.AckFlag := True;
          if TCPHeader.Flags and TCP_ACKEND = TCP_ACKEND then
          begin
            Inc(Socket.LastAckNumber);
            TCPSendPacket(TCP_ACK, Socket);
            Socket.State:= SCK_LOCALCLOSING;
            Socket.RemoteClose := True;
          end else
          begin
            if DataSize <> 0 then
            begin
              Socket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber)+DataSize;
              Source := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTCPHeader));
              Dest := Pointer(PtrUInt(Socket.Buffer)+Socket.BufferLength);
              Move(Source^, Dest^, DataSize);
              Socket.BufferLength := Socket.BufferLength + DataSize;
              if (Socket.DispatcherEvent <> DISP_CLOSING) and (Socket.DispatcherEvent <> DISP_ZOMBIE) and (Socket.DispatcherEvent <> DISP_ACCEPT) then
              begin
                Socket.DispatcherEvent := DISP_RECEIVE;
                {$IFDEF DebugNetwork}WriteDebug('ProcessTCPSocket TCP_ACK: Socket %h in DISP_RECEIVE\n', [PtrUInt(Socket)]);{$ENDIF}
              end;
              TCPSendPacket(TCP_ACK, Socket);
            end;
          end;
          {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket TCP_ACK: received ACK on Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
        end else
        begin
          {$IFDEF DebugNetwork} WriteDebug('ProcessTCPSocket: Socket %h TCP Header flag unknown: %d\n', [PtrUInt(Socket), TCPHeader.Flags]); {$ENDIF}
        end;
        ToroFreeMem(Packet)
      end;
  end;
end;

// Return a Socket or Nil if Socket does not exist
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
    while Socket <> nil do
    begin
      if (Socket.DestIP = IPSrc) and (Socket.DestPort = RemotePort) then
      begin
        {$IFDEF DebugNetwork} WriteDebug('ValidateTCPRequest: duplicate connection on local port %d\n', [LocalPort]); {$ENDIF}
        Exit;
      end
      else
        Socket:= Socket.Next;
    end;
  {$IFDEF DebugNetwork} WriteDebug('ValidateTCPRequest: SYN to local port %d OK, ServerSocket %h\n', [LocalPort, PtrUInt(Service.ServerSocket)]); {$ENDIF}
  Result := Service.ServerSocket;
end;

const
  ICMPPacketLen = SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TICMPHeader) + sizeof(TPacket);

function ICMPSendEcho(IpDest: TIPAddress; Data: Pointer; len: Longint; seq, id: word): Longint;
var
  Packet: PPacket;
  ICMPHeader: PICMPHeader;
  Mac: PMachine;
  PData: Pointer;
  DataLen: Longint;
begin
  Mac := GetMacAddress(IpDest);
  if (Mac = nil) then
  begin
    Result := 1;
    Exit;
  end;
  Packet := ToroGetMem(ICMPPacketLen + len);
  If Packet = nil then
  begin
    Result := 1;
    Exit;
  end;
  Packet.Data := Pointer(PtrUInt(Packet) + sizeof(TPacket));
  Packet.ready := False;
  Packet.Status := False;
  Packet.Delete := True;
  Packet.Next := nil;
  Packet.size := ICMPPacketLen + len - sizeof(TPacket);
  ICMPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
  ICMPHeader.tipe := ICMP_ECHO_REQUEST;
  ICMPHeader.checksum :=0 ;
  ICMPHeader.seq :=  SwapWORD(seq);
  ICMPHeader.code := 0;
  ICMPHeader.id := SwapWORD(id);
  Datalen := len + sizeof(TICMPHeader);
  PData := Pointer(PtrUInt(Packet.Data) + ICMPPacketLen - sizeof(TPacket));
  Move(Data^, PData^, len);
  ICMPHeader.Checksum := CalculateChecksum(nil,ICMPHeader,DataLen,0);
  IPSendPacket(Packet,IPDest,IP_TYPE_ICMP);
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
  Result := ICMPPollerBuffer;
  ICMPPollerBuffer := nil;
end;

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
        if ICMPHeader.tipe = ICMP_ECHO_REQUEST then
        begin
          Packet.Delete := True;
          ICMPHeader.tipe:= ICMP_ECHO_REPLY;
          ICMPHeader.checksum:= 0 ;
          Datalen:= SwapWORD(IPHeader.PacketLength) - SizeOf(TIPHeader);
          ICMPHeader.Checksum := CalculateChecksum(nil,ICMPHeader,DataLen,0);
          AddTranslateIp(IPHeader.SourceIP,EthHeader.Source); // I'll use a MAC address of Packet
          IPSendPacket(Packet,IPHeader.SourceIP,IP_TYPE_ICMP); // sending response
          {$IFDEF DebugNetwork} WriteDebug('icmp: ECHO REQUEST answered\n', []); {$ENDIF}
        end else if ICMPHeader.tipe = ICMP_ECHO_REPLY then
        begin
          if ICMPPollerBuffer = nil then
            ICMPPollerBuffer := Packet
          else
            ToroFreeMem(Packet);
          {$IFDEF DebugNetwork} WriteDebug('icmp: received ECHO REPLY\n', []); {$ENDIF}
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
        if TCPHeader.Flags = TCP_SYN then
        begin
          {$IFDEF DebugNetwork} WriteDebug('ip: received TCP_SYN packet %h\n', [PtrUInt(Packet)]); {$ENDIF}
          Socket := ValidateTCPRequest(IPHeader.SourceIP, SwapWORD(TCPHeader.DestPort), SwapWORD(TCPHeader.SourcePort));
          if Socket <> nil then
          begin
            {$IFDEF DebugNetwork} WriteDebug('ip: SYNC packet %h to local port: %d, remote port: %d\n', [PtrUInt(Packet), Socket.SourcePORT, TCPHeader.SourcePort]); {$ENDIF}
            EthHeader := Packet.Data;
            AddTranslateIp(IpHeader.SourceIp, EthHeader.Source);
            {$IFDEF DebugNetwork} WriteDebug('ip: SYNC packet %h to port: %d, adding MAC to table\n', [PtrUInt(Packet), Socket.SourcePORT]); {$ENDIF}
            EnqueueTCPRequest(Socket, Packet);
          end else
          begin
            {$IFDEF DebugNetwork} WriteDebug('ip: SYNC packet invalid\n', [PtrUInt(Packet)]); {$ENDIF}
            ToroFreeMem(Packet);
          end;
        end else if TCPHeader.Flags and TCP_ACK = TCP_ACK then
        begin
          Socket:= ValidateTCP(IPHeader.SourceIP,SwapWORD(TCPHeader.SourcePort),SwapWORD(TCPHeader.DestPort));
          if Socket <> nil then
          begin
            {$IFDEF DebugNetwork} WriteDebug('ip: ACK packet %h to port: %d\n', [PtrUInt(Packet), Socket.SourcePORT]); {$ENDIF}
            ProcessTCPSocket(Socket,Packet);
          end else
          begin
            {$IFDEF DebugNetwork} WriteDebug('ip: ACK packet %h invalid to local port: %d and remote port: %d, TCP_HEADER: %d\n', [PtrUInt(Packet), SwapWORD(TCPHeader.DestPort), SwapWORD(TCPHeader.SourcePort), TCPHeader.Flags]); {$ENDIF}
            ToroFreeMem(Packet);
          end;
        end else if TCPHeader.Flags and TCP_RST = TCP_RST then
        begin
          Socket:= ValidateTCP(IPHeader.SourceIP,SwapWORD(TCPHeader.SourcePort),SwapWORD(TCPHeader.DestPort));
          {$IFDEF DebugNetwork} WriteDebug('ip: TCP_RST packet %h, Socket: %h\n', [PtrUInt(Packet), PtrUInt(Socket)]); {$ENDIF}
          if Socket <> nil then
            ProcessTCPSocket (Socket, Packet)
          else
            ToroFreeMem(Packet);
        end;
      end;
    else
    begin
      ToroFreeMem(Packet);
    end;
  end;
end;

// Read a packet from Buffer of local Network Interface
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
  else
  begin
    DedicateNetworks[CPUID].NetworkInterface.IncomingPackets := Packet.Next;
    If Packet.Next = nil then
      DedicateNetworks[CPUID].NetworkInterface.IncomingPacketTail := nil;
    Packet.Next := nil;
    Result := Packet;
    {$IFDEF DebugNetwork}WriteDebug('SysNetworkRead: getting packet: %h\n', [PtrUInt(Packet)]); {$ENDIF}
  end;
  RestoreInt;
end;

// This thread function processes the arriving of new packets
function ProcessNetworksPackets(Param: Pointer): PtrInt;
var
  Packet: PPacket;
  EthPacket: PEthHeader;
begin
  {$IFDEF FPC} Result := 0; {$ENDIF}
  while True do
  begin
    Packet := SysNetworkRead;
    if Packet = nil then
    begin
      SysThreadSwitch(True);
      Continue;
    end;
    SysThreadActive;
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
        {$IFDEF DebugNetwork} WriteDebug('ethernet: new unknown packet %h freeing\n', [PtrUInt(Packet)]); {$ENDIF}
        ToroFreeMem(Packet);
      end;
    end;
  end;
end;

procedure NetworkServicesInit;
var
  ThreadID: TThreadID;
begin
  if PtrUInt(BeginThread(nil, 10*1024, @ProcessNetworksPackets, nil, DWORD(-1), ThreadID)) <> 0 then
    WriteConsoleF('Networks Packets Service .... Thread: %d\n',[ThreadID])
  else
    WriteConsoleF('Networks Packets Service .... /VFailed!/n\n',[]);
end;

function LocalNetworkInit: Boolean;
var
  I, CPUID: LongInt;
begin
  CPUID := GetApicid;
  Result := false;
  DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets := nil;
  DedicateNetworks[CPUID].NetworkInterface.OutgoingPacketTail := nil;
  DedicateNetworks[CPUID].NetworkInterface.IncomingPackets := nil;
  DedicateNetworks[CPUID].NetworkInterface.IncomingPacketTail := nil;
  DedicateNetworks[CPUID].SocketStream := ToroGetMem(MAX_SocketPORTS * sizeof(PNetworkService));
  if DedicateNetworks[CPUID].SocketStream = nil then
    Exit;
  DedicateNetworks[CPUID].SocketDatagram := ToroGetMem(MAX_SocketPORTS * sizeof(PNetworkService));
  if DedicateNetworks[CPUID].SocketDatagram = nil then
  begin
    ToroFreeMem(DedicateNetworks[CPUID].SocketStream);
    Exit;
  end;
  for I:= 0 to (MAX_SocketPORTS-1) do
  begin
    DedicateNetworks[CPUID].SocketStream[I]:=nil;
    DedicateNetworks[CPUID].SocketDatagram[I]:=nil;
  end;
  NetworkServicesInit;
  DedicateNetworks[CPUID].NetworkInterface.start(DedicateNetworks[CPUID].NetworkInterface);
  Result := True;
end;

procedure DedicateNetwork(const Name: AnsiString; const IP, Gateway, Mask: array of Byte; Handler: TThreadFunc);
var
  Net: PNetworkInterface;
  Network: PNetworkDedicate;
  ThreadID: TThreadID;
  CPUID: Longint;
begin
  Net := NetworkInterfaces;
  CPUID:= GetApicid;
  {$IFDEF DebugNetwork} WriteDebug('DedicateNetwork: dedicating on CPU%d\n', [CPUID]); {$ENDIF}
  while Net <> nil do
  begin
    if (Net.Name = Name) and (Net.CPUID = -1) and (DedicateNetworks[CPUID].NetworkInterface = nil) then
    begin
      Net.CPUID := CPUID;
      DedicateNetworks[CPUID].NetworkInterface := Net;
      if @Handler <> nil then
      begin
        if PtrUInt(BeginThread(nil, 10*1024, @Handler, nil, DWORD(-1), ThreadID)) <> 0 then
          WriteConsoleF('Network Packets Service .... Thread %d\n',[ThreadID])
        else
        begin
          WriteConsoleF('Network Packets Service .... /RFail!/n\n',[]);
          Exit;
        end;
      end else
      begin
        if not LocalNetworkInit then
        begin
          DedicateNetworks[CPUID].NetworkInterface := nil;
          Exit;
        end;
      end;
      Network := @DedicateNetworks[CPUID];
      _IPAddress(IP, Network.IpAddress);
      _IPAddress(Gateway, Network.Gateway);
      _IPAddress(Mask, Network.Mask);
      WriteConsoleF('Network configuration:\n', []);
      WriteConsoleF('Local IP: /V%d.%d.%d.%d\n', [Network.Ipaddress and $ff, (Network.Ipaddress shr 8) and $ff, (Network.Ipaddress shr 16) and $ff, (Network.Ipaddress shr 24) and $ff ]);
      WriteConsoleF('/nGateway: /V%d.%d.%d.%d\n', [Network.Gateway and $ff, (Network.Gateway shr 8) and $ff, (Network.Gateway shr 16) and $ff, (Network.Gateway shr 24) and $ff ]);
      WriteConsoleF('/nMask: /V%d.%d.%d.%d/n\n', [Network.Mask and $ff, (Network.Mask shr 8) and $ff, (Network.Mask shr 16) and $ff, (Network.Mask shr 24) and $ff ]);
      {$IFDEF DebugNetwork} WriteDebug('DedicateNetwork: New Driver dedicated to CPU#%d\n', [CPUID]); {$ENDIF}
      Exit;
    end;
    Net := Net.Next;
  end;
  {$IFDEF DebugNetwork} WriteDebug('DedicateNetwork: fail, driver not found\n', []); {$ENDIF}
end;

procedure NetworkInit;
var
  I: LongInt;
begin
  WriteConsoleF('Loading Network Stack ...\n',[]);
  for I := 0 to MAX_CPU - 1 do
  begin
    DedicateNetworks[I].NetworkInterface := nil;
    DedicateNetworks[I].TranslationTable := nil;
    FillChar(DedicateNetworks[I].SocketStreamBitmap, SZ_SocketBitmap, 0);
    FillChar(DedicateNetworks[I].SocketDatagram, MAX_SocketPORTS*SizeOf(Pointer), 0);
    FillChar(DedicateNetworks[I].SocketStream, MAX_SocketPORTS*SizeOf(Pointer), 0);
  end;
end;

procedure DispatcherFlushPacket(Socket: PSocket);
var
  Buffer: PBufferSender;
  DataLen: UInt32;
  TcpHeader: PTCPHeader;
  TcpHeaderSize: LongInt;
begin
  if Socket.BufferSender = nil then
    Exit;
  if Socket.AckTimeOUT <> 0 then
  begin
    Buffer := Socket.BufferSender;
    if Socket.AckFlag then
    begin
      {$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: Socket %h Packet %h correctly sent\n', [PtrUInt(Socket),PtrUInt(Buffer.Packet)]); {$ENDIF}
      Socket.AckFlag := False; // clear the flag
      Socket.AckTimeOut:= 0;
      DataLen := Buffer.Packet.Size - (SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader));
      if Socket.BufferSender = Socket.BufferSenderTail then
        Socket.BufferSenderTail := nil;
      Buffer := Socket.BufferSender.NextBuffer;
      ToroFreeMem(Socket.BufferSender.Packet); // Free the packet
      ToroFreeMem(Socket.BufferSender); // Free the Buffer
      Socket.LastSequenceNumber := Socket.LastSequenceNumber+DataLen;
      Socket.BufferSender := Buffer;
      //if Socket.WinFlag then
      //begin
      //  Socket.WinCounter := read_rdtsc;
      //  Socket.WinTimeOut := WAIT_WIN*LocalCPUSpeed*1000;
      //  Exit;
      //end;
      if Buffer = nil then
        Exit;
    end else
    begin
      if Socket.AckTimeOut < read_rdtsc then
      begin
        {$IFDEF DebugSocket}WriteDebug('DispatcherFlushPacket: CheckTimeOut Exiting Socket %h\n', [PtrUInt(Socket)]);{$ENDIF}
        Exit;
      end;
      // Hardware problem !!!
      // TODO: To check this
      // we need to re-calculate the RDTSC register counter
      // the timer will be recalculated until the packet has been sent
      // The packet is still queued in Network Buffer
      //if not(Socket.BufferSender.Packet.Ready) then
      //begin
      //  Socket.BufferSender.Counter := read_rdtsc;
      //  Exit;
      //end;
      if Buffer.Attempts = 0 then
      begin
        Socket.State := SCK_BLOCKED;
        Socket.AckTimeOut := 0;
        Socket.DispatcherEvent := DISP_CLOSE;
        {$IFDEF DebugSocket} WriteDebug('DispatcherFlushPacket: 0 attempt Socket %h in state BLOCKED\n', [PtrUInt(Socket)]);{$ENDIF}
      end
      else
        Dec(Buffer.Attempts);
    end;
  end;
  Socket.ACKFlag := False;
  Socket.AckTimeOut := read_rdtsc + WAIT_ACK*LocalCPUSpeed*1000;
  TcpHeader:= Pointer(PtrUInt(Socket.BufferSender.Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
  TcpHeader.AckNumber := SwapDWORD(Socket.LastAckNumber);
  TcpHeader.SequenceNumber := SwapDWORD(Socket.LastSequenceNumber);
  TcpHeaderSize := Socket.BufferSender.Packet.Size - SizeOf(TEthHeader) - SizeOf(TIPHeader);
  TcpHeader.Checksum := TCP_CheckSum(DedicateNetworks[GetApicid].IpAddress, Socket.DestIp, PChar(TCPHeader), TcpHeaderSize);
  IPSendPacket(Socket.BufferSender.Packet, Socket.DestIp, IP_TYPE_TCP);
  {$IFDEF DebugSocket}WriteDebug('DispatcherFlushPacket: Socket %h sending packet %h, checksum: %d\n', [PtrUInt(Socket), PtrUInt(Socket.BufferSender.Packet), TcpHeader.Checksum]);{$ENDIF}
end;

procedure NetworkDispatcher(Handler: PNetworkHandler);
var
  NextSocket: PSocket;
  Service: PNetworkService;
  Socket: PSocket;
  DoDispatcherFlushPacket: Boolean;
begin
  DoDispatcherFlushPacket := True;
  Service := GetCurrentThread.NetworkService;
  NextSocket := Service.ClientSocket;
  while NextSocket <> nil do
  begin
    Socket := NextSocket;
    NextSocket := Socket.Next;
    //{$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h Handler: %h, Dispatcher Event: %d, Buffer Sender: %h Socket state: %d\n', [PtrUInt(Socket),PtrUInt(Handler),Socket.DispatcherEvent, PtrUInt(Socket.BufferSender), Socket.State]); {$ENDIF}
    case Socket.DispatcherEvent of
      DISP_ACCEPT :
        begin
          {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h Handler: %h, ACCEPT, Buffer Sender: %h, Service queue counter: %d\n', [PtrUInt(Socket),PtrUInt(Handler),PtrUInt(Socket.BufferSender), Service.ServerSocket.ConnectionsQueueCount]); {$ENDIF}
          Dec(Service.ServerSocket.ConnectionsQueueCount);
          Handler.DoAccept(Socket);
        end;
      DISP_CLOSING :
        begin
          {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h Handler: %h in DISP_CLOSING\n', [PtrUInt(Socket),PtrUInt(Handler)]); {$ENDIF}
          if Socket.BufferSender = nil then
          begin
            {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h Handler: %h Buffer Sender: %h closing\n', [PtrUInt(Socket),PtrUInt(Handler),PtrUInt(Socket.BufferSender)]); {$ENDIF}
            Socket.State := SCK_PEER_DISCONNECTED;
            SetSocketTimeOut(Socket, WAIT_ACK);
            TCPSendPacket(TCP_ACK or TCP_FIN, Socket);
            Socket.DispatcherEvent := DISP_ZOMBIE;
          end;
        end;
      DISP_WAITING:
        begin
          //{$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h in DISP_WAITING, TimeOut: %d, rdtsc: %d\n', [PtrUInt(Socket), Socket.TimeOut, read_rdtsc]); {$ENDIF}
          if Socket.TimeOut < read_rdtsc then
          begin
            {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h, DISP_WAITING Timeout\n', [PtrUInt(Socket)]); {$ENDIF}
            if Socket.State = SCK_CONNECTING then
            begin
              Socket.State := SCK_BLOCKED;
              Handler.DoConnectFail(Socket)
            end else if Socket.State = SCK_LOCALCLOSING then
            begin
              {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h, SCK_LOCALCLOSING, freeing \n', [PtrUInt(Socket)]); {$ENDIF}
              FreeSocket(Socket)
            end else if Socket.State = SCK_PEER_DISCONNECTED then
            begin
              if Socket.RemoteClose then
              begin
                FreeSocket(Socket);
                {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h, SCK_PEER_DISCONNECTED, freeing\n', [PtrUInt(Socket)]); {$ENDIF}
              end else
              begin
                Socket.DispatcherEvent := DISP_ZOMBIE;
                {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h, SCK_PEER_DISCONNECTED, going zombie\n', [PtrUInt(Socket)]); {$ENDIF}
              end;
            end else if Socket.State = SCK_NEGOTIATION then
            begin
              // TODO: We should not wait for everything
              SetSocketTimeOut(Socket, WAIT_ACK);
              {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h in SCK_NEGOTIATION, setting new timeout\n', [PtrUInt(Socket)]); {$ENDIF}
              DoDispatcherFlushPacket := False;
            end else if Socket.State = SCK_CLOSED then
            begin
              {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h, SCK_CLOSED, Freeing Socket\n', [PtrUInt(Socket)]); {$ENDIF}
              FreeSocket(Socket);
              DoDispatcherFlushPacket := False;
            end else
            begin
              Socket.DispatcherEvent := DISP_TIMEOUT;
              {$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Socket: %h, DoTimeOut(), State: %d\n', [PtrUInt(Socket), Socket.State]); {$ENDIF}
              Handler.DoTimeOut(Socket)
            end
          end;
        end;
      DISP_RECEIVE: Handler.DoReceive(Socket);
      DISP_CLOSE: Handler.DoClose(Socket);
      DISP_CONNECT: Handler.DoConnect(Socket);
    end;
    if DoDispatcherFlushPacket then
    begin
      DispatcherFlushPacket(Socket);
      //{$IFDEF DebugSocket} WriteDebug('NetworkDispatcher: Flushed %h\n', [PtrUInt(Socket.BufferSender)]); {$ENDIF}
    end;
  end;
end;

function DoNetworkService(Handler: PNetworkHandler): LongInt;
var
  Service: PNetworkService;
begin
  Handler.DoInit;
  {$IFDEF DebugSocket} WriteDebug('DoNetworkService: DoInit in Handler: %h\n', [PtrUInt(Handler)]); {$ENDIF}
  while True do
  begin
    NetworkDispatcher(Handler);
    Service := GetCurrentThread.NetworkService;
    if Service.ClientSocket = nil then
      SysThreadSwitch(True)
    else
      SysThreadSwitch;
  end;
  Result := 0;
end;

procedure SysRegisterNetworkService(Handler: PNetworkHandler);
var
  Service: PNetworkService;
  Thread: PThread;
  ThreadID: TThreadID; // FPC was using ThreadVar ThreadID
begin
  Service := ToroGetMem(SizeOf(TNetworkService));
  if Service = nil then
    Exit;
  ThreadID := BeginThread(nil, ServiceStack, @DoNetworkService, Handler, DWORD(-1), ThreadID);
  Thread := Pointer(ThreadID);
  if Thread = nil then
  begin
    ToroFreeMem(Service);
    Exit;
  end;
  Thread.NetworkService := Service;
  Service.ServerSocket := nil;
  Service.ClientSocket := nil;
  {$IFDEF DebugSocket} WriteDebug('SysRegisterNetworkService: Thread %d, Handler: %h\n', [ThreadID,PtrUInt(Handler)]); {$ENDIF}
end;

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
  Socket.DispatcherEvent := DISP_ZOMBIE;
  Socket.State := 0;
  Socket.SocketType := SocketType;
  Socket.BufferLength := 0;
  Socket.Buffer := nil;
  Socket.AckFlag := False;
  Socket.AckTimeOut := 0;
  Socket.BufferSender := nil;
  Socket.RemoteClose := False;
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
  for J := 0 to MAX_SocketPorts-USER_START_PORT do
  begin
    if not Bit_Test(bitmap, J) then
    begin
      Bit_Set(bitmap, J);
      Result := J + USER_START_PORT;
      Exit;
    end;
  end;
  Result := USER_START_PORT-1;
end;

function SysSocketConnect(Socket: PSocket): Boolean;
var
  CPUID: LongInt;
  Service: PNetworkService;
begin
  CPUID:= GetApicid;
  Socket.Buffer := ToroGetMem(MAX_WINDOW);
  if Socket.Buffer = nil then
  begin
    Result:=False;
    Exit;
  end;
  Socket.SourcePort := GetFreePort;
  if Socket.SourcePort < USER_START_PORT then
  begin
    ToroFreeMem(Socket.Buffer);
    Socket.SourcePort:= 0 ;
    Result := False;
    Exit;
  end;
  Socket.State := SCK_CONNECTING;
  Socket.mode := MODE_CLIENT;
  Socket.NeedFreePort := True;
  Socket.BufferLength := 0;
  Socket.BufferLength:=0;
  Socket.BufferReader:= Socket.Buffer;
  Service := GetCurrentThread.NetworkService;
  DedicateNetworks[CPUID].SocketStream[Socket.SourcePort]:= Service ;
  Socket.Next := Service.ClientSocket;
  Service.ClientSocket := Socket;
  {$IFDEF DebugSocket} WriteDebug('SysSocketConnect: Connecting from Port %d to Port %d\n', [Socket.SourcePort, Socket.DestPort]); {$ENDIF}
  Socket.LastAckNumber := 0;
  Socket.LastSequenceNumber := 300;
  TcpSendPacket(TCP_SYN, Socket);
  SetSocketTimeOut(Socket,WAIT_ACK);
  Result := True;
end;

procedure SysSocketClose(Socket: PSocket);
begin
  DisableInt;
  {$IFDEF DebugSocket} WriteDebug('SysSocketClose: Closing Socket %h in port %d, Buffer Sender %h, Dispatcher %d\n', [PtrUInt(Socket),Socket.SourcePort, PtrUInt(Socket.BufferSender),Socket.DispatcherEvent]); {$ENDIF}
  if Socket.RemoteClose then
  begin
    if Socket.BufferSender = nil then
    begin
      Socket.State := SCK_PEER_DISCONNECTED;
      SetSocketTimeOut(Socket, WAIT_ACK);
      TCPSendPacket(TCP_ACK or TCP_FIN, Socket);
      {$IFDEF DebugSocket} WriteDebug('SysSocketClose: send FINACK in Socket %h with RemoteClose\n', [PtrUInt(Socket)]); {$ENDIF}
    end else
    begin
      Socket.DispatcherEvent := DISP_CLOSING;
      {$IFDEF DebugSocket} WriteDebug('SysSocketClose: Socket %h in DISP_CLOSING with RemoteClose\n', [PtrUInt(Socket)]); {$ENDIF}
    end;
  end
  else
  begin
    if Socket.BufferSender = nil then
    begin
      Socket.State := SCK_PEER_DISCONNECTED;
      SetSocketTimeOut(Socket, WAIT_ACK);
      TCPSendPacket(TCP_ACK or TCP_FIN, Socket);
      {$IFDEF DebugSocket} WriteDebug('SysSocketClose: send FINACK in Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
    end else
    begin
      Socket.DispatcherEvent := DISP_CLOSING;
      {$IFDEF DebugSocket} WriteDebug('SysSocketClose: Socket %h in DISP_CLOSING\n', [PtrUInt(Socket)]); {$ENDIF}
    end;
  end;
  RestoreInt;
end;

function SysSocketListen(Socket: PSocket; QueueLen: LongInt): Boolean;
var
  CPUID: LongInt;
  Service: PNetworkService;
begin
  CPUID := GetApicid;
  Result := False;
  if Socket.SocketType <> SOCKET_STREAM then
    Exit;
  if Socket.SourcePORT >= USER_START_PORT then
    Exit;
  Service := DedicateNetworks[CPUID].SocketStream[Socket.SourcePort];
  if Service <> nil then
   Exit;
  Service:= GetCurrentThread.NetworkService;
  Service.ServerSocket := Socket;
  DedicateNetworks[CPUID].SocketStream[Socket.SourcePort]:= Service;
  Socket.State := SCK_LISTENING;
  Socket.Mode := MODE_SERVER;
  Socket.NeedfreePort := False;
  Socket.ConnectionsQueueLen := QueueLen;
  Socket.ConnectionsQueueCount := 0;
  Socket.DestPort:=0;
  Result := True;
  {$IFDEF DebugSocket} WriteDebug('SysSocketListen: Socket listening at Local Port: %d, Buffer Sender: %h, QueueLen: %d\n', [Socket.SourcePort,PtrUInt(Socket.BufferSender),QueueLen]); {$ENDIF}
end;

function SysSocketPeek(Socket: PSocket; Addr: PChar; AddrLen: UInt32): LongInt;
var
  FragLen: LongInt;
begin
  {$IFDEF DebugSocket} WriteDebug('SysSocketPeek BufferLength: %d\n', [Socket.BufferLength]); {$ENDIF}
  Result := 0;
  if (Socket.State <> SCK_TRANSMITTING) or (AddrLen=0) or (Socket.Buffer+Socket.BufferLength = Socket.BufferReader) then
  begin
    {$IFDEF DebugSocket} WriteDebug('SysSocketPeek -> Exit\n', []); {$ENDIF}
    Exit;
  end;
  while (AddrLen > 0) and (Socket.State = SCK_TRANSMITTING) do
  begin
    if Socket.BufferLength > AddrLen then
    begin
      FragLen := AddrLen;
      AddrLen := 0;
    end else
    begin
      FragLen := Socket.BufferLength;
      AddrLen := 0;
    end;
    Move(Socket.BufferReader^, Addr^, FragLen);
    {$IFDEF DebugSocket} WriteDebug('SysSocketPeek:  %q bytes from port %d to port %d\n', [PtrUInt(FragLen), Socket.SourcePort, Socket.DestPort]); {$ENDIF}
    Result := Result + FragLen;
  end;
end;

function SysSocketRecv(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32): LongInt;
var
  FragLen: LongInt;
  PendingBytes: LongInt;
begin
  {$IFDEF DebugSocket} WriteDebug('SysSocketRecv: BufferLength: %d\n', [Socket.BufferLength]); {$ENDIF}
  Result := 0;
  if (Socket.State <> SCK_TRANSMITTING) or (AddrLen=0) or (Socket.BufferReader = Socket.Buffer+Socket.BufferLength) then
  begin
    {$IFDEF DebugSocket} WriteDebug('SysSocketRecv -> Exit\n', []); {$ENDIF}
    Exit;
  end;
  while (AddrLen > 0) and (Socket.State = SCK_TRANSMITTING) do
  begin
    PendingBytes := Socket.BufferLength - (PtrUInt(Socket.BufferReader)-PtrUInt(Socket.Buffer));
    {$IFDEF DebugSocket} WriteDebug('SysSocketRecv: AddrLen: %d PendingBytes: %d\n', [AddrLen, PendingBytes]); {$ENDIF}
    if AddrLen > PendingBytes then
      FragLen := PendingBytes
    else
      FragLen := AddrLen;
    Dec(AddrLen, FragLen);
    Move(Socket.BufferReader^, Addr^, FragLen);
    {$IFDEF DebugSocket} WriteDebug('SysSocketRecv: Receiving from %h to %h count: %d\n', [PtrUInt(Socket.BufferReader), PtrUInt(Addr), FragLen]); {$ENDIF}
    Inc(Result, FragLen);
    Inc(Socket.BufferReader, FragLen);
    if Socket.BufferReader = Socket.Buffer+Socket.BufferLength then
    begin
      {$IFDEF DebugSocket} WriteDebug('SysSocketRecv: Reseting Socket.BufferReader\n', []); {$ENDIF}
      Socket.BufferReader := Socket.Buffer;
      Socket.BufferLength := 0;
      Break;
    end;
  end;
end;

function SysSocketSelect(Socket: PSocket; TimeOut: LongInt): Boolean;
begin
  Result := True;
  {$IFDEF DebugSocket} WriteDebug('SysSocketSelect: Socket %h TimeOut: %d\n', [PtrUInt(Socket), TimeOut]); {$ENDIF}
  if Socket.State = SCK_LOCALCLOSING then
  begin
    Socket.DispatcherEvent := DISP_CLOSE;
    {$IFDEF DebugSocket} WriteDebug('SysSocketSelect: Socket %h in SCK_LOCALCLOSING, executing DISP_CLOSE\n', [PtrUInt(Socket)]); {$ENDIF}
    Exit;
  end;
  if Socket.BufferReader < Socket.Buffer+Socket.BufferLength then
  begin
    Socket.DispatcherEvent := DISP_RECEIVE;
    {$IFDEF DebugSocket} WriteDebug('SysSocketSelect: Socket %h executing, DISP_RECEIVE\n', [PtrUInt(Socket)]); {$ENDIF}
    Exit;
  end;
  SetSocketTimeOut(Socket, TimeOut);
  {$IFDEF DebugSocket} WriteDebug('SysSocketSelect: Socket %h set timeout\n', [PtrUInt(Socket)]); {$ENDIF}
end;

// Send data to Remote Host using a Client Socket
// every packet is sent with ACKPSH bit, with the maximum size possible
//
// TODO: check the return values
function SysSocketSend(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32): LongInt;
var
  Buffer: PBufferSender;
  Dest: PByte;
  FragLen: UInt32;
  P: PChar;
  Packet: PPacket;
  TCPHeader: PTCPHeader;
begin
  P := Addr;
  Result := AddrLen;
  {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Socket: %h Addr: %d Size: %d, BufferSender: %h\n',[PtrUInt(Socket),PtrUInt(Addr),AddrLen,PtrUInt(Socket.BufferSender)]);{$ENDIF}
  while Addrlen > 0 do
  begin
    if Addrlen > MTU then
      FragLen := MTU
    else
      FragLen := Addrlen;
    if Fraglen > Socket.RemoteWinCount then
      Fraglen := Socket.RemoteWinCount;
    Packet := ToroGetMem(SizeOf(TPacket)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader)+FragLen);
    if Packet = nil then
      Exit;
    Buffer := ToroGetMem(SizeOf(TBufferSender));
    if Buffer = nil then
    begin
      ToroFreeMem(Packet);
      Exit;
    end;
    Socket.RemoteWinCount := Socket.RemoteWinCount - Fraglen;
    if Socket.RemoteWinCount = 0 then
      Socket.RemoteWinCount := Socket.RemoteWinLen;
    Packet.Data := Pointer(PtrUInt(Packet) + SizeOf(TPacket));
    Packet.Size := SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader)+FragLen;
    Packet.ready := False;
    Packet.Delete := False;
    Packet.Next := nil;
    TcpHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
    FillChar(TCPHeader^, SizeOf(TTCPHeader), 0);
    Dest := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader));
    {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Moving from %h to %h len %d\n',[PtrUInt(P),PtrUInt(Dest),FragLen]);{$ENDIF}
    Move(P^, Dest^, FragLen);
    if AddrLen <= MTU then
      TcpHeader.Flags := TCP_ACKPSH
    else
      TcpHeader.Flags := TCP_ACK;
    TcpHeader.Header_Length := (SizeOf(TTCPHeader) div 4) shl 4;
    TcpHeader.SourcePort := SwapWORD(Socket.SourcePort);
    TcpHeader.DestPort := SwapWORD(Socket.DestPort);
    TcpHeader.Window_Size := SwapWORD(MAX_WINDOW - Socket.BufferLength);
    Buffer.Packet := Packet;
    Buffer.NextBuffer := nil;
    Buffer.Attempts := 2;
    {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enqueing sender Buffer\n',[PtrUInt(P),PtrUInt(Dest),FragLen]);{$ENDIF}
    if Socket.BufferSender = nil then
    begin
      Socket.BufferSender := Buffer;
      Socket.BufferSenderTail := Buffer;
      {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enquing first %h\n',[PtrUInt(Socket.BufferSender)]);{$ENDIF}
    end else
    begin
      {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enquing in last buffer %h\n',[PtrUInt(Socket.BufferSender)]);{$ENDIF}
      Socket.BufferSenderTail.NextBuffer := Buffer;
      Socket.BufferSenderTail := Buffer;
      {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enqued last sender Buffer\n',[]);{$ENDIF}
    end;
      {$IFDEF DebugSocket} WriteDebug('SysSocketSend: Enqued sender Buffer\n',[]);{$ENDIF}
    Dec(AddrLen, FragLen);
    Inc(P, FragLen);
  end;
//{$IFDEF DebugSocket} WriteDebug('SysSocketSend: END\n',[]);{$ENDIF}
end;

end.



