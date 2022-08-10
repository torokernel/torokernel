// MpiReduce.pas
//
// This example shows the use of MPI_REDUCE to reduce a vector
// by using the MPI_SUM reduction.
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

program MpiReduce;

uses
 Kernel,
 Process,
 Memory,
 Debug,
 Arch,
 Filesystem,
 Network,
 VirtIO,
 {$IFDEF UseGDBstub}
 VirtIOConsole,
 Gdbstub,
 {$ENDIF}
 ToroMPI,
 Console;

const
  VECTOR_LEN = 64;

var
  root: LongInt = 0;

{$L MpiReduceC.o}

function mainC(param: Pointer): PtrInt; external name 'mainC';

function Main2(param: Pointer): PtrInt;
var
  r: ^LongInt;
  s: ^LongInt;
  len, i, rank: LongInt;
begin
  // build a vector with the rank of each core
  // and reduce it with the MPI_SUM operation
  rank := GetCoreId;
  r := ToroGetMem(VECTOR_LEN * sizeof(LongInt));
  s := ToroGetMem(VECTOR_LEN * sizeof(LongInt));
  for i:= 0 to VECTOR_LEN-1 do
    r[i] := rank;
  Mpi_Reduce(@r[0], @s[0], VECTOR_LEN, MPI_SUM, root);
  if rank = root then
  begin
    for i:= 0 to VECTOR_LEN-1 do
      if s[i] <> (((CPU_COUNT-1) * CPU_COUNT) div 2) then
      begin
        WriteConsoleF('Test has failed\n',[]);
        Break;
      end;
    if i = VECTOR_LEN-1 then
      WriteConsoleF('Test has succeeded\n',[]);
  end;
  FreeMem(r);
  FreeMem(s);
end;

var
  i: LongInt;
  tmp: QWORD;
begin
 for i:= 0 to CPU_COUNT-1 do
   //tmp := BeginThread(nil, 4096, @Main2, Nil, i, tmp);
   tmp := BeginThread(nil, 4096, @mainC, Nil, i, tmp);
 while True do ThreadSwitch;
end.
