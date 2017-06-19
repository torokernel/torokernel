
// Toro Ping example.

// Changes :
// 08 / 12 / 2016 : First Version by Matias Vara

// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
// All Rights Reserved

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

unit uToroPing;

{$mode delphi}

interface

type
    TIPAddr = array[0..3] of byte;

procedure Main(PingIPDword: Dword);
function Init(const PingIP: TIPAddr): Dword;

const
    MaskIP: TIPAddr = (255, 255, 255, 0);
    Gateway: TIPAddr = (192, 100, 200, 1);
    LocalIP: TIPAddr = (192, 100, 200, 100);
    // this ip may change depending on windows or linux host
    PingIP: TIPAddr = (192, 168, 0, 98);// (192, 100, 200, 10);
    // wait for ping in seconds
    WAIT_FOR_PING = 1;

implementation

uses
    Process,
    Memory,
    Network,
    Console;
//    E1000;

function Init(const PingIP: TIPAddr): Dword;
begin
    // Dedicate the ne2000 network card to local cpu
    {Network.}DedicateNetwork('e1000', LocalIP, Gateway, MaskIP, nil);

    // I convert the IP to a DWord
    {Network.}_IPAddress(PingIP, Result);

    // I keep sending ICMP packets and waiting for an answer
    {Console.}WriteConsole('\t/R ToroPing: This test sends ICMP packets every %ds\n', [WAIT_FOR_PING]);
end;

procedure Main(PingIPDword: Dword);
var

    PingPacket: {Network.}PPacket;
    PingContent: PChar = 'abcdefghijklmtororstuvwabcdefghi';
    seq: word = 90;
    IP: {Network.}PIPHeader;
    ICMP: {Network.}PICMPHeader;
begin
    while True do
      begin
        {Console.}WriteConsole('\t ToroPing: /Vsending/n ping to %d.%d.%d.%d, seq: %d\n', [PingIP[0], PingIP[1], PingIP[2], PingIP[3], seq]);
        {Network.}ICMPSendEcho(PingIPDword, PingContent, 32, seq, 0);
        PingPacket := {Network.}ICMPPoolPackets;
        if (PingPacket <> nil) then
          begin
            IP := Pointer(PtrUInt(PingPacket.Data) + SizeOf(TEthHeader));
            ICMP := Pointer(PtrUInt(PingPacket.Data) + SizeOf(TEthHeader) + SizeOf(TIPHeader));
            if ((IP.SourceIP = PingIPDword) and (ICMP.seq = SwapWORD(seq))) then
                {Console.}WriteConsole('\t ToroPing: /areceived/n ping from %d.%d.%d.%d\n', [PingIP[0], PingIP[1], PingIP[2], PingIP[3]])
            else
                {Console.}WriteConsole('\t ToroPing: /rwrong/n received ping, seq=%d\n', [SwapWORD(ICMP.seq)]);
            {Memory.}ToroFreeMem(PingPacket);
          end
        else
            {Console.}WriteConsole('\t ToroPing: /rno received/n ping from %d.%d.%d.%d\n', [PingIP[0], PingIP[1], PingIP[2], PingIP[3]]);

        // I increment the seq for next packet
        seq := seq + 1;

        // I wait WAIT_FOR_PING seconds
        {Process.}sleep(WAIT_FOR_PING * 1000);
      end;
end;

end.
