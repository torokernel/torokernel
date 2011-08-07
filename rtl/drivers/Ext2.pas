//
// Ext2.pas
// 
// Drivers for Ext2 Filesystem , are implement only the most important functions .
// Supports file up to 4 MB , some code was extracted from DelphineOs project <delphineos.sourceforge.net>  
// with some corrections.
//
// Changes :
// 
// 31 / 03 / 2007 : First Version by Matias Vara.
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
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
Unit Ext2;

interface

{$I ..\Toro.inc}

//{$DEFINE DebugExt2FS}

uses Console,Arch,FileSystem,Process,Debug,Memory;

implementation

type
   Ext2SuperBlock = record    
      inodes_count      : longint;
      blocks_count      : longint;
      r_blocks_count    : longint; // Reserved blocks 
      free_blocks_count : longint;
      free_inodes_count : longint;
      first_data_block  : longint;
      log_block_size    : longint;
      log_frag_size     : longint;
      blocks_per_group  : longint;
      frags_per_group   : longint;
      inodes_per_group  : longint;
      mtime             : longint; // Time of the last mount 
      wtime             : longint; // Time of the last write 
      mnt_count         : word;
      max_mnt_count     : word;
      magic             : word;
      state             : word;
      errors            : word;
      pad               : word;
      lastcheck         : longint;
      checkinterval     : longint;
      creator_os        : longint;
      rev_level         : longint;
      reserved          : array [0..235] of longint;
   end;

   P_Ext2_sb_info = ^Ext2_Sb_Info;
   
   ext2_sb_info = record
      inodes_per_block : longint;
      blocks_per_group : longint;
      inodes_per_group : longint;
      inodes_count     : longint;
      blocks_count     : longint;
      groups_count     : longint;
      desc_per_block   : longint;
      log_block_size   : longint;
      group_desc       : PBufferHead;
   end;

   
   P_Ext2_Inode = ^Ext2_Inode;
   
   ext2_inode = record  
      mode        : word;
      uid         : word;
      size        : longint; // Size in bytes 
      atime       : longint; // Access time 
      ctime       : longint; // Creation time 
      mtime       : longint; // Modification time 
      dtime       : longint; // Deletion time 
      gid         : word;
      links_count : word;
      blocks      : longint; // Blocks (512 bytes) count 
      flags       : longint;
      reserved1   : longint;
      block       : array [1..15] of longint; //Pointers to blocks 
      version     : longint;
      file_acl    : longint;
      dir_acl     : longint;
      faddr       : longint; //Fragment address 
      frag        : byte;  //Fragment number 
      fsize       : byte;  // Fragment size 
      pad1        : word;
      reserved2   : array [0..1] of dword;
   end;

   ext2_inode_info = record
      data        : array[1..15] of longint;
      block_group : longint;
   end;

   ext2_group_desc = record
      block_bitmap : longint;
      inode_bitmap : longint;
      inode_table  : longint;
      free_blocks_count : word;
      free_inodes_count : word;
      used_dirs_count   : word;
      pad               : word;
      reserved          : array[0..2] of dword;
   end;
   Text2_group_descArray = array[0..0] of ext2_group_desc;
   P_ext2_group_desc = ^Text2_group_descArray;

   P_Ext2_Dir_Entry = ^Ext2_Dir_Entry;
   ext2_dir_entry = record
      inode     : longint;
      rec_len   : word;
      name_len  : byte;
      file_type : byte;   // Not used
      name      : array [0..254] of XChar;
   end;   
 

var
 Ext2Driver: TFilesystemDriver;


//
// Ext2ReadSuper: 
// Read Super Block structure from Ext2 Filesystem
//
function Ext2ReadSuper(Super: PSuperBlock): PSuperBlock;
var
  bh: PBufferHead;
  SuperExt2: ^Ext2SuperBlock;
  SpbInfo: ^Ext2_Sb_Info;
  db_count,i: longint;
  pDesc: ^PBufferHead;
begin
  bh:= GetBlock(Super.BlockDevice,1,1024);
  Result := nil;
  if bh=nil then
  begin
    WriteConsole('Ext2FS: Unabled to read SuperBlock\n',[]);
    Exit;
  end;
  SuperExt2:= bh.data;
  if SuperExt2.magic <> $EF53 then
  begin
    PutBlock(Super.BlockDevice,bh);
    WriteConsole('Ext2FS: Bad magic number in SuperBlock\n',[]);
    Exit;
  end else if (SuperExt2.log_block_size>2) then
  begin
    PutBlock(Super.BlockDevice,bh);
    WriteConsole('Ext2FS: Logical Block Size is not supported\n',[]);
    Exit;
  end;
  case SuperExt2.log_block_size of
    0: Super.BlockSize:= 1024;
    1: Super.BlockSize:= 2048;
    2: Super.BlockSize:= 4096;
  end;
  SpbInfo:= ToroGetMem(sizeof(Ext2_Sb_Info));
  if SpbInfo=nil then
  begin
    PutBlock(Super.BlockDevice,bh);
    Exit;
  end;
  SpbInfo.log_block_size:= SuperExt2.log_block_size;
  SpbInfo.inodes_per_block:= Super.BlockSize div sizeof(ext2_inode);
  SpbInfo.blocks_per_group:= SuperExt2.blocks_per_group;
  SpbInfo.inodes_per_group:= SuperExt2.inodes_per_group;
  SpbInfo.inodes_count:= SuperExt2.inodes_count;
  SpbInfo.blocks_count:= SuperExt2.blocks_count;
  SpbInfo.groups_count:= (SuperExt2.blocks_count-SuperExt2.first_data_block+SuperExt2.blocks_per_group-1)
                            div SuperExt2.blocks_per_group;
  SpbInfo.desc_per_block:= Super.BlockSize div sizeof(ext2_group_desc);
  db_count:= (SpbInfo.groups_count+SpbInfo.desc_per_block-1) div SpbInfo.desc_per_block;
  SpbInfo.Group_Desc:= ToroGetMem(db_count*sizeof(pointer));
  // not enough memory ??
  if SpbInfo.Group_Desc=nil then
  begin
    ToroFreeMem(SpbInfo);
    PutBlock(Super.BlockDevice,bh);
    WriteConsole('Ext2FS: Not memory for Descriptor\n',[]);
    Exit;
  end;
  pDesc:= @SpbInfo.Group_Desc;
  for i:= 0 to db_count-1 do
  begin
    pDesc^ := GetBlock(Super.BlockDevice, SuperExt2.first_data_block+i+1, Super.BlockSize);
    if pDesc = nil then
    begin
      WriteConsole('EXT2Fs: Error reading Block Descriptors\n',[]);
      ToroFreeMem(SpbInfo);
      PutBlock(Super.BlockDevice,bh);
      Exit;
    end;
    Inc(pDesc);
  end;
  // The Filesystem was mounted fine
  Super.SbInfo:= SpbInfo;
  // loading inode root
  Super.InodeROOT:= GetInode(2);
  Result := Super;
  {$IFDEF DebugExt2FS}
    DebugTrace('Ext2FS: Ext2 Super Block Mounted , Information:', 0, 0, 0);
    DebugTrace('Logic Block Size: %d', 0, SpbInfo.log_block_size, 0);
    DebugTrace('Inodes per Block: %d', 0, SpbInfo.inodes_per_block, 0);
    DebugTrace('Inodes Count: %d', 0, SpbInfo.inodes_count, 0);
    DebugTrace('Block Counts: %d', 0, SpbInfo.blocks_count, 0);
  {$ENDIF}
end; 
 
//
// Ext2ReadInode : 
// Read Inode from Ext2 Filesystem
//
procedure Ext2ReadInode(Inode: PInode);
var
  block_group, group_desc, desc, Offset, block, I: longint;
  SbInfo: P_Ext2_sb_info;
  bh: PBufferHead;
  gdp: P_ext2_group_desc;
  raw_inode: P_Ext2_Inode;
  InoInfo: ^ext2_inode_info;
begin
  SbInfo:= Inode.SuperBlock.SbInfo;
  Inode.Dirty:= true;
  // Invalid inode number!
  if (Inode.ino<>2) and(inode.ino<11) and (inode.ino > SbInfo.inodes_count) then
    Exit;
  block_group:= (Inode.ino-1) div (SbInfo.inodes_per_group);
  // Invalid group!
  if block_group >= SbInfo.groups_count then
    Exit;
  group_desc:= block_group div SbInfo.desc_per_block;
  desc:= block_group and (SbInfo.desc_per_block -1);
  bh := Pointer(PtrUInt(SbInfo.group_desc)+group_desc);
  if bh=nil then
    Exit; // Error in Read operations
  gdp := bh.data;
  // Offset in the  block
  Offset := (Inode.ino -1) mod SbInfo.inodes_per_block * sizeof(ext2_inode);
  // block where is the inode
  block:= gdp^[desc].inode_table + (((inode.ino-1) mod SbInfo.inodes_per_group * sizeof(ext2_inode))
            shr (SbInfo.log_block_size +10));
  bh := GetBlock(Inode.SuperBlock.BlockDevice, Block, Inode.SuperBlock.BlockSize);
  if bh = nil then
    Exit; // error when was read the inode
  raw_inode := Pointer(PtrUInt(bh.data) + Offset);
  // Block and Char Devices are not supported
  if (raw_inode.mode and $4000 <> $4000) and (raw_inode.mode and $8000 <> $8000) then
  begin
    PutBlock(Inode.SuperBlock.BlockDevice,bh);
    {$IFDEF DebugExt2FS} DebugTrace('Ext2FS: Inode mode not supported , Inode: %d',0,Inode.ino,0); {$ENDIF}
    Exit;
  end;
  Inode.InoInfo:= ToroGetMem(sizeof(ext2_inode_info));
  if Inode.InoInfo = nil then
  begin // Not enough memory ?
    PutBlock(Inode.SuperBlock.BlockDevice,bh);
    Exit;
  end;
  InoInfo:= Inode.InoInfo;
  InoInfo.block_group:= block_group;
  Inode.Dirty:= false;
  Inode.ATime:= Raw_Inode.atime;
  Inode.CTime:= raw_Inode.ctime;
  Inode.DTime:= raw_Inode.dtime;
  Inode.MTime:= raw_Inode.atime;
  Inode.Size := raw_Inode.size;
  // only direcotories and Regular files
  if raw_inode.mode and $4000 = $4000 then
    Inode.Mode := INODE_DIR
  else
    Inode.Mode:= INODE_REG;
  // loading direct and indirect blocks
  for I := 1 to 15 do
    InoInfo.data[I]:= raw_inode.block[I];
  // return the block to the cache
  PutBlock(Inode.SuperBlock.BlockDevice, bh);
  {$IFDEF DebugExt2FS} DebugTrace('Ext2FS: Inode %d, Read Ok', 0, Inode.ino, 0); {$ENDIF}
end;

// Look for Inode name in Directory Inode  and return his inode.
// Only read from Directs blocks
function Ext2LookUpInode(Ino: PInode; const Name: AnsiString): PInode;
var
  I, J: longint;
  InoInfo: ^ext2_inode_info;
  bh : PBufferHead;
  Offset: longint;
  entry: P_Ext2_Dir_Entry;
label _next;
begin
  InoInfo := Ino.InoInfo;
  Result := nil;
  for I:= 1 to 12 do
  begin
    if InoInfo.data[I] <> 0 then
    begin
      bh := GetBlock(Ino.SuperBlock.BlockDevice,InoInfo.data[I], Ino.SuperBlock.BlockSize);
      if bh = nil then
        Exit; // error in read operations
      Offset:= 0;
      while Offset < Ino.SuperBlock.BlockSize do
      begin
      _next:
        entry:= Pointer(PtrUInt(bh.data)+Offset);
        Offset := Offset+entry.rec_len;
        if entry.name_len = Length(name) then
        begin // any size ?
          for J:= 0 to (entry.name_len-1) do
            if entry.name[J] <> name[J+1] then
              goto _next;
          Result:= GetInode(entry.inode); // this is the inode !
          {$IFDEF DebugFilesystem} DebugTrace('Ext2LookUpInode: Inode found', 0, 0, 0); {$ENDIF}
          PutBlock(Ino.SuperBlock.BlockDevice,bh);
          Exit
        end;
      end;
    end;
  end;
  {$IFDEF DebugFilesystem} DebugTrace('Ext2LookUpInode: Inode not found',0,0,0); {$ENDIF}
end;

type
  TLongIntArray = array[0..0] of LongInt;
  PLongIntArray = ^TLongIntArray;

// Return a real block in inode structure , only for direct and indirect simple blocks
function Get_Real_Block(block: longint;Inode: PInode):longint;
var
  InoInfo: ^ext2_inode_info;
  tmp_block: longint;
  buffer: PLongIntArray;
  bh: PBufferHead;
begin
  InoInfo:= Inode.InoInfo;
  // directs blocks
  if (block <= 12) then
    Result := InoInfo.data[block]
  else if block <= (12 + Inode.SuperBlock.BlockSize div 4) then
  begin
    tmp_block := InoInfo.data[13];
    bh := GetBlock(Inode.SuperBlock.BlockDevice,tmp_block,Inode.SuperBlock.BlockSize);
    // error in read operations
    if bh = nil then
    begin
      Result:=0;
      Exit;
    end;
    buffer := bh.data;
    Result := buffer^[(block-12)-1]
    // More Blocks are not supported
  end else
    Result := 0;
end;
 
// Read Regular File from Ext2 Filesystem , support up to 4MB per file , usign 4096 bytes physic blocks.
function Ext2ReadFile(FileDesc: PFileRegular; Count: longint; Buffer: Pointer): longint;
var 
  I, blocksize:longint;
  nb_block, start_block, real_block, initoff, Len: longint;
  // file_ofs: LongInt;
  bh : PBufferHead;
begin
  if FileDesc.FilePos + Count > FileDesc.Inode.Size then
    Count:= FileDesc.Inode.Size - FileDesc.FilePos;
  blocksize := Filedesc.Inode.SuperBlock.Blocksize;
  nb_block := Count div blocksize;
  initoff := FileDesc.FilePos mod Blocksize;
  start_block:= FileDesc.FilePos div blocksize+1;
  if Count mod blocksize <> 0 then
    nb_block:= nb_block +1;
  //file_ofs:= FileDesc.filepos;
  Len := Count;
  // reading
  for I := start_block to (start_block+nb_block-1) do
  begin
    real_block := Get_Real_Block(I, FileDesc.Inode);
    bh:= GetBlock(FileDesc.Inode.SuperBlock.BlockDevice,real_block,BlockSize);
    // Hardware error
    if bh = nil then
      break;
    // count exced a one block
    if Len>blocksize then
    begin
      Move(PByte(PtrUInt(bh.data)+initoff)^, PByte(Buffer)^, blocksize-initoff);
      FileDesc.FilePos:= FileDesc.FilePos + Blocksize - initoff;
      initoff := 0;
      Buffer := Pointer(PtrUInt(Buffer) + Blocksize - initoff);
      Len := Len - Blocksize + initoff;
    end else
    begin
      Move(PByte(PtrUInt(bh.data)+initoff)^, PByte(Buffer)^, Len);
      initoff := 0 ;
      FileDesc.FilePos := FileDesc.FilePos + Len;
      Len := 0 ;
    end;
  end;
  Result := Count-Len;
end;

// Initialization of Ext2 Filesystem

initialization
  WriteConsole('Ext2 VFS Driver ... /VOk!/n\n',[]);
  Ext2Driver.name := 'ext2';
  Ext2Driver.ReadSuper := @Ext2ReadSuper;
  Ext2Driver.CreateInode := nil;
  Ext2Driver.ReadInode := @Ext2ReadInode;
  Ext2Driver.LookUpInode := @Ext2LookUpInode;
  Ext2Driver.ReadFile := @Ext2ReadFile;
  Ext2Driver.WriteFile := nil;
  RegisterFilesystem(@Ext2Driver);


end.
