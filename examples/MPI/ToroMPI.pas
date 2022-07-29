Unit ToroMPI;

interface

uses
  Arch,
  Memory,
  Console,
  VirtIOBus;

const
  MPI_SUM = 0;
  MPI_MIN = 1;

function Mpi_Scatter(send_data: Pointer; send_count: LongInt; recv_data: Pointer; var recv_count: LongInt; root: LongInt): LongInt; cdecl;
function Mpi_Gather(send_data: Pointer; send_count: LongInt; recv_data: Pointer; var recv_count: LongInt; root: LongInt): LongInt; cdecl;
function Mpi_Reduce(send_data: Pointer; recv_data: Pointer; send_count: LongInt; Operation: Longint; root:LongInt): LongInt; cdecl;
function GetRank: LongInt; cdecl;
function GetCores: LongInt; cdecl;
function printf(p: pchar; param: LongInt): LongInt; cdecl;

implementation

function printf(p: pchar; param: LongInt): LongInt; cdecl; [public, alias: 'printf'];
begin
  WriteConsoleF('%p %d\n', [PtrUInt(p), param]);
end;

function GetCores: Longint; cdecl; [public, alias: 'GetCores'];
begin
  Result := CPU_COUNT;
end;

function GetRank: LongInt; cdecl; [public, alias: 'GetRank'];
begin
 Result := GetApicId;
end;

// assume that data-type are longint
function Mpi_Scatter(send_data: Pointer; send_count: LongInt; recv_data: Pointer; var recv_count: LongInt; root: LongInt): LongInt; cdecl;
var
  r, tmp: ^LongInt;
  cpu, len_per_core: LongInt;
  buff: array[0..VIRTIO_CPU_MAX_PKT_BUF_SIZE-1] of Char;
begin
  r := send_data;
  len_per_core := (send_count * sizeof(LongInt)) div CPU_COUNT;
  if GetApicID = root then
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
  buff: array[0..VIRTIO_CPU_MAX_PKT_BUF_SIZE-1] of Char;
begin
  r := recv_data;
  len_per_core := send_count * sizeof(LongInt);
  if GetApicID = root then
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
  if GetApicID = root then
    s := ToroGetMem(sizeof(LongInt) * CPU_COUNT * send_count)
  else
    s := nil;
  Mpi_Gather(send_data, send_count, s, len, root);
  if GetApicId = root then
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
    end;
    ToroFreeMem(s);
  end;
end;
end.
