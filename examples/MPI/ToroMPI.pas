// ToroMPI.pas
//
// This unit is a simple implementation of the MPI API for Toro unikernel.
// The functions are defined by following the cdecl ABI so they can be used from a C program.
//
// Copyright (c) 2003-2023 Matias Vara <matiasevara@torokernel.io>
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

Unit ToroMPI;

interface

uses
  Arch,
  Memory,
  Console,
  VirtIOBus;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

const
  MPI_SUM = 0;
  MPI_MIN = 1;
  MPI_MAX = 2;
  MPI_COMM_WORLD = 0;

  MinLongInt    = LongInt(Low(LongInt));

function Mpi_Scatter(send_data: Pointer; send_count: LongInt; recv_data: Pointer; var recv_count: LongInt; root: LongInt): LongInt; cdecl;
function Mpi_Gather(send_data: Pointer; send_count: LongInt; recv_data: Pointer; var recv_count: LongInt; root: LongInt): LongInt; cdecl;
function Mpi_Reduce(send_data: Pointer; recv_data: Pointer; send_count: LongInt; Operation: Longint; root:LongInt): LongInt; cdecl;
function Mpi_AllReduce(send_data: Pointer; recv_data: Pointer; send_count: LongInt; Operation: Longint; root:LongInt): LongInt; cdecl;
procedure MPI_Comm_size(value: LongInt; out param: LongInt); cdecl;
procedure MPI_Comm_rank(value: LongInt; out param: LongInt); cdecl;
procedure MPI_Barrier(value: LongInt); cdecl;
function Mpi_Wtime: PtrUInt; cdecl;

implementation

procedure Mpi_Bcast(data: Pointer; count: LongInt; root: LongInt); cdecl; forward;

procedure MPI_Comm_size(value: LongInt; out param: LongInt); cdecl; [public, alias: 'MPI_Comm_size'];
begin
  param := CPU_COUNT;
end;

procedure MPI_Comm_rank(value: LongInt; out param: LongInt); cdecl; [public, alias : 'MPI_Comm_rank'];
begin
  param := GetCoreId;
end;

// assume that data-type are longint
function Mpi_Scatter(send_data: Pointer; send_count: LongInt; recv_data: Pointer; var recv_count: LongInt; root: LongInt): LongInt; cdecl;
var
  r, tmp: ^LongInt;
  cpu, len_per_core: LongInt;
  buff: array[0..VIRTIO_CPU_MAX_PKT_PAYLOAD_SIZE - 1] of Char;
begin
  r := send_data;
  len_per_core := (send_count * sizeof(LongInt)) div CPU_COUNT;
  if GetCoreId = root then
  begin
    for cpu:= 0 to CPU_COUNT-1 do
    begin
      if cpu <> root then
        SendTo(cpu, r, len_per_core)
      else
      begin
        tmp := recv_data;
        recv_count := len_per_core;
        Move(r^, tmp^, len_per_core);
      end;
      Inc(r, len_per_core div (sizeof(longint)));
    end;
  end else
  begin
    RecvFrom(root, @buff[0]);
    tmp := recv_data;
    r := @buff[0];
    Move(r^, tmp^, len_per_core);
    recv_count := len_per_core;
  end;
end;

function Mpi_Gather(send_data: Pointer; send_count: LongInt; recv_data: Pointer; var recv_count: LongInt; root: LongInt): LongInt; cdecl;
var
  r, tmp: ^LongInt;
  cpu, len_per_core: LongInt;
  buff: array[0..VIRTIO_CPU_MAX_PKT_PAYLOAD_SIZE - 1] of Char;
begin
  r := recv_data;
  len_per_core := send_count * sizeof(LongInt);
  if GetCoreId = root then
  begin
    for cpu:= 0 to CPU_COUNT-1 do
    begin
      if cpu <> root then
      begin
        RecvFrom(cpu, @buff[0]);
        tmp := @buff[0];
        Move(tmp^, r^, len_per_core);
      end
      else
      begin
        tmp := send_data;
        Move(tmp^, r^, len_per_core);
      end;
      Inc(r, len_per_core div sizeof(LongInt));
    end;
  end else
    SendTo(root, send_data, len_per_core);
end;

function Mpi_Reduce(send_data: Pointer; recv_data: Pointer; send_count: LongInt; Operation: Longint; root:LongInt): LongInt; cdecl; [public, alias: 'Mpi_Reduce'];
var
  count, i, j, len: LongInt;
  ret, s: ^LongInt;
begin
  count := 0;
  if GetCoreId = root then
    s := ToroGetMem(sizeof(LongInt) * CPU_COUNT * send_count)
  else
    s := nil;
  Mpi_Gather(send_data, send_count, s, len, root);
  if GetCoreId = root then
  begin
    ret := recv_data;
    if Operation = MPI_SUM then
    begin
      for j := 0 to send_count -1 do
      begin
        ret[j] := 0;
        for i := 0 to CPU_COUNT-1 do
          Inc(ret[j], s[i * send_count + j]);
      end;
    end else if Operation = MPI_MIN then
    begin
      for j := 0 to send_count -1 do
      begin
        ret[j] := MaxLongint;
        for i := 0 to CPU_COUNT-1 do
          if ret[j] > s[i * send_count + j] then
            ret[j] := s[i * send_count +j];
      end;
    end else if Operation = MPI_MAX then
    begin
      for j := 0 to send_count -1 do
      begin
        ret[j] := MinLongInt;
        for i := 0 to CPU_COUNT-1 do
          if ret[j] < s[i * send_count + j] then
            ret[j] := s[i * send_count +j];
      end;
    end;
    ToroFreeMem(s);
  end;
end;

function Mpi_AllReduce(send_data: Pointer; recv_data: Pointer; send_count: LongInt; Operation: Longint; root:LongInt): LongInt; cdecl; [public, alias: 'Mpi_AllReduce'];
begin
  Mpi_Reduce(send_data, recv_data, send_count, Operation, root);
  Mpi_Barrier(MPI_COMM_WORLD);
  Mpi_Bcast(recv_data, send_count, root);
end;

var
  CoreCounter: LongInt;
  globalsense: Boolean;

Threadvar
  localsense: Boolean;

// this is a simple counter-based algorithm
// see https://github.com/yuleihit/Barrier-Synchronization/blob/master/sensereversal_openmp.c
procedure Mpi_Barrier(value: LongInt); cdecl; [public, alias: 'Mpi_Barrier'];
begin
  localsense := not localsense;
  if InterlockedDecrement(CoreCounter) = 0 then
  begin
    CoreCounter := CPU_COUNT;
    globalsense := localsense;
  end else
  begin
    while globalsense <> localsense do
      ThreadSwitch;
  end;
end;

// TODO: count must always be less or equal than VIRTIO_CPU_MAX_PKT_BUF_SIZE
procedure Mpi_Bcast(data: Pointer; count: LongInt; root: LongInt); cdecl; [public, alias: 'Mpi_Bcast'];
var
  buff: array[0..VIRTIO_CPU_MAX_PKT_PAYLOAD_SIZE - 1] of Char;
  tmp, r: PChar;
  cpu: LongInt;
begin
  if GetCoreId = root then
  begin
    for cpu:= 0 to CPU_COUNT-1 do
    begin
      if cpu <> root then
        SendTo(cpu, data, count * sizeof(LongInt));
    end;
  end else
  begin
    RecvFrom(root, @buff[0]);
    tmp := @buff[0];
    r := data;
    Move(tmp^, r^, count * sizeof(LongInt));
  end;
end;

function Mpi_Send(data: pointer; count: LongInt; dest: Longint): LongInt;
begin
  SendTo(dest, data, count);
end;

// TODO: count must be less or equal than VIRTIO_CPU_MAX_PKT_BUF_SIZE
function Mpi_Recv(data: pointer; count: LongInt; source: LongInt): LongInt;
var
  buff: array[0..VIRTIO_CPU_MAX_PKT_PAYLOAD_SIZE - 1] of Char;
  r, tmp: PChar;
begin
  RecvFrom(source, @buff[0]);
  tmp := @buff[0];
  r := data;
  Move(tmp^, r^, count);
end;

// This function just returns the rdtsc counter, we should change it for the kvm wallclock
function Mpi_Wtime: PtrUInt; cdecl; [public, alias: 'Mpi_Wtime'];
begin
  Result := read_rdtsc;
end;

initialization
  CoreCounter := CPU_COUNT;
end.
