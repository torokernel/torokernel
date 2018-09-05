//
// Unit BuildImg
//
// Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
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
unit BuildImg;

{$IFDEF FPC}
  {$mode objfpc}
{$ENDIF}

interface

procedure BuildBootableImage(ImageSize: Integer; const FEFileName, BootFileName, OutFilename : string);
function ELFtoKernelBin(const ELFFileName: string): Boolean;

implementation

const
  PEMAGIC= $00004550 ;
  ImageBase = $400000;

  // Debug section is written at address $700000
  DebugFileOff = $300000;

type
  // head needed by Toro's Bootloader
  TBootHead = record

  magic_boot: DWORD;
  add_main: DWORD;
  end_sector: DWORD;
  add_image: DWORD;
end;

  PBootHead = ^TBootHead;

  //  Structures for PECOFF files.

  TImageFileHeader = record
    Machine: Word;
    NumberOfSections: Word;
    TimeDateStamp : DWORD;
    PointerToSymbolTable : DWORD;
    NumberOfSymbols : DWORD;
    SizeOfOptionalHeader:word;
    Characteristics:word;
  end;

  TImageOptionalHeader = record
    res : array[1..4] of DWORD;
    AddressOfEntryPoint : DWORD;
    BaseofCode : DWORD;
    BaseofData : DWORD;
    ImagenBase : DWORD;
    res2 : array[1..17] of DWORD;
  end;

  TImageSectionHeader = record
    Name: array[0..7] of Char;
    VirtualSize: DWORD;
    VirtualAddress: DWORD;
    PhysicalSize: DWORD;
    PhysicalOffset: DWORD;
    peObjReserved: array[0..2] of DWORD;
    peObjFlags: DWORD;
  end;

  TELFImageHeader = record   { 52 bytes }
    e_ident: array [0..15] of byte;
    e_type: word;   { Object file type }
    e_machine: word;
    e_version: dword;
    e_entry: pointer;
    e_phoff: pointer;
    e_shoff: pointer;
    e_flags: dword;
    e_ehsize: word;
    e_phentsize: word;
    e_phnum: word;
    e_shentsize: word;
    e_shnum: word;
    e_shstrndx: word;
  end;

  TELFImageSectionHeader = record   { 32 bytes }
    p_type   : dword;
    p_flags  : dword;
    p_offset : pointer;
    p_vaddr  : pointer;
    p_paddr  : pointer;
    p_filesz : qword;
    p_memsz  : qword;
    p_align  : qword;
  end;


  TELFSectionHeader = record { 64 bytes }
    sh_name: dword;
    sh_type: dword;
    sh_flags: qword;
    sh_addr: pointer;
    sh_offset: pointer;
    sh_size: qword;
    sh_link: Dword;
    sh_info: Dword;
    sh_addraling: qword;
    sh_entsize: qword;
  end;

  coffsymbol = packed record
    name: array[0..3] of char; { real is [0..7], which overlaps the strofs ! }
    strofs: PtrUInt;
    value: PtrUInt;
    section: smallint;
    empty: word;
    typ: byte;
    aux: byte;
   end;

  kerneldebuginfo = record
    magic: PtrUInt;
    size: PtrUInt;
    data: array of byte;
  end;

var
  addmain: pointer;
  PEOptHeader :  TImageOptionalHeader ;

function PEtoKernelBin(const PEFileName: string): Boolean;
var
  Buffer: PByte;
  BytesRead: Integer;
  I, J: Integer;
  Magic, Code: Integer;
  OutputFile: File;
  PEFile: File;
  PEHeader: TImageFileHeader;
  PESections: ^TImageSectionHeader;
  PEKDebug: ^kerneldebuginfo;
  Value: Longint;
  Tmp: array [0..7] of char;
  SectionNameBuf: array[0..255] of char;
  SectionName: string;
begin
  Assign(PEFile, PEFileName);
  Reset(PEFile, 1);
  while not Eof(PEFile) do
  begin
    BytesRead := 0;
    BlockRead(PEFile, Magic, SizeOf(Magic), BytesRead);
    if Magic = PEMAGIC then
    begin
      WriteLn(PEFileName , ': ', 'Detected PECOFF format');
      Assign(OutputFile, 'kernel.bin');
      Rewrite(OutputFile,1);
      BlockRead(PEFile, PEHeader, SizeOf(PEHeader), BytesRead); // PE header
      BlockRead(PEFile,PEOptHeader,SizeOf(PEOptHeader),BytesRead); // optional header
      addmain := Pointer(ImageBase + PEOptHeader.AddressOfEntryPoint); // point to start
      Seek(PEFile, filepos(PEFile)+PEHeader.SizeOfOptionalHeader-BytesRead); // position of PE sections
      PESections := GetMem(PEHeader.NumberOfSections * sizeof(TImageSectionHeader));
      for I := 0 to PEHeader.NumberOfSections-1 do
        BlockRead(PEFile, PESections[I], SizeOf(TImageSectionHeader), BytesRead);
      for I := 0 to PEHeader.NumberOfSections-1 do
      begin
        if (PESections[I].name='.text') or (PESections[I].name='.data') or (PESections[I].name='.rdata')then
        begin
          WriteLn('Writing ', PESections[I].name, ' section ...');
          Seek(PEFile, PESections[I].PhysicalOffset);
          Seek(OutputFile, PESections[I].VirtualAddress);
          GetMem(Buffer, PESections[I].PhysicalSize);
          try
            BlockRead(PEFile, Buffer^,PESections[I].PhysicalSize);
            BlockWrite(OutputFile, Buffer^,PESections[I].PhysicalSize);
          finally
            FreeMem(Buffer);
          end;
        end else
        begin
          if PESections[I].name[0] = '/' then
          begin
            for J:= 1 to 7 do
              Tmp[J-1] := PESections[I].name[J];
            Val (Tmp, Value, Code);
            if Code=0 then
            begin
              FillChar(SectionNameBuf,sizeof(SectionNameBuf),0);
              Seek(PEFile,PEHeader.PointerToSymbolTable+PEHeader.NumberOfSymbols*sizeof(coffsymbol)+Value);
              BlockRead(PEFile,SectionNameBuf,sizeof(SectionNameBuf));
              SectionName := strpas(SectionNameBuf);
            end else
              SectionName := '';
            if SectionName = '.debug_line' then
            begin
              PEKDebug := GetMem(PESections[I].PhysicalSize);
              Seek(PEFile, PESections[I].PhysicalOffset);
              Seek(OutputFile, DebugFileOff-SizeOf(PESections[I].PhysicalSize));
              BlockWrite(OutputFile, PESections[I].PhysicalSize, sizeof (PESections[I].PhysicalSize));
              Seek(OutputFile, DebugFileOff);
              try
                BlockRead(PEFile, PEKDebug^ , PESections[I].PhysicalSize);
                BlockWrite(OutputFile, PEKDebug^, PESections[I].PhysicalSize);
              finally
                FreeMem(PEKDebug);
              end;
              WriteLn('Writing ', SectionName,' section ...');
            end else
              WriteLn('Ignoring ', SectionName,' section ... ');
          end else
            WriteLn('Ignoring ',PESections[I].name,' section ... ');
        end;
      end;
      WriteLn('Building binary ... ');
      Close(PEFile);
      Close(OutputFile);
      Result := True;
      Exit;
    end;
  end;
  Close(PEFile);
  Result := False;
end;

function ELFtoKernelBin(const ELFFileName: string): Boolean;
var
  ELFFile, OutputFile: File;
  FileInit, I: LongInt;
  Buffer: PByte;
  StrTable: PChar;
  ElfHeader:  TELFImageHeader;
  Elftext, Elfdata: TELFImageSectionHeader;
  ElfDebug, ElfString: TELFSectionHeader;
  PEKDebug: ^kerneldebuginfo;
begin
  Result := False;
  Assign(ELFFile, ELFFileName);
  Reset(ELFFile, 1);
  Assign(OutputFile, 'kernel.bin');
  Rewrite(OutputFile, 1);
  BlockRead(ELFFile, ElfHeader, SizeOf(ElfHeader));

  if not((char(ElfHeader.e_ident[1])='E') and (char(ElfHeader.e_ident[2])='L')) then
  begin
    Close(ELFFile);
    Close(OutputFile);
    Exit;
  end else
    WriteLn(ELFFileName , ': ','Detected ELF64 format');

  addmain := ELFHeader.e_entry;
  FileInit := PtrUInt(ElfHeader.e_phoff)+ElfHeader.e_phentsize*ElfHeader.e_phnum;
  Seek(ELFFile, PtrUInt(ElfHeader.e_phoff));
  BlockRead(ELFFile,Elftext, Sizeof(Elftext));
  BlockRead(ELFFile,Elfdata, Sizeof(Elftext));

  // copy .text section
  Seek(ELFFIle, PtrUInt(ELFtext.p_offset)+FileInit);
  Seek(OutputFile, PtrUInt(ELFtext.p_vaddr)-ImageBase+FileInit);
  GetMem(Buffer, ELFtext.p_filesz-FileInit);
  try
    BlockRead(ELFFIle, Buffer^, ELFtext.p_filesz-FileInit);
    BlockWrite(OutputFile, Buffer^, ELFtext.p_filesz-FileInit);
  finally
    FreeMem(Buffer);
  end;
  WriteLn('Writing .text section ...');

  // copy .data section
  // we assume .data section is after .text
  Seek(ELFFIle, PtrUInt(ELFdata.p_offset));
  Seek(OutputFile, PtrUInt(ELFdata.p_vaddr)-ImageBase);
  GetMem(Buffer, ELFdata.p_filesz);
  try
    BlockRead(ELFFIle, Buffer^,ELFdata.p_filesz);
    BlockWrite(OutputFile, Buffer^,ELFdata.p_filesz);
  finally
    FreeMem(Buffer);
  end;
  WriteLn('Writing .data section ...');

  // if exists, copy the debug section too
  Seek (ELFFile, PtrUInt(ElfHeader.e_shoff) + ElfHeader.e_shstrndx * sizeof(ElfHeader));
  BlockRead (ELFFile, ElfString, Sizeof(ElfString));
  Seek(ELFFile, PtrUInt(ELFString.sh_offset));
  GetMem(StrTable, ELFstring.sh_size);
  BlockRead(ELFFile, StrTable^, ELFstring.sh_size);
  Seek (ELFFile, PtrUInt(ElfHeader.e_shoff));
  for I := 0 to ElfHeader.e_shnum - 1 do
  begin
    BlockRead (ELFFile, ElfDebug, Sizeof(ElfDebug));
    if I <> ElfHeader.e_shstrndx then
    begin
      if PChar(StrTable + ElfDebug.sh_name) = '.debug_line' then
      begin
        PEKDebug := GetMem(ElfDebug.sh_size);
        Seek(ELFFile, PtrUInt(ElfDebug.sh_offset));
        Seek(OutputFile, DebugFileOff - sizeof (ElfDebug.sh_size));
        // save size of the .debug_line section
        BlockWrite(OutputFile, ElfDebug.sh_size, sizeof (QWORD));
        Seek(OutputFile, DebugFileOff);
        try
          BlockRead(ELFFile, PEKDebug^ , ElfDebug.sh_size);
          BlockWrite(OutputFile, PEKDebug^, ElfDebug.sh_size);
        finally
          FreeMem(PEKDebug);
        end;
        // warn if .debug_line section could overwrite other section
        if ElfDebug.sh_size > 1024*1024 then
          WriteLn('Writing ', pchar(StrTable + ElfDebug.sh_name),' section ... section size > 1MB!')
        else
          WriteLn('Writing ', pchar(StrTable + ElfDebug.sh_name),' section ... ');
        Break;
      end;
    end;
  end;

  FreeMem(StrTable);
  Close(ELFFile);
  Close(OutputFile);
  Result := True;
end;

procedure BuildBootableImage(ImageSize: Integer; const FEFileName, BootFileName, OutFileName : string);
var
  BootFile: File;
  BootHead: PBootHead;
  Buffer: array[1..512] of Byte;
  BytesRead: LongInt;
  Count: LongInt;
  KernelFile: File;
  P: ^dword;
  ToroImageFile: File;
begin
  if not(PEtoKernelBin(FEFileName)) then
  begin
    if not(ELFtoKernelBin(FEFileName)) then
    begin
      WriteLn('Unknow Binary Format');
      Exit;
    end;
  end;
  ImageSize := (ImageSize * 1024 * 2 ) -2 ;
  Assign(ToroImageFile, OutFileName);
  Rewrite(ToroImageFile, 1);
  Assign(BootFile, BootFileName);
  Reset(BootFile, 1);
  Assign(KernelFile, 'kernel.bin');
  Reset(KernelFile, 1);

  // Calculate the size of the kernel in 512 bytes blocks
  if (FileSize(KernelFile) mod 512) = 0 then
  begin
    ImageSize := ImageSize - FileSize(KernelFile) div 512;
    Count := FileSize(KernelFile) div 512;
  end else
  begin
    ImageSize := ImageSize - FileSize(KernelFile) div 512 - 1 ;
    Count := FileSize(KernelFile) div 512 + 1;
  end;

  Writeln('Building Image ... ');
  BytesRead := 0;
  BlockRead(BootFile, Buffer, SizeOf(Buffer), BytesRead); // copying Bootloader
  P := @Buffer[1];

  // finding the Boot's Magic Number
  while  (P^ <> $1987) and not(PtrUInt(P) = PtrUInt((@Buffer[512])+1)) do
    Inc(P);

  if P^ <> $1987 then
  begin
    Close(BootFile);
    Close(ToroImageFile);
    Close (KernelFile);
    WriteLn('Bad boot.bin file!!');
    Exit;
  end;

  BootHead := pointer(P);
  BootHead^.end_sector := FileSize(KernelFile) div 512+1;

  BootHead^.add_image := ImageBase ;
  BootHead^.add_main := DWORD(PtrUInt(addmain));
  BlockWrite(ToroImageFile, Buffer, BytesRead);
  WriteLn('Entry point : ', BootHead^.add_main);

  BlockRead(BootFile, Buffer, SizeOf(Buffer), BytesRead);
  BlockWrite(ToroImageFile, Buffer, BytesRead);
  repeat
    BlockRead(KernelFile, Buffer, SizeOf(Buffer),BytesRead);
    // some bugs here ever read and write 512 bytes !
    BlockWrite(ToroImageFile, Buffer, sizeof(Buffer));
    Dec(Count);
    // the size is not correct if use BytesRead = 0
  until (Count=0);

  FillChar(Buffer, SizeOf(Buffer), 0);
  for Count := 1 to ImageSize do
    BlockWrite(ToroImageFile, Buffer, SizeOf(Buffer));
  Close(ToroImageFile);
  Close(BootFile);
end;

end.
