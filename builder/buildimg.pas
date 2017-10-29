//
// Unit BuildImg
//
// Copyright (c) 2003-2010 Matias Vara <matiasvara@yahoo.com>
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

type
 // head needed by Toro's Bootloader
 TBootHead = record

 magic_boot: DWORD;
 add_main: DWORD;
 end_sector: DWORD;
 add_image: DWORD;
end;

 PBootHead = ^TBootHead;

 //
 //  Structures for PECOFF files.
 //
 //
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

 //
 // Structures for ELF files.
 //
 TELFImageHeader = record   { 52 bytes }

 e_ident     : array [0..15] of byte;
 e_type      : word;   { Object file type }
 e_machine   : word;
 e_version   : dword;
 e_entry     : pointer;
 e_phoff     : pointer;
 e_shoff     : pointer;
 e_flags     : dword;
 e_ehsize    : word;
 e_phentsize : word;
 e_phnum     : word;
 e_shentsize : word;
 e_shnum     : word;
 e_shstrndx  : word;
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


 coffsymbol=packed record
   name    : array[0..3] of char; { real is [0..7], which overlaps the strofs ! }
   strofs  : longint;
   value   : longint;
   section : smallint;
   empty   : word;
   typ     : byte;
   aux     : byte;
 end;

 kerneldebuginfo = record
   magic: longint;
   size: longint;
   data: array of byte;
 end;

var
 // Pointer to main() in the kernel
 addmain: pointer;


var
 PEOptHeader :  TImageOptionalHeader ;
	
// Translate the PE file to binary executable and save in kernel.bin file
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
  value: Longint;
  tmp: array [0..7] of char;
  secnamebuf : array[0..255] of char;
  secname    : string;
begin
  // PE file
  Assign(PEFile, PEFileName);
  Reset(PEFile, 1);
  while not Eof(PEFile) do
  begin
    BytesRead := 0;
    BlockRead(PEFile, Magic, SizeOf(Magic), BytesRead);
    // looking for PE header
    if Magic = PEMAGIC then // searching the PE section
    begin
      WriteLn(PEFileName , ': ', 'Detected PECOFF format');
      Assign(OutputFile, 'kernel.bin'); // temp file
      Rewrite(OutputFile,1);
      BlockRead(PEFile, PEHeader, SizeOf(PEHeader), BytesRead); // PE header
      BlockRead(PEFile,PEOptHeader,SizeOf(PEOptHeader),BytesRead); // optional header
      addmain := Pointer(ImageBase + PEOptHeader.AddressOfEntryPoint); // point to start
      Seek(PEFile, filepos(PEFile)+PEHeader.SizeOfOptionalHeader-BytesRead); // position of PE sections
      PESections := GetMem(PEHeader.NumberOfSections * sizeof(TImageSectionHeader));

      // reading the sections of PE file
      for I:= 0 to (PEHeader.NumberOfSections-1) do
      begin
        BlockRead(PEFile, PESections[I], SizeOf(TImageSectionHeader), BytesRead);
      end;

      // the sections aren't sorted
      for I:= 0 to (PEHeader.NumberOfSections-1) do
      begin
        if (PESections[I].name='.text') or (PESections[I].name='.data') or (PESections[I].name='.rdata')then
        begin
          writeln('Writing ',PESections[I].name,' section ...');
          Seek(PEFile, PESections[I].PhysicalOffset);
          // Virtual Address is from ImageBase
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
          if (PESections[I].name[0] = '/') then
          begin
             for J:= 1 to 7 do
               tmp[J-1] := PESections[I].name[J];
             Val (tmp, value, Code);
             if Code=0 then
             begin
               FillChar(secnamebuf,sizeof(secnamebuf),0);
               Seek(PEFile,PEHeader.PointerToSymbolTable+PEHeader.NumberOfSymbols*sizeof(coffsymbol)+value);
               BlockRead(PEFile,secnamebuf,sizeof(secnamebuf));
               secname:= strpas(secnamebuf);
             end else secname:='';

             // copy .debug_line section
             if (secname = '.debug_line') then
             begin
                 PEKDebug := GetMem(PESections[I].PhysicalSize);
                 Seek(PEFile, PESections[I].PhysicalOffset);
                 Seek(OutputFile, $200000 - sizeof (PESections[I].PhysicalSize));
                 BlockWrite(OutputFile, PESections[I].PhysicalSize, sizeof (PESections[I].PhysicalSize));
                 Seek(OutputFile, $200000);
                 try
                    BlockRead(PEFile, PEKDebug^ , PESections[I].PhysicalSize);
                    BlockWrite(OutputFile, PEKDebug^, PESections[I].PhysicalSize);
                 finally
                    FreeMem(PEKDebug);
                 end;
                 WriteLn('Writing ', secname,' section ...');
             end else WriteLn('Ignoring ', secname,' section ... ');
          end else writeln('Ignoring ',PESections[I].name,' section ... ');
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


var
 ElfHeader:  TELFImageHeader;
 Elftext,Elfdata: TELFImageSectionHeader;

// Translate the ELF file to binary executable and save in kernel.bin file
function ELFtoKernelBin(const ELFFileName: string): Boolean;
var
  ELFFile: File;
  OutputFile: File;
  FileInit: Integer;
  Buffer: PByte;
begin
  Assign(ELFFile, ELFFileName); // PE file
  Reset(ELFFile, 1);
  // temporal file
  Assign(OutputFile, 'kernel.bin');
  Rewrite(OutputFile,1);
  // reading elf header
  BlockRead(ELFFile, ElfHeader, SizeOf(ElfHeader));
  // entry point
  addmain := ELFHeader.e_entry;
  // char indentification
  if not((char(ElfHeader.e_ident[1])='E') and (char(ElfHeader.e_ident[2])='L')) then
  begin
    Result:=false;
    Exit;
  end else
    WriteLn(ELFFileName , ': ','Detected ELF64 format');
  // The Sections starts at the end of Program Headers
  FileInit := longint(ElfHeader.e_phoff)+ElfHeader.e_phentsize*ElfHeader.e_phnum;
  // Program Header array
  Seek(ELFFile, longint(ElfHeader.e_phoff));
  // .text section
  BlockRead(ELFFile,Elftext, Sizeof(Elftext));
  // .data  section
  BlockRead(ELFFile,Elfdata, Sizeof(Elftext));
  // making kernel.bin
  // .text section
  Seek(ELFFIle, longint(ELFtext.p_offset)+FileInit);
  Seek(OutputFile, longint(ELFtext.p_vaddr)-ImageBase+FileInit);
  GetMem(Buffer, ELFtext.p_filesz-FileInit);
  try
    BlockRead(ELFFIle, Buffer^, ELFtext.p_filesz-FileInit);
    BlockWrite(OutputFile, Buffer^, ELFtext.p_filesz-FileInit);
  finally
    FreeMem(Buffer);
  end;
  writeln('Writing .text section ...');
  //
  // making .data segment
  //
  Seek(ELFFIle, longint(ELFdata.p_offset));
  Seek(OutputFile, longint(ELFdata.p_vaddr)-ImageBase);
  GetMem(Buffer, ELFdata.p_filesz);
  try
    BlockRead(ELFFIle, Buffer^,ELFdata.p_filesz);
    BlockWrite(OutputFile, Buffer^,ELFdata.p_filesz);
  finally
    FreeMem(Buffer);
  end;
  WriteLn('Writing .data section ...');
  // clocing files
  Close(ELFFile);
  Close(OutputFile);
  result:=true;
end;

//
// Makes a boot's image
//
procedure BuildBootableImage(ImageSize: Integer; const FEFileName, BootFileName, OutFileName : string);
var
  BootFile: File;
  BootHead: PBootHead;
  Buffer: array[1..512] of Byte;
  BytesRead: Integer;
  Count: Integer;
  KernelFile: File;
  p: ^dword;
  ToroImageFile: File;
begin
  if not(PEtoKernelBin(FEFileName)) then
  begin
  if not(ELFtoKernelBin(FEFileName)) then
  begin
   writeln('Unknow Binary Format');
   exit;
  end;
  end;
  // Boot's image size
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
  p := @buffer[1];

  // finding the Boot's Magic Number
  while  (p^ <> $1987) and not(longint(p) = longint((@buffer[512])+1)) do
    p := p + 1;

  // Invalid Bootloader
  if (p^ <> $1987) then
  begin
    Close(BootFile);
    Close(ToroImageFile);
    Close (KernelFile);
    writeln('Bad boot.bin file!!');
    Exit;
  end;

  // Information about the kernel.bin
  BootHead := pointer(p);
  BootHead^.end_sector := FileSize(KernelFile) div 512+1;

  // Address of Binary in memory
  BootHead^.add_image := ImageBase ;
  BootHead^.add_main := dword(addmain);
  BlockWrite(ToroImageFile, Buffer, BytesRead);
  writeln('Entry point : ', BootHead^.add_main);

  // second block of boot
  BlockRead(BootFile, Buffer, SizeOf(Buffer), BytesRead);
  BlockWrite(ToroImageFile, Buffer, BytesRead);
  repeat
    BlockRead(KernelFile, Buffer, SizeOf(Buffer),BytesRead);

    // some bugs here ever read and write 512 bytes !
    BlockWrite(ToroImageFile, Buffer, sizeof(Buffer));
    Count := Count - 1 ;

    // the size is not correct if use BytesRead = 0
  until (Count=0);

  // filling with zeros
  FillChar(Buffer, SizeOf(Buffer), 0);
  for Count := 1 to ImageSize do
    BlockWrite(ToroImageFile, Buffer, SizeOf(Buffer));
  Close(ToroImageFile);
  Close(BootFile);
end;

end.
