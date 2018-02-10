//
// Here is load all the modules of Toro .
//
// Changes :
//
// 26/02/2007 Toro 0.03 Version by Matias Vara.
// 04/05/2007 Toro 0.02 Version by Matias Vara.
// 18/01/2007 Some modification in Memoy Model
// 21/08/2006 Memory model implement .
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
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
unit Kernel;

{$I Toro.inc}

interface

{$IFDEF DCC}
type
  PtrInt = Int64;
{$ENDIF}
// function InitSystem is declared only for compatibility
function InitSystem(notused: pointer): PtrInt; external {$IFDEF DCC} '' {$ENDIF} name 'PASCALMAIN';
procedure KernelStart;

implementation

uses
  {$IFDEF DEBUG} Debug, {$ENDIF}
  Arch, Console, Process, Memory, FileSystem, Network;
  
// Called from Arch
procedure KernelStart;
begin
  WriteConsoleF('/c/VLoading Toro ...\n/n',[]);
  ArchInit;
  // CPU must be initialized before DebugInit
  FillChar(CPU, sizeof(CPU),0);
  {$IFDEF DEBUG} DebugInit; {$ENDIF}
  ProcessInit;
  MemoryInit;
  FileSystemInit;
  NetworkInit;
  ConsoleInit;
  // we will never return from this procedure call
  {$IFDEF FPC} CreateInitThread(@InitSystem, 32*1024); {$ENDIF}
  {$IFDEF DCC}
//    CreateInitThread(@InitSystem, 32*1024);
  {$ENDIF}
end;

initialization
  {$IFDEF DCC} KernelStart; {$ENDIF}

end.



