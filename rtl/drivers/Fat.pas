//
// Fat.pas
//
// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
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
Unit Fat;

interface

{$I ..\Toro.inc}

//{$DEFINE DebugExt2FS}

uses Console,Arch,FileSystem,Process,Debug,Memory;

var
  FatDriver: TFileSystemDriver;

implementation

type
  pfat_boot_sector = ^fat_boot_sector ;

  fat_boot_sector = packed record
    BS_jmpBott: array[1..3] of byte;
    BS_OEMName: array[1..8] of char;
    BPB_BytsPerSec: word;
    BPB_SecPerClus: byte;
    BPB_RsvdSecCnt: word;
    BPB_NumFATs: byte;
    BPB_RootEntCnt: word;
    BPB_TotSec16: word;
    BPB_Media: byte;
    BPB_FATSz16: word;
    BPB_SecPerTrk: word;
    BPB_NumHeads: word;
    BPB_HiddSec: dword;
    BPB_TotSec32: dword;
    BS_DrvNum: byte;
    BS_Reserved1: byte;
    BS_BootSig: byte;
    BS_VolID: dword;
    BS_VolLab : array[1..11] of char;
    BS_FilSysType : array[1..8] of char;
  end;

  psb_fat = ^super_fat;

  super_fat = record
    tfat : dword ;
    pfat : ^byte ;
    pbpb : pfat_boot_sector ;
  end;

function FatLoadTable (sb: PSuperBlock): boolean ;
var
  j: LongInt;
  sb_fat : psb_fat;
  bh : PBufferHead;
  pfat : ^Byte;
begin
  Result := False;
  sb_fat := sb.SbInfo;
  pfat := ToroGetMem(sb_fat^.pbpb^.bpb_fatsz16* sb_fat^.pbpb^.bpb_bytspersec);
  for j:= 1 to sb_fat^.pbpb^.bpb_fatsz16 do
  begin
   bh := GetBlock(sb.BlockDevice, j,sb_fat^.pbpb^.bpb_bytspersec);
   if bh=nil then
   begin
     WriteConsoleF('FatLoadTable: Error when loading Fat\n',[]);
     Exit;
   end;
   Move(bh^.data^, pfat^, sb_fat^.pbpb^.bpb_bytspersec);
   Inc(pfat, sb_fat^.pbpb^.bpb_bytspersec);
  end;
  sb_fat^.pfat := pfat;
  Result := True;
  WriteConsoleF('FatLoadTable: Fat has been loaded correctly\n',[]);
end;

function FatReadSuper (Super: PSuperBlock): PSuperBlock;
var
  bh: PBufferHead;
  pfatboot: pfat_boot_sector;
  pfat: psb_fat ;
begin
  Result := nil;
  bh := GetBlock (Super.BlockDevice, 0, 512);
  pfatboot := bh.data;

  // look for FAT16 string
  if (pfatboot.BS_FilSysType[1] = 'F') and (pfatboot.BS_FilSysType[5] = '6') then
  begin
    WriteConsoleF('FatReadSuper: FAT16 partition found\n',[]);
    pfat := ToroGetMem(sizeof(super_fat));
    pfat.pbpb := pfatboot;
    Super.SbInfo:= pfat;
    Super.BlockSize:= pfat.pbpb.BPB_BytsPerSec;
    if not FatLoadTable(Super) then
    begin
      PutBlock(Super.BlockDevice,bh);
      WriteConsoleF('FatReadSuper: Fail when loading FAT table\n',[]);
      Exit;
    end;
  end else
  begin
    PutBlock(Super.BlockDevice,bh);
    WriteConsoleF('FatReadSuper: Bad magic number in SuperBlock\n',[]);
    Exit;
  end;
  // TODO
  Super.InodeROOT:= GetInode(1);
  // we return the bh to cache
  PutBlock(Super.BlockDevice,bh);
  Result := Super;
end;


procedure FatReadInode(Inode: PInode);
begin
    WriteConsoleF('FatReadInode\n',[]);
    while true do;

end;

initialization
  WriteConsoleF('Fat driver ... /Vinstalled/n\n',[]);
  FatDriver.name := 'fat';
  FatDriver.ReadSuper := @FatReadSuper;
  FatDriver.ReadInode := @FatReadInode;
  {Ext2Driver.CreateInode := @Ext2CreateInode;
  Ext2Driver.CreateInodeDir := @Ext2CreateInodeDir;
  Ext2Driver.ReadInode := @Ext2ReadInode;
  Ext2Driver.WriteInode := @Ext2WriteInode;
  Ext2Driver.LookUpInode := @Ext2LookUpInode;
  Ext2Driver.ReadFile := @Ext2ReadFile;
  Ext2Driver.WriteFile := @Ext2WriteFile;}
  RegisterFilesystem(@FatDriver);
end.
