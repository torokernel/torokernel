//
// Build.pas :
//
// <image size> : Size of image in MB .
// <PE file>    : Executable File. Formats supported : ELF-X86-64 and PECOFF64
// <boot.o>   : path of bootloader's file.
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

program Build;

{$IFDEF WIN64}
 {$APPTYPE CONSOLE}
{$ENDIF WIN64}

{$IFDEF FPC}
	{$mode objfpc}
{$ENDIF}

uses
  SysUtils,
  BuildImg in 'BuildImg.pas';

var
  BootFileName: string;
  ImageSize: Integer;
  EFFileName: string;
  OutFileName: string;
begin
  if (Paramcount < 4) then
  begin
  	Writeln('usage: build.exe <image size in MB> <Executable file> <boot.o> <Output file>');
   	Exit;
  end;
  ImageSize := StrToIntDef(ParamStr(1), 1);
  EFFileName := ParamStr(2);
  if not(FileExists(EFFileName)) then
  begin
	Writeln('Error: <Executable file> does not exist');
	Exit;
  end;
  BootFileName := ParamStr(3);
  if not(FileExists(BootFileName)) then
  begin
	Writeln('Error: <boot.o> does not exist');
	Exit;
  end;
  OutFileName := ParamStr(4);
  BuildBootableImage(ImageSize, EFFileName, BootFileName, OutFileName);
end.
