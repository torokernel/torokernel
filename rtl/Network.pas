//
// Network.pas
//
// This unit contains the code to support vsocket communication.
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

unit Network;

interface

{$I Toro.inc}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Arch, Process, Console, Memory;

const
  SOCKET_STREAM = 2;
  MAX_SocketPORTS = 20000;
  MAX_WINDOW = $4000;
  USER_START_PORT = 10000;
  // size of the bitmap in bytes
  SZ_SocketBitmap = (MAX_SocketPORTS - USER_START_PORT) div 8;
  ServiceStack = 40*1024;

  VIRTIO_VSOCK_OP_INVALID = 0;
  VIRTIO_VSOCK_OP_REQUEST = 1;
  VIRTIO_VSOCK_OP_RW = 5;
  VIRTIO_VSOCK_OP_RESPONSE = 2;
  VIRTIO_VSOCK_OP_SHUTDOWN = 4;
  VIRTIO_VSOCK_OP_RST = 3;
  VIRTIO_VSOCK_OP_CREDIT_UPDATE = 6;
  VIRTIO_VSOCK_TYPE_STREAM = 1;
  VIRTIO_VSOCK_MAX_PKT_BUF_SIZE = 64 * 1024;
  MAX_NET_NAME = 30;

type
  PNetworkInterface = ^TNetworkInterface;
  PPacket = ^TPacket;
  PSocket = ^TSocket;
  PBufferSender = ^TBufferSender;
  TIPAddress = DWORD;
  PNetworkService = ^TNetworkService;

  TPacket = record
    Size: LongInt;
    Data: Pointer;
    Status: Boolean;
    Ready: Boolean;
    Delete: Boolean;
    Next: PPacket;
  end;

  TNetworkInterface = record
    Name: array[0..MAX_NET_NAME-1] of Char;
    Minor: LongInt;
    Device: Pointer;
    IncomingPacketTail: PPacket;
    IncomingPackets: PPacket;
    OutgoingPacketTail: PPacket;
    OutgoingPackets: PPacket;
    Start: procedure (NetInterface: PNetworkInterface);
    Send: procedure (NetInterface: PNetWorkInterface;Packet: PPacket);
    Reset: procedure (NetInterface: PNetWorkInterface);
    Stop: procedure (NetInterface: PNetworkInterface);
    CPUID: LongInt;
    Next: PNetworkInterface;
  end;

  PTANetworkService = ^TANetworkService;
  TANetworkService = array[0..0] of PNetworkService;

  TNetworkDedicate = record
    NetworkInterface: PNetworkInterface;
    IpAddress: TIPAddress;
    SocketStream: PTANetworkService;
    SocketStreamBitmap: array[0..SZ_SocketBitmap-1] of Byte;
    SocketDatagram: PTANetworkService;
    SocketDatagramBitmap: array[0..SZ_SocketBitmap-1] of Byte;
  end;
  PNetworkDedicate = ^TNetworkDedicate;

  TSocket = record
    SourcePort,DestPort: UInt32;
    DestIp: TIPAddress;
    SocketType: LongInt;
    Mode: LongInt;
    State: LongInt;
    RemoteWinLen: UInt32;
    RemoteWinCount: UInt32;
    BufferReader: PChar;
    BufferLength: UInt32;
    Buffer: PChar;
    ConnectionsQueueLen: LongInt;
    ConnectionsQueueCount: LongInt;
    NeedFreePort: Boolean;
    DispatcherEvent: LongInt;
    TimeOut: Int64;
    BufferSenderTail: PBufferSender;
    BufferSender: PBufferSender;
    UserDefined: Pointer;
    Blocking: Boolean;
    Next: PSocket;
  end;

  TNetworkService = record
    ServerSocket: PSocket;
    ClientSocket: PSocket;
  end;

  TBufferSender = record
    Packet: PPacket;
    Attempts: LongInt;
    NextBuffer: PBufferSender;
  end;

  PVirtIOVSocketPacket = ^VirtIOVSocketPacket;
  TVirtIOVSockHdr = packed record
    src_cid: QWORD;
    dst_cid: QWORD;
    src_port: DWORD;
    dst_port: DWORD;
    len: DWORD;
    tp: WORD;
    op: WORD;
    flags: DWORD;
    buf_alloc: DWORD;
    fwd_cnt: DWORD;
  end;

  VirtIOVSocketPacket = packed record
    hdr: TVirtIOVSockHdr;
    data: array[0..0] of Byte;
  end;

  TVirtIOVSockEvent = record
    ID: DWORD;
  end;

function SysSocket(SocketType: LongInt): PSocket;
procedure SysSocketClose(Socket: PSocket);
function SysSocketConnect(Socket: PSocket): Boolean;
function SysSocketListen(Socket: PSocket; QueueLen: LongInt): Boolean;
function SysSocketAccept(Socket: PSocket): PSocket;
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
procedure DedicateNetworkSocket(const Name: PXChar);

implementation

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}

var
  DedicateNetworks: array[0..MAX_CPU-1] of TNetworkDedicate;
  NetworkInterfaces: PNetworkInterface = nil;

const
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

  // Socket Dispatcher State
  DISP_WAITING = 0;
  DISP_ACCEPT = 1;
  DISP_RECEIVE = 2;
  DISP_CONNECT = 3;
  DISP_TIMEOUT = 4;
  DISP_CLOSE = 5;
  DISP_ZOMBIE = 6;
  DISP_CLOSING = 7;

  PERCPUCURRENTNET = 3;

function GetNetwork: PNetworkDedicate; inline;
begin
  Result := Pointer(GetGSOffset(PERCPUCURRENTNET * sizeof(QWORD)));
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

procedure SetSocketTimeOut(Socket: PSocket; TimeOut: Int64); inline;
begin
  Socket.TimeOut := read_rdtsc + TimeOut * LocalCPUSpeed * 1000;
  Socket.DispatcherEvent := DISP_WAITING;
  {$IFDEF DebugSocket}WriteDebug('SetSocketTimeOut: Socket %h, SocketTimeOut: %d, TimeOut: %d\n', [PtrUInt(Socket), Socket.TimeOut, TimeOut]);{$ENDIF}
end;

procedure SysNetworkSend(Packet: PPacket);
var
  NetworkInterface: PNetworkInterface;
begin
  NetworkInterface := GetNetwork.NetworkInterface;
  Packet.Ready := False; // the packet has been sent when Ready = True
  Packet.Status := False;
  Packet.Next := nil;
  {$IFDEF DebugNetwork}WriteDebug('SysNetworkSend: sending packet %h\n', [PtrUInt(Packet)]);{$ENDIF}
  NetworkInterface.Send(NetworkInterface, Packet);
  {$IFDEF DebugNetwork}WriteDebug('SysNetworkSend: sent packet %h\n', [PtrUInt(Packet)]);{$ENDIF}
end;

// Inform the Kernel that the last packet has been sent, returns the next packet to be sent
function DequeueOutgoingPacket: PPacket;
var
  Packet: PPacket;
begin
  Packet := GetNetwork.NetworkInterface.OutgoingPackets;
  If Packet = nil then
  begin
    {$IFDEF DebugNetwork}WriteDebug('DequeueOutgoingPacket: OutgoingPackets = NULL\n', []);{$ENDIF}
    Result := nil;
    Exit;
  end;
  GetNetwork.NetworkInterface.OutgoingPackets := Packet.Next;
  if Packet.Next = nil then
  begin
     GetNetwork.NetworkInterface.OutgoingPacketTail := nil
  end;
  Result := GetNetwork.NetworkInterface.OutgoingPackets;
  if Packet.Delete then
  begin
    {$IFDEF DebugNetwork}WriteDebug('DequeueOutgoingPacket: Freeing packet %h\n', [PtrUInt(Packet)]);{$ENDIF}
    ToroFreeMem(Packet);
    Exit;
  end;
  Packet.Ready := True;
end;

// Inform the Kernel that a new Packet has arrived
// This procedure is not interruption-safe so caller needs to disable interruptions
procedure EnqueueIncomingPacket(Packet: PPacket);
var
  PacketQueue: PPacket;
begin
  {$IFDEF DebugNetwork}WriteDebug('EnqueueIncomingPacket: new packet: %h\n', [PtrUInt(Packet)]); {$ENDIF}
  PacketQueue := GetNetwork.NetworkInterface.IncomingPackets;
  Packet.Next := nil;
  if PacketQueue = nil then
  begin
    GetNetwork.NetworkInterface.IncomingPackets := Packet;
    {$IFDEF DebugNetwork}
      if GetNetwork.NetworkInterface.IncomingPacketTail <> nil then
      begin
        WriteDebug('EnqueueIncomingPacket: IncomingPacketTail <> nil\n', []);
      end;
    {$ENDIF}
  end else
  begin
    GetNetwork.NetworkInterface.IncomingPacketTail.Next := Packet;
  end;
  GetNetwork.NetworkInterface.IncomingPacketTail := Packet
end;

procedure FreePort(LocalPort: LongInt);
var
  Bitmap: Pointer;
begin
  Bitmap := @GetNetwork.SocketStreamBitmap[0];
  Bit_Set(Bitmap, LocalPort);
end;

procedure FreeSocket(Socket: PSocket);
var
  ClientSocket: PSocket;
  Service: PNetworkService;
  tmp, tmp2: PBufferSender;
begin
  {$IFDEF DebugSocket} WriteDebug('FreeSocket: Freeing Socket %h\n', [PtrUInt(Socket)]); {$ENDIF}
  Service := GetNetwork.SocketStream[Socket.SourcePort];
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
      GetNetwork.SocketStream[Socket.SourcePort] := nil
    else
      GetNetwork.SocketDatagram[Socket.SourcePort] := nil;
    FreePort(Socket.SourcePort);
    ToroFreeMem(Service);
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

// Read a packet from Buffer of local Network Interface
function SysNetworkRead: PPacket;
var
  Packet: PPacket;
begin
  DisableInt;
  Packet := GetNetwork.NetworkInterface.IncomingPackets;
  if Packet=nil then
    Result := nil
  else
  begin
    GetNetwork.NetworkInterface.IncomingPackets := Packet.Next;
    If Packet.Next = nil then
      GetNetwork.NetworkInterface.IncomingPacketTail := nil;
    Packet.Next := nil;
    Result := Packet;
    {$IFDEF DebugNetwork}WriteDebug('SysNetworkRead: getting packet: %h\n', [PtrUInt(Packet)]); {$ENDIF}
  end;
  RestoreInt;
end;

procedure VSocketReset(DstCID, DstPort, LocalPort: DWORD);
var
  Packet: PPacket;
  VPacket: PVirtIOVSocketPacket;
begin
  Packet := ToroGetMem(sizeof(TPacket)+ sizeof(TVirtIOVSockHdr));
  Packet.Data := Pointer(PtrUInt(Packet)+ sizeof(TPacket));
  Packet.Size := sizeof(TVirtIOVSockHdr);
  Packet.Ready := False;
  Packet.Delete := False;
  Packet.Next := nil;
  VPacket := Pointer(Packet.Data);
  VPacket.hdr.src_cid := GetNetwork.NetworkInterface.Minor;
  VPacket.hdr.dst_cid := DstCID;
  VPacket.hdr.src_port := LocalPort;
  VPacket.hdr.dst_port := DstPort;
  VPacket.hdr.flags := 0;
  VPacket.hdr.tp := VIRTIO_VSOCK_TYPE_STREAM;
  VPacket.hdr.op := VIRTIO_VSOCK_OP_RST;
  VPacket.hdr.len := 0;
  SysNetworkSend(Packet);
  ToroFreeMem(Packet);
end;

function VSocketValidateIncomingConnection(tp, LocalPort: DWORD): PNetworkService;
var
  Service: PNetworkService;
  ServerSocket: PSocket;
begin
  Result := nil;
  if tp <> VIRTIO_VSOCK_TYPE_STREAM then
    Exit;
  Service := GetNetwork.SocketStream[LocalPort];
  if (Service = nil) or (Service.ServerSocket = nil) then
    Exit;
  ServerSocket := Service.ServerSocket;
  if ServerSocket.ConnectionsQueueCount = ServerSocket.ConnectionsQueueLen then
    Exit;
  Result := Service;
end;

function VSocketGetClient(LocalPort, RemotePort: DWORD): PSocket;
var
  Service: PNetworkService;
  Socket: PSocket;
begin
  Result := nil;
  Service := GetNetwork.SocketStream[LocalPort];
  if (Service = nil) or (Service.ClientSocket = nil) then
    Exit;
  Socket := Service.ClientSocket;
  while Socket <> nil do
  begin
    if Socket.DestPort = RemotePort then
    begin
      Result := Socket;
      Exit;
    end;
    Socket := Socket.Next;
  end;
end;

function VSocketInit: PSocket;
var
  ClientSocket: PSocket;
  Buffer: Pointer;
begin
  Result := nil;
  ClientSocket := ToroGetMem(SizeOf(TSocket));
  if ClientSocket = nil then
    Exit;
  Buffer := ToroGetMem(MAX_WINDOW);
  if Buffer = nil then
  begin
    ToroFreeMem(ClientSocket);
    Exit;
  end;
  ClientSocket.State := SCK_TRANSMITTING;
  ClientSocket.BufferLength := 0;
  ClientSocket.Buffer := Buffer;
  ClientSocket.BufferReader := ClientSocket.Buffer;
  ClientSocket.SocketType := SOCKET_STREAM;
  ClientSocket.DispatcherEvent := DISP_ACCEPT;
  ClientSocket.Mode := MODE_CLIENT;
  ClientSocket.BufferSender := nil;
  ClientSocket.BufferSenderTail := nil;
  ClientSocket.NeedFreePort := False;
  Result := ClientSocket;
end;

procedure VSocketResponse(Socket: PSocket);
var
  Packet: PPacket;
  VPacket: PVirtIOVSocketPacket;
begin
  Packet := ToroGetMem(sizeof(TPacket)+ sizeof(TVirtIOVSockHdr));
  Packet.Data := Pointer(PtrUInt(Packet)+ sizeof(TPacket));
  Packet.Size := sizeof(TVirtIOVSockHdr);
  Packet.Ready := False;
  Packet.Delete := False;
  Packet.Next := nil;
  VPacket := Pointer(Packet.Data);
  VPacket.hdr.src_cid := GetNetwork.NetworkInterface.Minor;
  VPacket.hdr.dst_cid := Socket.DestIp;
  VPacket.hdr.src_port := Socket.SourcePort;
  VPacket.hdr.dst_port := Socket.DestPort;
  VPacket.hdr.flags := 0;
  VPacket.hdr.op := VIRTIO_VSOCK_OP_RESPONSE;
  VPacket.hdr.tp := VIRTIO_VSOCK_TYPE_STREAM;
  VPacket.hdr.len := 0;
  VPacket.hdr.buf_alloc := MAX_WINDOW;
  VPacket.hdr.fwd_cnt := 0;
  SysNetworkSend(Packet);
  ToroFreeMem(Packet);
end;

procedure VSocketUpdateCredit(Socket: PSocket);
var
  Packet: PPacket;
  VPacket: PVirtIOVSocketPacket;
begin
  Packet := ToroGetMem(sizeof(TPacket)+ sizeof(TVirtIOVSockHdr));
  Packet.Data := Pointer(PtrUInt(Packet)+ sizeof(TPacket));
  Packet.Size := sizeof(TVirtIOVSockHdr);
  Packet.Ready := False;
  Packet.Delete := False;
  Packet.Next := nil;
  VPacket := Pointer(Packet.Data);
  VPacket.hdr.src_cid := GetNetwork.NetworkInterface.Minor;
  VPacket.hdr.dst_cid := Socket.DestIP;
  VPacket.hdr.op := VIRTIO_VSOCK_OP_CREDIT_UPDATE;
  VPacket.hdr.tp := VIRTIO_VSOCK_TYPE_STREAM;
  VPacket.hdr.src_port := Socket.SourcePort;
  VPacket.hdr.dst_port := Socket.DestPort;
  VPacket.hdr.buf_alloc := MAX_WINDOW;
  VPacket.hdr.fwd_cnt := Socket.BufferLength;
  VPacket.hdr.len := 0;
  VPacket.hdr.flags := 0;
  SysNetworkSend(Packet);
  ToroFreeMem(Packet);
end;

function ProcessSocketPacket(Param: Pointer): PtrUInt;
var
  Packet: PPacket;
  VPacket: PVirtIOVSocketPacket;
  Service: PNetworkService;
  ClientSocket: PSocket;
  Source, Dest: PByte;
  total: DWORD;
begin
  {$IFDEF FPC} Result := 0; {$ENDIF}
  while True do
  begin
    Packet := SysNetworkRead;
    if Packet = nil then
    begin
      SysSetCoreIdle;
      Continue;
    end;
    VPacket := Packet.Data;
    case VPacket.hdr.op of
      VIRTIO_VSOCK_OP_REQUEST:
        begin
          Service := VSocketValidateIncomingConnection(VPacket.hdr.tp, VPacket.hdr.dst_port);
          if Service = nil then
            VSocketReset(VPacket.hdr.src_cid, VPacket.hdr.src_port, VPacket.hdr.dst_port)
          else
          begin
            ClientSocket := VSocketInit();
            if ClientSocket <> nil then
            begin
              Inc(Service.ServerSocket.ConnectionsQueueCount);
              ClientSocket.Next := Service.ClientSocket;
              Service.ClientSocket := ClientSocket;
              ClientSocket.SourcePort := VPacket.hdr.dst_port;
              ClientSocket.DestPort := VPacket.hdr.src_port;
              ClientSocket.DestIp := VPacket.hdr.src_cid;
              ClientSocket.RemoteWinLen := VPacket.hdr.buf_alloc;
              ClientSocket.RemoteWinCount := VPacket.hdr.fwd_cnt;
              ClientSocket.Blocking := Service.ServerSocket.Blocking;
              VSocketResponse(ClientSocket);
            end else
              VSocketReset(VPacket.hdr.src_cid, VPacket.hdr.src_port, VPacket.hdr.dst_port);
          end;
        end;
      VIRTIO_VSOCK_OP_RW:
        begin
          ClientSocket := VSocketGetClient(VPacket.hdr.dst_port, VPacket.hdr.src_port);
          if ClientSocket <> nil then
          begin
            Source := Pointer(PtrUInt(@VPacket.data));
            Dest := Pointer(PtrUInt(ClientSocket.Buffer)+ClientSocket.BufferLength);
            if  ClientSocket.BufferLength + VPacket.hdr.len > MAX_WINDOW then
              total := MAX_WINDOW - ClientSocket.BufferLength
            else
              total :=  VPacket.hdr.len;
            Move(Source^, Dest^, total);
            Inc(ClientSocket.BufferLength, total);
            VSocketUpdateCredit(ClientSocket);
          end else
            VSocketReset(VPacket.hdr.src_cid, VPacket.hdr.src_port, VPacket.hdr.dst_port);
        end;
      VIRTIO_VSOCK_OP_SHUTDOWN:
        begin
          ClientSocket := VSocketGetClient(VPacket.hdr.dst_port, VPacket.hdr.src_port);
          if ClientSocket <> nil then
          begin
            If ClientSocket.State = SCK_TRANSMITTING then
            begin
              ClientSocket.State := SCK_LOCALCLOSING;
              VSocketReset(VPacket.hdr.src_cid, VPacket.hdr.src_port, VPacket.hdr.dst_port);
            end;
          end else
            VSocketReset(VPacket.hdr.src_cid, VPacket.hdr.src_port, VPacket.hdr.dst_port);
        end;
      VIRTIO_VSOCK_OP_CREDIT_UPDATE:
        begin
          ClientSocket := VSocketGetClient(VPacket.hdr.dst_port, VPacket.hdr.src_port);
          if ClientSocket <> nil then
            ClientSocket.RemoteWinCount := VPacket.hdr.fwd_cnt
          else
            VSocketReset(VPacket.hdr.src_cid, VPacket.hdr.src_port, VPacket.hdr.dst_port);
        end;
      VIRTIO_VSOCK_OP_RST:
        begin
          ClientSocket := VSocketGetClient(VPacket.hdr.dst_port, VPacket.hdr.src_port);
          if ClientSocket <> nil then
          begin
            If ClientSocket.State = SCK_PEER_DISCONNECTED then
              FreeSocket(ClientSocket)
            else if ClientSocket.State = SCK_CONNECTING then
              ClientSocket.State := SCK_BLOCKED;
          end else
              VSocketReset(VPacket.hdr.src_cid, VPacket.hdr.src_port, VPacket.hdr.dst_port);
        end;
      VIRTIO_VSOCK_OP_RESPONSE:
        begin
          Service := GetNetwork.SocketStream[VPacket.hdr.dst_port];
          if Service = nil then
          begin
            VSocketReset(VPacket.hdr.src_cid, VPacket.hdr.src_port, VPacket.hdr.dst_port);
          end else
          begin
            ClientSocket := Service.ClientSocket;
            ClientSocket.RemoteWinLen := VPacket.hdr.buf_alloc;
            ClientSocket.RemoteWinCount := VPacket.hdr.fwd_cnt;
            ClientSocket.State := SCK_TRANSMITTING;
          end;
        end;
    end;
    ToroFreeMem(Packet);
  end;
end;

function LocalNetworkInit(PacketHandler: Pointer): Boolean;
var
  I: LongInt;
begin
  SetPerCPUVar(PERCPUCURRENTNET, PtrUInt(@DedicateNetworks[GetCoreId]));
  Result := false;
  GetNetwork.NetworkInterface.OutgoingPackets := nil;
  GetNetwork.NetworkInterface.OutgoingPacketTail := nil;
  GetNetwork.NetworkInterface.IncomingPackets := nil;
  GetNetwork.NetworkInterface.IncomingPacketTail := nil;
  GetNetwork.SocketStream := ToroGetMem(MAX_SocketPORTS * sizeof(PNetworkService));
  if GetNetwork.SocketStream = nil then
    Exit;
  GetNetwork.SocketDatagram := ToroGetMem(MAX_SocketPORTS * sizeof(PNetworkService));
  if GetNetwork.SocketDatagram = nil then
  begin
    ToroFreeMem(GetNetwork.SocketStream);
    Exit;
  end;
  for I:= 0 to (MAX_SocketPORTS-1) do
  begin
    GetNetwork.SocketStream[I]:=nil;
    GetNetwork.SocketDatagram[I]:=nil;
  end;
  if PtrUInt(BeginThread(nil, ServiceStack, PacketHandler, nil, DWORD(-1), ThreadID)) <> 0 then
    WriteConsoleF('Networks Packets Service .... Thread: %h\n',[ThreadID])
  else
    WriteConsoleF('Networks Packets Service .... /VFailed!/n\n',[]);
  GetNetwork.NetworkInterface.start(GetNetwork.NetworkInterface);
  Result := True;
end;

procedure DedicateNetworkSocket(const Name: PXChar);
var
  Net: PNetworkInterface;
  CPUID: Longint;
begin
  Net := NetworkInterfaces;
  CPUID:= GetCoreId;
  while Net <> nil do
  begin
    if StrCmp(@Net.Name, Name, StrLen(Name)) and (Net.CPUID = -1) and (DedicateNetworks[CPUID].NetworkInterface = nil) then
    begin
      Net.CPUID := CPUID;
      DedicateNetworks[CPUID].NetworkInterface := Net;
      if not LocalNetworkInit(@ProcessSocketPacket) then
      begin
        DedicateNetworks[CPUID].NetworkInterface := nil;
        Exit;
      end;
      WriteConsoleF('DedicateNetworkSocket: success on core #%d\n', [CPUID]);
      Exit;
    end;
    Net := Net.Next;
  end;
  {$IFDEF DebugNetwork} WriteDebug('DedicateNetworkSocket: fail, driver not found\n', []); {$ENDIF}
end;

procedure NetworkInit;
var
  I: LongInt;
begin
  WriteConsoleF('Loading Network Stack ...\n',[]);
  for I := 0 to MAX_CPU - 1 do
  begin
    DedicateNetworks[I].NetworkInterface := nil;
    FillChar(DedicateNetworks[I].SocketStreamBitmap, SZ_SocketBitmap, $ff);
    DedicateNetworks[I].SocketDatagram := nil;
    DedicateNetworks[I].SocketStream := nil;
  end;
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
  Socket.BufferSender := nil;
  FillChar(Socket.DestIP, 0, SizeOf(TIPAddress));
  Socket.DestPort := 0;
  Socket.Blocking := False;
  Result := Socket;
  {$IFDEF DebugSocket} WriteDebug('SysSocket: New Socket Type %d, Buffer Sender: %d\n', [SocketType, PtrUInt(Socket.BufferSender)]); {$ENDIF}
end;

// Return a free port from Local Socket Bitmap
function GetFreePort: LongInt;
var
  j, pos: LongInt;
  Bitmap: ^DWORD;
begin
  Bitmap := @GetNetwork.SocketStreamBitmap[0];
  Result := 0;
  // the lastest 48 bits are ignored
  for j := 0 to (SZ_SocketBitmap div sizeof(DWORD))-1 do
  begin
    pos := find_msb_set(Bitmap^);
    if pos > (sizeof(DWORD) * 8 - 1) then
    begin
      Inc(Bitmap);
      continue;
    end;
    Bitmap^ := Bitmap^ and (not (1 shl pos));
    Result := USER_START_PORT + j * sizeof(DWORD) * 8 + pos;
    Exit;
  end;
end;

function SysSocketConnect(Socket: PSocket): Boolean;
var
  Service: PNetworkService;
  Packet: PPacket;
  VPacket: PVirtIOVSocketPacket;
begin
  Result := False;
  Socket.Buffer := ToroGetMem(MAX_WINDOW);
  if Socket.Buffer = nil then
    Exit;
  Socket.SourcePort := GetFreePort;
  if Socket.SourcePort = 0 then
  begin
    ToroFreeMem(Socket.Buffer);
    Exit;
  end;
  Socket.State := SCK_CONNECTING;
  Socket.mode := MODE_CLIENT;
  Socket.NeedFreePort := True;
  Socket.BufferLength :=0;
  Socket.BufferReader := Socket.Buffer;
  Service := ToroGetMem(sizeof(TNetworkService));
  if Service = nil then
  begin
    ToroFreeMem(Socket.Buffer);
    FreePort(Socket.SourcePort);
    Exit;
  end;
  GetNetwork.SocketStream[Socket.SourcePort]:= Service;
  Service.ServerSocket := Socket;
  Service.ClientSocket := Socket;
  Socket.Next := nil;
  Socket.SocketType := SOCKET_STREAM;
  Socket.BufferSender := nil;
  Socket.BufferSenderTail := nil;
  Packet := ToroGetMem(sizeof(TPacket)+ sizeof(TVirtIOVSockHdr));
  if Packet = nil then
  begin
    ToroFreeMem(Socket.Buffer);
    ToroFreeMem(GetNetwork.SocketStream[Socket.SourcePort]);
    GetNetwork.SocketStream[Socket.SourcePort] := nil;
    FreePort(Socket.SourcePort);
    Exit;
  end;
  Packet.Data := Pointer(PtrUInt(Packet)+ sizeof(TPacket));
  Packet.Size := sizeof(TVirtIOVSockHdr);
  Packet.Ready := False;
  Packet.Delete := False;
  Packet.Next := nil;
  VPacket := Pointer(Packet.Data);
  VPacket.hdr.src_cid := GetNetwork.NetworkInterface.Minor;
  VPacket.hdr.dst_cid := Socket.DestIp;
  VPacket.hdr.src_port := Socket.SourcePort;
  VPacket.hdr.dst_port := Socket.DestPort;
  VPacket.hdr.flags := 0;
  VPacket.hdr.op := VIRTIO_VSOCK_OP_REQUEST;
  VPacket.hdr.tp := VIRTIO_VSOCK_TYPE_STREAM;
  VPacket.hdr.len := 0;
  VPacket.hdr.buf_alloc := MAX_WINDOW;
  VPacket.hdr.fwd_cnt := Socket.BufferLength;
  SysNetworkSend(Packet);
  ToroFreeMem(Packet);
  SetSocketTimeOut(Socket, WAIT_ACK);
  while True do
  begin
    if (Socket.TimeOut < read_rdtsc) or (Socket.State = SCK_BLOCKED) then
    begin
      ToroFreeMem(Socket.Buffer);
      ToroFreeMem(GetNetwork.SocketStream[Socket.SourcePort]);
      GetNetwork.SocketStream[Socket.SourcePort] := nil;
      FreePort(Socket.SourcePort);
      Exit;
    end
    else if Socket.State = SCK_TRANSMITTING then
    begin
      Result := True;
      Exit;
    end;
    SysThreadSwitch;
  end;
end;

procedure SysSocketClose(Socket: PSocket);
var
  Packet: PPacket;
  VPacket: PVirtIOVSocketPacket;
begin
  if Socket.State = SCK_LOCALCLOSING then
  begin
    FreeSocket(Socket)
  end else
  begin
    Socket.State := SCK_PEER_DISCONNECTED;
    Packet := ToroGetMem(sizeof(TPacket)+ sizeof(TVirtIOVSockHdr));
    Packet.Data := Pointer(PtrUInt(Packet)+ sizeof(TPacket));
    Packet.Size := sizeof(TVirtIOVSockHdr);
    Packet.Ready := False;
    Packet.Delete := False;
    Packet.Next := nil;
    VPacket := Pointer(Packet.Data);
    VPacket.hdr.src_cid := GetNetwork.NetworkInterface.Minor;
    VPacket.hdr.dst_cid := Socket.DestIp;
    VPacket.hdr.src_port := Socket.SourcePort;
    VPacket.hdr.dst_port := Socket.DestPort;
    VPacket.hdr.flags := 3;
    VPacket.hdr.op := VIRTIO_VSOCK_OP_SHUTDOWN;
    VPacket.hdr.tp := VIRTIO_VSOCK_TYPE_STREAM;
    VPacket.hdr.len := 0;
    VPacket.hdr.buf_alloc := MAX_WINDOW;
    VPacket.hdr.fwd_cnt := Socket.BufferLength;
    SysNetworkSend(Packet);
    ToroFreeMem(Packet);
  end;
end;

function SysSocketListen(Socket: PSocket; QueueLen: LongInt): Boolean;
var
  Service: PNetworkService;
begin
  Result := False;
  if Socket.SocketType <> SOCKET_STREAM then
    Exit;
  if Socket.SourcePORT >= USER_START_PORT then
    Exit;
  Service := GetNetwork.SocketStream[Socket.SourcePort];
  if Service <> nil then
   Exit;
  if Socket.Blocking then
  begin
    Service := ToroGetMem(SizeOf(TNetworkService));
    if Service = nil then
      Exit;
    GetCurrentThread.NetworkService := Service;
    Service.ClientSocket := nil;
  end;
  Service:= GetCurrentThread.NetworkService;
  Service.ServerSocket := Socket;
  GetNetwork.SocketStream[Socket.SourcePort]:= Service;
  Socket.State := SCK_LISTENING;
  Socket.Mode := MODE_SERVER;
  Socket.NeedfreePort := False;
  Socket.ConnectionsQueueLen := QueueLen;
  Socket.ConnectionsQueueCount := 0;
  Socket.DestPort:=0;
  Result := True;
  {$IFDEF DebugSocket} WriteDebug('SysSocketListen: Socket listening at Local Port: %d, Buffer Sender: %h, QueueLen: %d\n', [Socket.SourcePort,PtrUInt(Socket.BufferSender),QueueLen]); {$ENDIF}
end;

function SysSocketAccept(Socket: PSocket): PSocket;
var
  NextSocket, tmp: PSocket;
  Service: PNetworkService;
begin
  if not Socket.Blocking then
  begin
    Result := nil;
    Exit;
  end;
  Service := GetNetwork.SocketStream[Socket.SourcePort];
  while True do
  begin
    NextSocket := Service.ClientSocket;
    while NextSocket <> nil do
    begin
      tmp := NextSocket;
      NextSocket := tmp.Next;
      if tmp.DispatcherEvent = DISP_ACCEPT then
      begin
        Dec(Service.ServerSocket.ConnectionsQueueCount);
        // TODO: This may be not needed because client socket are created based on the father socket
        tmp.Blocking := True;
        tmp.DispatcherEvent := DISP_ZOMBIE;
        Result := tmp;
        Exit;
      end;
    end;
    SysThreadSwitch;
  end;
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
  if not Socket.Blocking then
  begin
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
  end else
  begin
    SetSocketTimeOut(Socket, TimeOut);
    while True do
    begin
      {$IFDEF DebugSocket} WriteDebug('SysSocketSelect: Socket %h TimeOut: %d\n', [PtrUInt(Socket), TimeOut]); {$ENDIF}
      if Socket.State = SCK_LOCALCLOSING then
      begin
        Socket.DispatcherEvent := DISP_CLOSE;
        Result := False;
        {$IFDEF DebugSocket} WriteDebug('SysSocketSelect: Socket %h in SCK_LOCALCLOSING, executing DISP_CLOSE\n', [PtrUInt(Socket)]); {$ENDIF}
        Exit;
      end;
      if Socket.BufferReader < Socket.Buffer+Socket.BufferLength then
      begin
        Socket.DispatcherEvent := DISP_RECEIVE;
        {$IFDEF DebugSocket} WriteDebug('SysSocketSelect: Socket %h executing, DISP_RECEIVE\n', [PtrUInt(Socket)]); {$ENDIF}
        Exit;
      end;
      {$IFDEF DebugSocket} WriteDebug('SysSocketSelect: Socket %h set timeout\n', [PtrUInt(Socket)]); {$ENDIF}
      if Socket.TimeOut < read_rdtsc then
      begin
        Result := False;
        Exit;
      end;
      SysThreadSwitch;
    end;
  end;
end;

function SysSocketSend(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32): LongInt;
var
  Packet: PPacket;
  VPacket: PVirtIOVSocketPacket;
  P: PChar;
  FragLen: UInt32;
begin
  while Addrlen > 0 do
  begin
    if Addrlen > VIRTIO_VSOCK_MAX_PKT_BUF_SIZE then
      FragLen := VIRTIO_VSOCK_MAX_PKT_BUF_SIZE
    else
      FragLen := Addrlen;

    while FragLen = Socket.RemoteWinLen - Socket.RemoteWinCount do
    begin
      SysThreadSwitch;
    end;

    if FragLen > Socket.RemoteWinLen - Socket.RemoteWinCount then
      FragLen := Socket.RemoteWinLen - Socket.RemoteWinCount;

    Packet := ToroGetMem(FragLen + sizeof(TPacket)+ sizeof(TVirtIOVSockHdr));
    Packet.Data := Pointer(PtrUInt(Packet)+ sizeof(TPacket));
    Packet.Size := FragLen + sizeof(TVirtIOVSockHdr);
    Packet.Ready := False;
    Packet.Delete := False;
    Packet.Next := nil;
    VPacket := Pointer(Packet.Data);
    VPacket.hdr.src_cid := GetNetwork.NetworkInterface.Minor;
    VPacket.hdr.dst_cid := Socket.DestIp;
    VPacket.hdr.src_port := Socket.SourcePort;
    VPacket.hdr.dst_port := Socket.DestPort;
    VPacket.hdr.flags := 0;
    VPacket.hdr.op := VIRTIO_VSOCK_OP_RW;
    VPacket.hdr.tp := VIRTIO_VSOCK_TYPE_STREAM;
    VPacket.hdr.len := FragLen;
    VPacket.hdr.buf_alloc := MAX_WINDOW;
    VPacket.hdr.fwd_cnt := Socket.BufferLength;
  //WriteConsoleF('VIRTIO_VSOCK_OP_RW from %d:%d to %d:%d, size: %d, %d, size packet: %d\n', [VPacket.hdr.src_cid, VPacket.hdr.src_port, VPacket.hdr.dst_cid, VPacket.hdr.dst_port, VPacket.hdr.len, VPacket.hdr.fwd_cnt, Packet.Size]);
    P := Pointer(@VPacket.data);
    Move(Addr^, P^, FragLen);
    SysNetworkSend(Packet);
    ToroFreeMem(Packet);
    Dec(AddrLen, FragLen);
    Inc(Addr, FragLen);
  end;
    Result := AddrLen;
end;

end.
