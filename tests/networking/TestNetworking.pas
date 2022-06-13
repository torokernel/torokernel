//
// TestNetworking.pas
//
// This unit contains unittests for the Networking unit.
//
// Copyright (c) 2003-2022 Matias Vara <matiasevara@gmail.com>
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

program TestNetworking;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

uses
  Kernel,
  Process,
  Memory,
  Debug,
  Arch,
  Filesystem,
  Network,
  Console,
  VirtIO,
  VirtIOConsole,
  VirtIOVSocket;

const
  SERVICE_TIMEOUT = 1000;
  INIT_MEM = 2048;

var
  total, i, total_t, new_size, curr_size: LongInt;
  netdriver, tmp, mode: PChar;
  HttpServer, HttpClient: PSocket;
  buf: array[0..255] of Byte;
  buff, buff_i: PChar;

// This test sends an array buf and expects to get the same array
// If not, it returns False
function TestClient: Boolean;
begin
  Result := False;
  HttpClient := SysSocket(SOCKET_STREAM);
  // Host CID
  HttpClient.DestIp := 2;
  HttpClient.DestPort := 80;
  HttpClient.Blocking := True;
  if SysSocketConnect(HttpClient) then
  begin
    // generate a sequence of numbers
    for i := 0 to sizeof(buf)-1 do
      buf[i] := i;
    SysSocketSend(HttpClient, @buf[0], sizeof(buf), 0);
    while true do
    begin
      if not SysSocketSelect(HttpClient, SERVICE_TIMEOUT) then
        Break;
      total := SysSocketRecv(HttpClient, @buf[0], sizeof(buf), 0);
    end;
    SysSocketClose(HttpClient);
    // check if the sequence is correctly received
    for i:= 0 to sizeof(buf)-1 do
      if buf[i] <> i Then
        Exit;
    Result := True;
  end;
end;

begin
  netdriver := GetKernelParam(0);
  mode := GetKernelParam(1);
  DedicateNetworkSocket(netdriver);
  if StrCmp(mode, 'client', StrLen('client')) then
  begin
    If TestClient = False then
      WriteDebug('TestClient-%d: FAILED\n', [0])
    else
      WriteDebug('TestClient-%d: PASSED\n', [0]);
    Exit
  end else if StrCmp(mode, 'server', StrLen('server')) then
  begin
    HttpServer := SysSocket(SOCKET_STREAM);
    HttpServer.Sourceport := 80;
    HttpServer.Blocking := True;
    SysSocketListen(HttpServer, 50);
    // server mode
    while true do
    begin
      curr_size := INIT_MEM;
      buff := ToroGetMem(curr_size);
      buff_i := buff;
      total_t := 0;
      HttpClient := SysSocketAccept(HttpServer);
      while true do
      begin
        if not SysSocketSelect(HttpClient, SERVICE_TIMEOUT) then
          Break;
        total := SysSocketRecv(HttpClient, @buf, sizeof(buf), 0);
        if total = 0 then
          Continue;
        if total_t + total > curr_size then
        begin
          Inc(new_size, curr_size + sizeof(buf));
          tmp := ToroGetMem(new_size);
          Move(buff_i^, tmp^, total_t);
          ToroFreeMem(buff_i);
          buff_i := tmp;
          buff := buff_i + total_t;
          curr_size := new_size;
        end;
        Inc(total_t, total);
        Move(buf, buff^, total);
        Inc(buff, total);
      end;
      SysSocketSend(HttpClient, buff_i, total_t, 0);
      SysSocketClose(HttpClient);
      ToroFreeMem(buff_i);
    end;
  end;
end.
