// MpiBarrier.pas
//
// Copyright (c) 2003-2023 Matias Vara <matiasevara@gmail.com>
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

program MpiBarrier;

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

{$L MPI_Barrier.o}

function mainC(param: Pointer): PtrInt; external name 'mainC';

var
  i: LongInt;
  tmp: QWORD;
begin
 for i:= 0 to CPU_COUNT-1 do
   tmp := BeginThread(nil, 4096, @mainC, Nil, i, tmp);
 while True do ThreadSwitch;
end.
