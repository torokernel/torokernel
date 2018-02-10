//
// Ext2.pas
// 
// This unit contains the driver for Ext2 filesystem. For the moment, it supports file up to 4MB.
// This unit is based on the ext2 driver from DelphineOs project <delphineos.sourceforge.net>
//
// Changes :
//
// 09 / 04 / 2017 Adding SysCreateDir()
// 12 / 03 / 2017 Adding writting support.
// 31 / 03 / 2007 v1.
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
      inodes_per_block  : longint;
      blocks_per_group  : longint;
      inodes_per_group  : longint;
      inodes_count      : longint;
      blocks_count      : longint;
      groups_count      : longint;
      desc_per_block    : longint;
      log_block_size    : longint;
      free_blocks_count : longint;
      free_inodes_count : longint;
      group_desc        : PBufferHead;
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
      blocks      : longint;
      block_group : longint;
      links_count : longint;
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
      inode     : dword;
      rec_len   : word;
      name_len  : byte;
      file_type : byte;   // Not used
      name      : array [0..254] of Char;
   end;   

const
  Ext2_FT_Reg = 1;
  Ext2_FT_Dir = 2;

  Ext2_Mode_Reg = $8000;
  Ext2_Mode_Dir = $4000;

  Ext2_Mode_Irusr = &400;
  Ext2_Mode_Iwusr = &200;
  Ext2_Mode_Ixusr = &100;

  Ext2_Mode_Irgrp = &40;
  Ext2_Mode_Iwgrp = &20;
  Ext2_Mode_Ixgrp = &10;

  Ext2_Mode_Iroth = &4;
  Ext2_Mode_Iwoth = &2;
  Ext2_Mode_Ixoth = &1;

  Ext2_All_Right = Ext2_Mode_Irusr or Ext2_Mode_Iwusr or Ext2_Mode_Ixusr or Ext2_Mode_Irgrp or Ext2_Mode_Iroth or Ext2_Mode_Ixoth or Ext2_Mode_Ixgrp;
  Ext2_Dir_Mode = Ext2_All_Right;
  Ext2_File_Mode = Ext2_Mode_Irusr or Ext2_Mode_Iwusr or Ext2_Mode_Irgrp or Ext2_Mode_Iroth;

  // const used to set up times in inodes
  Ext2Date : TNow = ( Sec:0 ; Min:0 ; Hour:0 ; Day: 1 ; Month: 1; Year: 1970 );

function AddFreeBlocktoInode (Inode: PInode; I: longint): Boolean;forward;
function AddFiletoInodeDir(Ino: PInode; const Name: AnsiString; Inode: longint): Boolean;forward;
function InitializeInodeDir(Ino: PInode; Inode: longint): Boolean;forward;
function AddDirtoInodeDir(Ino: PInode; const Name: AnsiString; Inode: longint): Boolean;forward;
var
 Ext2Driver: TFilesystemDriver;

// Returns the number of seconds between Now and Ext2Date
function Ext2GetSeconds: Longint;
var
 ANow: TNow;
begin
  Now(@ANow);
  Result:= SecondsBetween(ANow, Ext2Date);
end;

// Ext2WriteSuper:
// Update SuperBlock structure in disk
//
function Ext2WriteSuper(Super: PSuperBlock): Boolean;
var
  bh: PBufferHead;
  SuperExt2: ^Ext2SuperBlock;
  SpbInfo: ^Ext2_Sb_Info;
begin
 {$IFDEF DebugExt2FS} WriteDebug('Ext2WriteSuper: Updating SuperBlock ...\n', []); {$ENDIF}
  bh:= GetBlock(Super.BlockDevice,1,1024);
  if bh=nil then
  begin
   {$IFDEF DebugExt2FS} WriteDebug('Ext2WriteSuper: GetBlock has failed\n', []); {$ENDIF}
    Result:= False;
    Exit;
  end;
  SuperExt2:= bh.data;
  SpbInfo := Super.SbInfo;
  {$IFDEF DebugExt2FS} WriteDebug('Ext2WriteSuper: free_blocks_count: %d, free_inodes_count: %d\n', [SuperExt2.free_blocks_count, SuperExt2.free_inodes_count]); {$ENDIF}
  // only update the number of free inodes and blocks
  SuperExt2.free_blocks_count := SpbInfo.free_blocks_count;
  SuperExt2.free_inodes_count := SpbInfo.free_inodes_count;
  bh.Dirty:= True;
  PutBlock(Super.BlockDevice,bh);
  {$IFDEF DebugExt2FS} WriteDebug('Ext2WriteSuper: SuperBlock has been updated, free_blocks_count: %d, free_inodes_count: %d\n', [SpbInfo.free_blocks_count, SpbInfo.free_inodes_count]); {$ENDIF}
  Result := True;
end;

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
    WriteConsoleF('Ext2ReadSuper: Unabled to read SuperBlock\n',[]);
    Exit;
  end;
  SuperExt2:= bh.data;
  if SuperExt2.magic <> $EF53 then
  begin
    PutBlock(Super.BlockDevice,bh);
    WriteConsoleF('Ext2ReadSuper: Bad magic number in SuperBlock\n',[]);
    Exit;
  end else if (SuperExt2.log_block_size>2) then
  begin
    PutBlock(Super.BlockDevice,bh);
    WriteConsoleF('Ext2ReadSuper: Logical Block Size is not supported\n',[]);
    Exit;
  end;
  case SuperExt2.log_block_size of
    0: Super.BlockSize:= 1024;
    1: Super.BlockSize:= 2048;
    2: Super.BlockSize:= 4096;
  end;

  {$IFDEF DebugExt2FS}
  if SuperExt2.state = 2 then
  begin
     WriteDebug('Ext2ReadSuper: Ext2 superblock was not cleaned unmounted\n', []);
  end;
  {$ENDIF}

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
  SpbInfo.free_blocks_count := SuperExt2.free_blocks_count;
  SpbInfo.free_inodes_count := SuperExt2.free_inodes_count;
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
    WriteConsoleF('Ext2ReadSuper: Not memory for Descriptor\n',[]);
    Exit;
  end;
  pDesc:= @SpbInfo.Group_Desc;
  // we load in memory all the group descriptors
  for i:= 0 to db_count-1 do
  begin
    pDesc^ := GetBlock(Super.BlockDevice, SuperExt2.first_data_block+i+1, Super.BlockSize);
    if pDesc = nil then
    begin
      WriteConsoleF('Ext2ReadSuper: Error reading Block Descriptors\n',[]);
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
  // we return the bh to cache
  PutBlock(Super.BlockDevice,bh);
  Result := Super;
  {$IFDEF DebugExt2FS}
    WriteDebug('Ext2ReadSuper: Ext2 Super Block Mounted , Information:\n', []);
    WriteDebug('Ext2ReadSuper: Logic Block Size: %d\n',  [SpbInfo.log_block_size]);
    WriteDebug('Ext2ReadSuper: Inodes per Block: %d\n',  [SpbInfo.inodes_per_block]);
    WriteDebug('Ext2ReadSuper: Inodes Count: %d\n', [SpbInfo.inodes_count]);
    WriteDebug('Ext2ReadSuper: Block Counts: %d\n',  [SpbInfo.blocks_count]);
  {$ENDIF}
end; 

// Ext2WriteInode
// Update the inode structure from memory to disk
procedure Ext2WriteInode(Inode: PInode);
var
  block_group, group_desc, desc, Offset, block, I: longint;
  SbInfo: P_Ext2_sb_info;
  bh: PBufferHead;
  gdp: P_ext2_group_desc;
  raw_inode: P_Ext2_Inode;
  InoInfo: ^ext2_inode_info;
begin
  SbInfo:= Inode.SuperBlock.SbInfo;
  InoInfo:= Inode.InoInfo;
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

  // error when it was reading the inode
  if bh = nil then
    Exit;

  raw_inode := Pointer(PtrUInt(bh.data) + Offset);
  //
  // TODO: to update the mode??
  // we update the size
  raw_Inode.size := Inode.Size;

  // we update the direct and indirect blocks
  for I := 1 to 15 do
    raw_inode.block[I]:= InoInfo.data[I];

  // we update the number of blocks and the links_count
  raw_inode.blocks:= InoInfo.blocks;
  raw_inode.links_count:= InoInfo.links_count;

  // we update the access and modification time
  raw_inode.atime:= Inode.ATime;
  raw_inode.mtime:= Inode.MTime;
  bh.Dirty:= True;
  PutBlock (Inode.SuperBlock.BlockDevice, bh);
  {$IFDEF DebugExt2FS} WriteDebug('Ext2WriteInode: updating Inode: %d, blocks: %d, links_count: %d\n', [Inode.ino,raw_inode.blocks,raw_inode.links_count]); {$ENDIF}
end;

// Ext2InitInodeFile
// Initializes a new inode structure.
procedure Ext2InitInode(Inode: PInode; cache_mode, i_mode: Word);
var
  block_group, group_desc, desc, Offset, block, I: longint;
  SbInfo: P_Ext2_sb_info;
  bh: PBufferHead;
  gdp: P_ext2_group_desc;
  raw_inode: P_Ext2_Inode;
  InoInfo: ^ext2_inode_info;
begin
  SbInfo:= Inode.SuperBlock.SbInfo;
  InoInfo:= Inode.InoInfo;
  // Invalid inode number!
  if (Inode.ino<>2) and(inode.ino<11) and (inode.ino > SbInfo.inodes_count) then
  begin
    {$IFDEF DebugExt2FS} WriteDebug('Ext2InitInode: invalid inode number\n', [Inode.ino]); {$ENDIF}
    Exit;
  end;
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

  with Inode^ do
  begin
    Size:= 0;
    ATime:= Ext2GetSeconds;
    MTime:= ATime;
    CTime:= ATime;
    DTime:= 0;
    Mode:= cache_mode;
    Dirty:= False;
  end;

  // cleaning entries
  InoInfo:= Inode.InoInfo;
  with InoInfo^ do
  begin
    for I := 1 to 15 do
        data[I] :=0;
    block_group:= block_group;
    blocks:= 0;
    if cache_mode = INODE_DIR then
       links_count:= 2
    else
       links_count:= 1;
  end;
  // we first clean the memory
  FillChar(raw_Inode^,sizeof(Ext2_Inode),0);
  with raw_Inode^ do
  begin
    dtime:= 0;
    atime:= Inode^.ATime;
    ctime:= atime;
    mtime:= atime;
    mode:= i_mode;
    if cache_mode = INODE_DIR then
       links_count:= 2
    else
       links_count:= 1;
  end;

  // the block that contains the inode is marked as dirty
  bh.Dirty:= True;
  PutBlock (Inode.SuperBlock.BlockDevice, bh);
  {$IFDEF DebugExt2FS} WriteDebug('Ext2InitInode: initializing Inode: %d, Inode.atime: %d\n', [Inode.ino, raw_Inode^.atime]); {$ENDIF}
end;

// Ext2CreateInode:
// Create a new Inode in Base and name it as Name.
// Returns the new inode
function Ext2CreateInode(Inode: PInode; const Name: AnsiString): PInode;
var
  SbInfo: P_Ext2_sb_info;
  bh_gdp, bh: PBufferHead;
  gdp: P_ext2_group_desc;
  block_group, group_desc, desc, block_bitmap, bitmap_size_in_blocks: longint;
  k, j, nr_inode: longint;
  p: PByte;
  NInode: PInode;
label do_inode;
begin
   // group descriptor
  SbInfo:= Inode.SuperBlock.SbInfo;
  block_group:= (Inode.ino-1) div (SbInfo.inodes_per_group);
  group_desc:= block_group div SbInfo.desc_per_block;
  desc:= block_group and (SbInfo.desc_per_block -1);

  {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: Inode: %d\n', [Inode.ino]); {$ENDIF}
  {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: groups_desc: %d, desc: %d\n', [group_desc,desc]); {$ENDIF}

  // buffer head that points to the group descriptor block
  bh_gdp := Pointer(PtrUInt(SbInfo.group_desc)+group_desc);
  gdp := bh_gdp.data;

  // we check if we have enough free blocks
  if (gdp^[desc].free_inodes_count = 0) then
  begin
    {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: no more free inodes for Inode: %d\n', [Inode.ino]); {$ENDIF}
    Result:= nil;
  end;

  {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: free_blocks_count is %d\n', [gdp^[desc].free_blocks_count]); {$ENDIF}

  // we get the block bitmat
  block_bitmap:= gdp^[desc].inode_bitmap;
  bitmap_size_in_blocks := ((SbInfo.inodes_per_group div 8) div Inode.SuperBlock.BlockSize)+1;
  {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: block_bitmap: %d\n', [block_bitmap]); {$ENDIF}

  // I look for a free block for the the first indirect block
  for k:= 0 to (bitmap_size_in_blocks-1) do
  begin
    bh := GetBlock(Inode.SuperBlock.BlockDevice, block_bitmap+k, Inode.SuperBlock.BlockSize);
    p := bh.data;
    for j:= 0 to ((Inode.SuperBlock.BlockSize * 8) -1) do
    begin
      if ((p[j div 8] and (1 shl (j mod 8))) = 0) then
      begin
        // we mark it as busy
        p[j div 8] := p[j div 8] or (1 shl (j mod 8));
        nr_inode := SbInfo.inodes_per_group * block_group + k*(Inode.SuperBlock.BlockSize * 8) + j + 1;
        {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: free Inode: %d\n', [nr_inode]); {$ENDIF}
        gdp^[desc].free_inodes_count := gdp^[desc].free_inodes_count -1;
        // descriptor block is marked as dirty
        bh_gdp.Dirty:= True;
        // we update the descriptor group
        WriteBlock(Inode.SuperBlock.BlockDevice, bh_gdp);
        // bitmap block is marked as dirty
        bh.Dirty:= True;
        // we update the bitmap block
        WriteBlock(Inode.SuperBlock.BlockDevice, bh);
        PutBlock(Inode.SuperBlock.BlockDevice, bh);
        // we decrement the number of free inodes in sp
        SbInfo.free_inodes_count:= SbInfo.free_inodes_count - 1;
        Ext2WriteSuper(Inode.SuperBlock);
        goto do_inode;
      end;
    end;
  PutBlock(Inode.SuperBlock.BlockDevice, bh);
  end;

  // no free inode
  Result:= nil;
  Exit;
  {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: no enough space for indirect block\n', []); {$ENDIF}
do_inode:

  // we get the free inode
  NInode := GetInode (nr_inode);
  If NInode = nil then
  begin
    {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: error when doing GetInode\n', []); {$ENDIF}
    Result := nil;
    Exit;
  end;

  // clean Inode
  Ext2InitInode(NInode, INODE_REG , Ext2_Mode_Reg or Ext2_File_Mode);
  if AddFiletoInodeDir (Inode, Name, nr_inode) then
  begin
    Ext2WriteInode(Inode);
    Result := NInode;
    {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: New entry created\n', []); {$ENDIF}
  end else
  {$IFDEF DebugFS} WriteDebug('Ext2CreateInode: error when doing AddFileToInodeDire\n', []); {$ENDIF}
end;

// Ext2CreateInodeDir:
function Ext2CreateInodeDir(Inode: PInode; const Name: AnsiString): PInode;
var
  SbInfo: P_Ext2_sb_info;
  bh_gdp, bh: PBufferHead;
  gdp: P_ext2_group_desc;
  block_group, group_desc, desc, block_bitmap, bitmap_size_in_blocks: longint;
  k, j, nr_inode: longint;
  p: PByte;
  NInode: PInode;
label do_inode;
begin
   // group descriptor
  SbInfo:= Inode.SuperBlock.SbInfo;
  block_group:= (Inode.ino-1) div (SbInfo.inodes_per_group);
  group_desc:= block_group div SbInfo.desc_per_block;
  desc:= block_group and (SbInfo.desc_per_block -1);
  {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: Inode: %d\n', [Inode.ino]); {$ENDIF}
  {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: groups_desc: %d, desc: %d\n', [group_desc,desc]); {$ENDIF}
  // buffer head that points to the group descriptor block
  bh_gdp := Pointer(PtrUInt(SbInfo.group_desc)+group_desc);
  gdp := bh_gdp.data;
  // we check if we have enough free blocks
  if (gdp^[desc].free_inodes_count = 0) then
  begin
    {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: no more free inodes for Inode: %d\n', [Inode.ino]); {$ENDIF}
    Result:= nil;
  end;

  {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: free_blocks_count is %d\n', [gdp^[desc].free_blocks_count]); {$ENDIF}

  // we get the block bitmat
  block_bitmap:= gdp^[desc].inode_bitmap;
  bitmap_size_in_blocks := ((SbInfo.inodes_per_group div 8) div Inode.SuperBlock.BlockSize)+1;
  {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: block_bitmap: %d\n', [block_bitmap]); {$ENDIF}
  // I look for a free block for the the first indirect block
  for k:= 0 to (bitmap_size_in_blocks-1) do
  begin
    bh := GetBlock(Inode.SuperBlock.BlockDevice, block_bitmap+k, Inode.SuperBlock.BlockSize);
    p := bh.data;
    for j:= 0 to ((Inode.SuperBlock.BlockSize * 8) -1) do
    begin
      if ((p[j div 8] and (1 shl (j mod 8))) = 0) then
      begin
        // we mark it as busy
        p[j div 8] := p[j div 8] or (1 shl (j mod 8));
        nr_inode := SbInfo.inodes_per_group * block_group + k*(Inode.SuperBlock.BlockSize * 8) + j + 1;
        {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: free Inode: %d\n', [nr_inode]); {$ENDIF}
        gdp^[desc].free_inodes_count := gdp^[desc].free_inodes_count - 1;
        // we increment the number of directories
        gdp^[desc].used_dirs_count:= gdp^[desc].used_dirs_count + 1;
        // descriptor block is marked as dirty
        bh_gdp.Dirty:= True;
        // we update the descriptor group
        WriteBlock(Inode.SuperBlock.BlockDevice, bh_gdp);
        // bitmap block is marked as dirty
        bh.Dirty:= True;
        // we update the bitmap block
        WriteBlock(Inode.SuperBlock.BlockDevice, bh);
        PutBlock(Inode.SuperBlock.BlockDevice, bh);
        // we decrement the number of free inodes in sp
        SbInfo.free_inodes_count:= SbInfo.free_inodes_count - 1;
        Ext2WriteSuper(Inode.SuperBlock);
        goto do_inode;
      end;
    end;
  PutBlock(Inode.SuperBlock.BlockDevice, bh);
  end;
  // no free inode
  Result:= nil;
  Exit;
  {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: no enough space for indirect block\n', []); {$ENDIF}
do_inode:
  // we get the free inode
  // TODO: should I use GetInode when Inode is created from zero?
  NInode := GetInode (nr_inode);
  If NInode = nil then
  begin
    {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: error when doing GetInode\n', []); {$ENDIF}
    Result := nil;
    Exit;
  end;
  // clean Inode
  Ext2InitInode(NInode, INODE_DIR, Ext2_Mode_Dir or Ext2_Dir_Mode);
  if not AddDirtoInodeDir (Inode, Name, nr_inode) then
  begin
    {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: error when doing AddFileToInodeDire\n', []); {$ENDIF}
    Result := nil;
    Exit;
  end;
  // we create the . and .. entry
  if not InitializeInodeDir (NInode, Inode.ino) then
  begin
    {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: failed to create . and .. entry\n', []); {$ENDIF}
    Result := nil;
    Exit;
  end;
  {$IFDEF DebugFS} WriteDebug('Ext2CreateInodeDir: new Inode created: %d\n', [nr_inode]); {$ENDIF}
  // we ensure the Inode is written
  Ext2WriteInode(Inode);
  Inode.Dirty:= False;
  Result := NInode;
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
  // Invalid inode number!
  if (Inode.ino<>2) and(inode.ino<11) and (inode.ino > SbInfo.inodes_count) then
  begin
    {$IFDEF DebugExt2FS} WriteDebug('Ext2FS: Invalid inode number\n',[]); {$ENDIF}
    Exit;
  end;
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
  if (raw_inode.mode and $4000 <> $4000) and (raw_inode.mode and $8000 <> $8000) and (raw_inode.mode <> 0) then
  begin
    PutBlock(Inode.SuperBlock.BlockDevice,bh);
    {$IFDEF DebugExt2FS} WriteDebug('Ext2ReadInode: Inode mode not supported , Inode: %d\n', [Inode.ino]); {$ENDIF}
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
  InoInfo.blocks:= raw_inode.blocks;
  InoInfo.links_count:= raw_inode.links_count;
  Inode.Dirty:= False;
  Inode.ATime:= Raw_Inode.atime;
  Inode.CTime:= raw_Inode.ctime;
  Inode.DTime:= raw_Inode.dtime;
  Inode.MTime:= raw_Inode.atime;
  Inode.Size := raw_Inode.size;
  {$IFDEF DebugExt2FS}
          WriteDebug('Ext2ReadInode: Dumping Inode: %d\n',[Inode.ino]);
          WriteDebug('Ext2ReadInode: atime: %d, ctime: %d, dtime: %d\n',[Raw_Inode.atime,Raw_Inode.ctime,Raw_Inode.dtime]);
          WriteDebug('Ext2ReadInode: blocks: %d, links_count: %d, size: %d\n',[Raw_Inode.blocks,Raw_Inode.links_count,Raw_Inode.size]);
  {$ENDIF}
  // only directories and Regular files
  if raw_inode.mode and $4000 = $4000 then
    Inode.Mode := INODE_DIR
  else
    Inode.Mode:= INODE_REG;
  // getting direct and indirect blocks
  for I := 1 to 15 do
    InoInfo.data[I]:= raw_inode.block[I];
  // return the block to the cache
  PutBlock(Inode.SuperBlock.BlockDevice, bh);
  {$IFDEF DebugExt2FS} WriteDebug('Ext2ReadInode: Inode %d, Read Ok\n',[Inode.ino]); {$ENDIF}
end;

// Add a new entry to an Inode directory
function AddFiletoInodeDir(Ino: PInode; const Name: AnsiString; Inode: longint): Boolean;
var
  last_i, J: longint;
  InoInfo: ^ext2_inode_info;
  bh : PBufferHead;
  Offset: longint;
  entry: P_Ext2_Dir_Entry;
  prev_rec_len: word;
begin
  InoInfo := Ino.InoInfo;
  Result := False;
  last_i := Ino.Size div Ino.SuperBlock.BlockSize;
  if (last_i > 12) then
  begin
    {$IFDEF DebugFS} WriteDebug('AddFiletoInodeDir: directory too big!\n', []); {$ENDIF}
    Exit;
  end;
  // we check if the indice has been assigned
  if InoInfo.data[last_i] <> 0 then
    begin
      bh := GetBlock(Ino.SuperBlock.BlockDevice,InoInfo.data[last_i], Ino.SuperBlock.BlockSize);
      if bh = nil then
      begin
        {$IFDEF DebugFS} WriteDebug('AddFiletoInodeDir: error when reading a block\n', []); {$ENDIF}
        Exit; // error in read operations
      end;
    {$IFDEF DebugFS} WriteDebug('AddFiletoInodeDir: getting Indice %d\n', [last_i]); {$ENDIF}
    end else
    begin
       if not (AddFreeBlocktoInode(Ino, last_i)) then
       begin
        {$IFDEF DebugFS} WriteDebug('AddFiletoInodeDir: error when adding free block to inode\n', []); {$ENDIF}
        Exit; // error in read operations
       end;
       bh := GetBlock(Ino.SuperBlock.BlockDevice,InoInfo.data[last_i], Ino.SuperBlock.BlockSize);
       if bh = nil then
       begin
         {$IFDEF DebugFS} WriteDebug('AddFiletoInodeDir: error when reading a block\n', []); {$ENDIF}
         Exit; // error in read operations
       end;
       // the directory size is incremented in one block
       Ino.Size:= Ino.Size + Ino.SuperBlock.BlockSize ;
    end;

    // we go to last directory
    Offset:= 0;
    while Offset < Ino.SuperBlock.BlockSize do
    begin
      entry:= Pointer(PtrUInt(bh.data)+Offset);
      Offset := Offset + entry.rec_len;
      {$IFDEF DebugFS} WriteDebug('AddFiletoInodeDir: Offset: %d \n', [Offset]); {$ENDIF}
    end;
    // offset points to 1024
    prev_rec_len := entry.rec_len;
    entry.rec_len := sizeof(Ext2_Dir_Entry) - sizeof(Ext2_Dir_Entry.name) + entry.name_len - 1 + 4 - (sizeof(Ext2_Dir_Entry) - sizeof(Ext2_Dir_Entry.name) + entry.name_len - 1) mod 4;
    prev_rec_len := prev_rec_len - entry.rec_len;
    {$IFDEF DebugFS} WriteDebug('AddFiletoInodeDir: entry.rec_len: %d, test: %d\n', [entry.rec_len, sizeof(Ext2_Dir_Entry) - sizeof(Ext2_Dir_Entry.name) + entry.name_len - 1]); {$ENDIF}
    entry := Pointer(PtrUInt(entry)+ entry.rec_len);
    entry.inode := Inode;
    for J:= 0 to Length(Name) do
        entry.name[J] := name[J+1];
    entry.name_len := Length(Name);
    entry.file_type := Ext2_FT_Reg;
    entry.rec_len:= prev_rec_len;
    {$IFDEF DebugFS} WriteDebug('AddFiletoInodeDir: prev_rec_len: %d, entry.rec_len: %d \n', [prev_rec_len,entry.rec_len]); {$ENDIF}
    bh.Dirty := True;
    PutBlock (Ino.SuperBlock.BlockDevice, bh);
    // we increment the links count of the dir inode
    Ino.Dirty:= True;
    Result:= True;
end;

// Add a new entry to an Inode directory
function AddDirtoInodeDir(Ino: PInode; const Name: AnsiString; Inode: longint): Boolean;
var
  last_i, J: longint;
  InoInfo: ^ext2_inode_info;
  bh : PBufferHead;
  Offset: longint;
  entry: P_Ext2_Dir_Entry;
  prev_rec_len: word;
begin
  InoInfo := Ino.InoInfo;
  Result := False;
  last_i := Ino.Size div Ino.SuperBlock.BlockSize;
  if (last_i > 12) then
  begin
    {$IFDEF DebugFS} WriteDebug('AddDirtoInodeDir: directory too big!\n', []); {$ENDIF}
    Exit;
  end;
  // we check if the indice has been assigned
  if InoInfo.data[last_i] <> 0 then
    begin
      bh := GetBlock(Ino.SuperBlock.BlockDevice,InoInfo.data[last_i], Ino.SuperBlock.BlockSize);
      if bh = nil then
      begin
        {$IFDEF DebugFS} WriteDebug('AddDirtoInodeDir: error when reading a block\n', []); {$ENDIF}
        Exit; // error in read operations
      end;
    {$IFDEF DebugFS} WriteDebug('AddDirtoInodeDir: getting Indice %d\n', [last_i]); {$ENDIF}
    end else
    begin
       if not (AddFreeBlocktoInode(Ino, last_i)) then
       begin
        {$IFDEF DebugFS} WriteDebug('AddDirtoInodeDir: error when adding free block to inode\n', []); {$ENDIF}
        Exit; // error in read operations
       end;
       bh := GetBlock(Ino.SuperBlock.BlockDevice,InoInfo.data[last_i], Ino.SuperBlock.BlockSize);
       if bh = nil then
       begin
         {$IFDEF DebugFS} WriteDebug('AddDirtoInodeDir: error when reading a block\n', []); {$ENDIF}
         Exit; // error in read operations
       end;
       // directory size is incremented when a block is added
       Ino.Size:= Ino.Size + Ino.SuperBlock.BlockSize;
    end;

    // we go to last directory
    Offset:= 0;
    while Offset < Ino.SuperBlock.BlockSize do
    begin
      entry:= Pointer(PtrUInt(bh.data)+Offset);
      Offset := Offset + entry.rec_len;
      {$IFDEF DebugFS} WriteDebug('AddDirtoInodeDir: Offset: %d \n', [Offset]); {$ENDIF}
    end;
    // offset points to 1024
    prev_rec_len := entry.rec_len;
    entry.rec_len := sizeof(Ext2_Dir_Entry) - sizeof(Ext2_Dir_Entry.name) + entry.name_len - 1 + 4 - (sizeof(Ext2_Dir_Entry) - sizeof(Ext2_Dir_Entry.name) + entry.name_len - 1) mod 4;
    prev_rec_len := prev_rec_len - entry.rec_len;
    {$IFDEF DebugFS} WriteDebug('AddDirtoInodeDir: entry.rec_len: %d, test: %d\n', [entry.rec_len, sizeof(Ext2_Dir_Entry) - sizeof(Ext2_Dir_Entry.name) + entry.name_len - 1]); {$ENDIF}
    entry := Pointer(PtrUInt(entry)+ entry.rec_len);
    entry.inode := Inode;
    for J:= 0 to Length(Name) do
        entry.name[J] := name[J+1];
    entry.name_len := Length(Name);
    entry.file_type := Ext2_FT_Dir;
    entry.rec_len:= prev_rec_len;
    {$IFDEF DebugFS} WriteDebug('AddDirtoInodeDir: prev_rec_len: %d, entry.rec_len: %d \n', [prev_rec_len,entry.rec_len]); {$ENDIF}
    bh.Dirty := True;
    PutBlock (Ino.SuperBlock.BlockDevice, bh);
    {$IFDEF DebugFS} WriteDebug('AddDirtoInodeDir: old inode size: %d\n', [Ino.Size]); {$ENDIF}
    // we increment the links count of the dir inode
    InoInfo.links_count:= InoInfo.links_count + 1;
    Ino.Dirty:= True;
    Result:= True;
end;

// Add a new entry to an Inode directory
function InitializeInodeDir(Ino: PInode; Inode: longint): Boolean;
var
  InoInfo: ^ext2_inode_info;
  bh : PBufferHead;
  entry: P_Ext2_Dir_Entry;
begin
  InoInfo := Ino.InoInfo;
  Result := False;
  if not (AddFreeBlocktoInode(Ino, 1)) then
  begin
    {$IFDEF DebugFS} WriteDebug('InitializeInodeDir: error when adding free block to inode\n', []); {$ENDIF}
    Exit; // error in read operations
  end;
  bh := GetBlock(Ino.SuperBlock.BlockDevice,InoInfo.data[1], Ino.SuperBlock.BlockSize);
  if bh = nil then
  begin
    {$IFDEF DebugFS} WriteDebug('InitializeInodeDir: error when reading a block\n', []); {$ENDIF}
    Exit; // error in read operations
  end;
  // first entry
  entry := bh.data;
  entry.file_type := Ext2_FT_Dir;
  entry.name_len := 1;
  entry.inode := Ino.ino;
  entry.name[0] := '.';
  entry.rec_len:= 12;

  // second entry
  entry := Pointer(PtrUInt(bh.data) + entry.rec_len);
  entry.file_type := Ext2_FT_Dir;
  entry.name_len := 2;
  entry.inode := Inode;
  entry.name[0] := '.';
  entry.name[1] := '.';
  entry.rec_len := 1012;

  bh.Dirty := True;
  PutBlock (Ino.SuperBlock.BlockDevice, bh);
  Ino.Size:= Ino.SuperBlock.BlockSize;
  Ino.Dirty:= True;

  {$IFDEF DebugFS} WriteDebug('InitializeInodeDir: itself: %d, parent: %d\n', [Ino.ino, Inode]); {$ENDIF}
  Result:= True;
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
    {$IFDEF DebugFS} WriteDebug('Ext2LookUpInode: Inode: %d, entry: %d, Block: %d\n', [Ino.ino, I,InoInfo.data[I]]); {$ENDIF}
    if InoInfo.data[I] <> 0 then
    begin
      bh := GetBlock(Ino.SuperBlock.BlockDevice,InoInfo.data[I], Ino.SuperBlock.BlockSize);
      if bh = nil then
      begin
        {$IFDEF DebugFS} WriteDebug('Ext2LookUpInode: error when reading a block\n', []); {$ENDIF}
        Exit; // error in read operations
      end;
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
          {$IFDEF DebugFS} WriteDebug('Ext2LookUpInode: Inode found\n', []); {$ENDIF}
          PutBlock(Ino.SuperBlock.BlockDevice,bh);
          Exit
        end;
      {$IFDEF DebugFS} WriteDebug('Ext2LookUpInode: Offset %d\n', [Offset]); {$ENDIF}
      end;
      PutBlock(Ino.SuperBlock.BlockDevice,bh);
    end;
  end;
  {$IFDEF DebugFS} WriteDebug('Ext2LookUpInode: Inode not found\n', []); {$ENDIF}
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
    Result := buffer^[(block-12)-1];
    PutBlock(Inode.SuperBlock.BlockDevice, bh);
    // More Blocks are not supported
  end else
    Result := 0;
end;

// Add a block into the inode structure. It is based on the size of the inode.
// Note: This function is limited to 4MB files
//
function AddBlocktoInode(Inode: PInode; Indice: longint; Block: longint): Boolean;
var
  InoInfo: ^ext2_inode_info;
  lasti_entry, tmp_block: LongInt;
  bh: PBufferHead;
  buffer: PLongIntArray;
begin
  // last free entry in inode structure
  lasti_entry := Indice;
  InoInfo:= Inode.InoInfo;
  {$IFDEF DebugFS} WriteDebug('AddBlocktoInode: Inode: %d, Indice: %d, Block: %d\n', [Inode.ino, Indice, Block]); {$ENDIF}
  // directs blocks
  if (lasti_entry <= 12) then
  begin
    InoInfo.data[lasti_entry] := Block;
    // we need to update the inode in disk
    Inode.Dirty := True;
    Result := True;
  end
  else if lasti_entry <= (12 + Inode.SuperBlock.BlockSize div 4) then
  begin
    tmp_block := InoInfo.data[13];
    bh := GetBlock(Inode.SuperBlock.BlockDevice,tmp_block,Inode.SuperBlock.BlockSize);
    // error in read operations
    if bh = nil then
    begin
      Result:=False;
      Exit;
    end;
    buffer := bh.data;
    buffer^[(lasti_entry-12)-1] := Block;
    bh.dirty := True;
    PutBlock(Inode.SuperBlock.BlockDevice, bh);
    Result:=True;
    // More Blocks are not supported
  end else
    Result := False;
end;

// AddFreeBlockToInode
// Add a number of free blocks to an inode
// Note: This function is limited to 4MB files
//
function AddFreeBlocktoInode (Inode: PInode; I: longint): Boolean;
var
  SbInfo: P_Ext2_sb_info;
  bh_gdp, bh: PBufferHead;
  gdp: P_ext2_group_desc;
  block_group, group_desc, desc, block_bitmap, bitmap_size_in_blocks: longint;
  k, j: longint;
  p: PByte;
  InoInfo: ^ext2_inode_info;
label do_direct;
begin
  // group descriptor
  SbInfo:= Inode.SuperBlock.SbInfo;
  block_group:= (Inode.ino-1) div (SbInfo.inodes_per_group);
  group_desc:= block_group div SbInfo.desc_per_block;
  desc:= block_group and (SbInfo.desc_per_block -1);
  InoInfo:= Inode.InoInfo;
  {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode: Inode: %d, entry: %d\n', [Inode.ino,I]); {$ENDIF}
  {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode: groups_desc: %d, desc: %d\n', [group_desc,desc]); {$ENDIF}

  // buffer head that points to the group descriptor block
  bh_gdp := Pointer(PtrUInt(SbInfo.group_desc)+group_desc);
  gdp := bh_gdp.data;

  // we check if we have enough free blocks
  if (gdp^[desc].free_blocks_count = 0) then
  begin
    {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode: no more free blocks for Inode: %d\n', [Inode.ino]); {$ENDIF}
    Result:= False;
  end;

  {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode: free_blocks_count is %d\n', [gdp^[desc].free_blocks_count]); {$ENDIF}

  // we get the block bitmat
  block_bitmap:= gdp^[desc].block_bitmap;

  // size of a bitmap in blocks
  bitmap_size_in_blocks := ((SbInfo.blocks_per_group div 8) div Inode.SuperBlock.BlockSize) + 1;
  {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode: BitmapBlock: %d, BitmapSizeInBlocks: %d\n', [block_bitmap, bitmap_size_in_blocks]); {$ENDIF}

  // I check if the first indirect block has been assigned
  If ( I > 12) and (I <= (12 + Inode.SuperBlock.BlockSize div 4)) and (InoInfo.data[13] = 0) then
  begin
      // I look for a free block for the the first indirect block
      for k:= 0 to (bitmap_size_in_blocks-1) do
      begin
        bh := GetBlock(Inode.SuperBlock.BlockDevice, block_bitmap+k, Inode.SuperBlock.BlockSize);
        p := bh.data;
        for j:= 0 to ((Inode.SuperBlock.BlockSize * 8) -1) do
        begin
          if ((p[j div 8] and (1 shl (j mod 8))) = 0) then
          begin
            p[j div 8] := p[j div 8] or (1 shl (j mod 8));
            InoInfo.data[13] := k*(Inode.SuperBlock.BlockSize * 8) + j + 1;
            {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode: first indirect block: %d to Inode: %d\n', [InoInfo.data[13], PtrUInt(Inode)]); {$ENDIF}
            Inode.Dirty := True;
            gdp^[desc].free_blocks_count := gdp^[desc].free_blocks_count -1;
            // descriptor block is marked as dirty
            bh_gdp.Dirty:= True;
            // we update the descriptor group
            WriteBlock(Inode.SuperBlock.BlockDevice, bh_gdp);
            // bitmap block is marked as dirty
            bh.Dirty:= True;
            // we update the bitmap block
            WriteBlock(Inode.SuperBlock.BlockDevice, bh);
            PutBlock(Inode.SuperBlock.BlockDevice, bh);
            // we decrement the number of free blocks in sp
            SbInfo.free_blocks_count:= SbInfo.free_blocks_count - 1;
            Ext2WriteSuper(Inode.SuperBlock);
            goto do_direct;
          end;
        end;
      PutBlock(Inode.SuperBlock.BlockDevice, bh);
      end;
      {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode: no enough space for indirect block\n', []); {$ENDIF}
      Result := False;
      exit;
  end;
  do_direct:
  // direct block only
  for k:= 0 to (bitmap_size_in_blocks-1) do
  begin
      bh := GetBlock(Inode.SuperBlock.BlockDevice, block_bitmap+k, Inode.SuperBlock.BlockSize);
      {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode: getting block %d\n', [block_bitmap+k]); {$ENDIF}
      p := bh.data;
      // we look for the first bit free
      for j:= 0 to ((Inode.SuperBlock.BlockSize * 8) -1) do
      begin
          if ((p[j div 8] and (1 shl (j mod 8))) = 0) then
          begin
             p[j div 8] := p[j div 8] or (1 shl (j mod 8));

            {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode: found free block %d, pos_bitmap: %d\n', [k*(Inode.SuperBlock.BlockSize * 8) + j + 1, j]); {$ENDIF}

            // we add the block to the inode
            if AddBlocktoInode (Inode, I, k*(Inode.SuperBlock.BlockSize * 8) + j + 1) then
            begin
                 InoInfo.blocks:= InoInfo.blocks + Inode.SuperBlock.BlockSize div 512;
                 {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode:  Added block to inode, blocks: %d\n', [InoInfo.blocks]); {$ENDIF}
            end else
            begin
                 {$IFDEF DebugFS} WriteDebug('AddFreeBlocktoInode:  Fail to add block to Inode\n', []); {$ENDIF}
                 Result := False;
                 Exit;
            end;
            Inode.Dirty := True;
            gdp^[desc].free_blocks_count := gdp^[desc].free_blocks_count -1;

            // descriptor block is marked as dirty
            bh_gdp.Dirty:= True;

            // we update the descriptor group
            WriteBlock(Inode.SuperBlock.BlockDevice, bh_gdp);

            // bitmap block is marked as dirty
            bh.Dirty:= True;

            // we update the bitmap block
            WriteBlock(Inode.SuperBlock.BlockDevice, bh);
            PutBlock(Inode.SuperBlock.BlockDevice, bh);

            // we decrement the number of free blocks in sp
            SbInfo.free_blocks_count:= SbInfo.free_blocks_count - 1;
            Ext2WriteSuper(Inode.SuperBlock);

            Result := True;
            exit;
          end;
      end;
      PutBlock(Inode.SuperBlock.BlockDevice, bh);
  end;
Result:= False;
end;

//
// Write to a regular file in a ext2 fs
//
function Ext2WriteFile (FileDesc: PFileRegular; Count: longint; Buffer: Pointer): longint;
var
  initoff, Len: longint;
  nrfreeblks, real_block, start_block, J, last_block, lastoff: longint;
  i_off, end_off: longint;
  ret: Boolean;
  bh: PBufferHead;
begin

  // starting block
  start_block := (FileDesc.FilePos div FileDesc.Inode.SuperBlock.BlockSize) + 1;
  last_block := ((FileDesc.FilePos + Count) div  FileDesc.Inode.SuperBlock.BlockSize) +1;

  // initial and final offset
  initoff := FileDesc.FilePos mod FileDesc.Inode.SuperBlock.BlockSize;
  lastoff := (FileDesc.FilePos + Count) mod FileDesc.Inode.SuperBlock.BlockSize;

  Len := 0;
  {$IFDEF DebugFS} WriteDebug('Ext2WriteFile: start_block: %d, last_block: %d, initoff: %d, lastoff: %d, Size: %d\n', [start_block, last_block, initoff, lastoff, FileDesc.Inode.Size]); {$ENDIF}

  // we need to populate the inode
  if (start_block > (FileDesc.Inode.Size div FileDesc.Inode.SuperBlock.BlockSize)+1) then
  begin
    nrfreeblks := start_block - ((FileDesc.Inode.Size div FileDesc.Inode.SuperBlock.BlockSize)+1);
    {$IFDEF DebugFS} WriteDebug('Ext2WriteFile: populating Inode %d with %d blocks\n', [FileDesc.Inode.ino, nrfreeblks]); {$ENDIF}
    // we need to add free blocks to the inode
    for J:= 0 to (nrfreeblks-1) do
    begin
      ret := AddfreeblockToInode(FileDesc.Inode, J+1);
      if not ret then
      begin
        {$IFDEF DebugFS} WriteDebug('Ext2WriteFile: fail at populating Inode %d\n', [FileDesc.Inode.ino]); {$ENDIF}
         Result :=0;
      end;
    end;
  end;

  // we start to move the data from user to buffer cache
  for J := start_block to last_block do
  begin
    real_block := Get_Real_Block(J, FileDesc.Inode);
    {$IFDEF DebugFS} WriteDebug('Ext2WriteFile: getting block %d, real_block: %d\n', [J, real_block]); {$ENDIF}

    // we check if the entry has been populated
    // if not, we try to populate it
    if real_block = 0 then
    begin
       ret := AddFreeBlocktoInode (FileDesc.Inode, J);
       if not ret then
       begin
         {$IFDEF DebugFS} WriteDebug('Ext2WriteFile: failling at adding a free block\n', []); {$ENDIF}
         exit;
       end;
       real_block := Get_Real_Block(J, FileDesc.Inode);
       {$IFDEF DebugFS} WriteDebug('Ext2WriteFile: populating Indice %d with block %d\n', [J, real_block]); {$ENDIF}
    end;

    // we request the block to the buffer cache
    bh:= GetBlock(FileDesc.Inode.SuperBlock.BlockDevice,real_block,FileDesc.Inode.SuperBlock.BlockSize);

    // Hardware error
    if bh = nil then
      break;

    if ( J = start_block) then
      i_off := initoff
    else i_off := 0;

    if (J = last_block) then
       end_off := lastoff
    else end_off := FileDesc.Inode.SuperBlock.BlockSize;

    Move(PByte(Buffer)^, PByte(PtrUInt(bh.data)+i_off)^, end_off - i_off);
    Buffer := Pointer(PtrUInt(Buffer) + end_off - i_off);
    Len := Len + end_off - i_off;
    FileDesc.FilePos := FileDesc.FilePos + end_off - i_off;
    {$IFDEF DebugFS} WriteDebug('Ext2WriteFile: i_off: %d, end_off: %d, FilePos: %d, Len: %d\n', [initoff, end_off, FileDesc.FilePos, Len]); {$ENDIF}
    // we mark it as dirty
    // we return it to the cache
    bh.Dirty:= True;
    PutBlock(FileDesc.Inode.SuperBlock.BlockDevice,bh);
  end;

  Result := Len;

  // if we write something
  // we modify the modification access time
  if Result <> 0 then
  begin
     FileDesc.Inode.MTime:= Ext2GetSeconds;
  end;

  // TODO: It updates the inode only if size increments, is that right?
  if FileDesc.FilePos > FileDesc.Inode.Size then
  begin
     FileDesc.Inode.Size:= FileDesc.FilePos;
     // write inode inmediatly
     Ext2WriteInode(FileDesc.Inode);
  end;

  {$IFDEF DebugFS} WriteDebug('Ext2WriteFile: written %d, new inode size: %d\n', [Result,FileDesc.Inode.Size]); {$ENDIF}
end;

// Read Regular File from Ext2 Filesystem , support up to 4MB per file , usign 4096 bytes physic blocks.
function Ext2ReadFile(FileDesc: PFileRegular; Count: longint; Buffer: Pointer): longint;
var 
  I, blocksize:longint;
  nb_block, start_block, real_block, initoff, Len: longint;
  bh : PBufferHead;
begin
  if FileDesc.FilePos + Count > FileDesc.Inode.Size then
  begin
    {$IFDEF DebugFS} WriteDebug('Ext2ReadFile: reading after end, pos:%d, size:%d\n', [FileDesc.FilePos, FileDesc.Inode.Size ]); {$ENDIF}
    Count:= FileDesc.Inode.Size - FileDesc.FilePos;
  end;
  blocksize := Filedesc.Inode.SuperBlock.Blocksize;
  nb_block := Count div blocksize;
  initoff := FileDesc.FilePos mod Blocksize;
  start_block:= (FileDesc.FilePos div blocksize)+1;
  if Count mod blocksize <> 0 then
    nb_block:= nb_block +1;
  Len := Count;
   {$IFDEF DebugFS} WriteDebug('Ext2ReadFile: reading Count:%d, Len:%d, StartBlock: %d, EndBlock: %d\n', [PtrUInt(Count),PtrUInt(Len),start_block,start_block+nb_block-1 ]); {$ENDIF}
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
      Buffer := Pointer(PtrUInt(Buffer) + Blocksize - initoff);
      Len := Len - Blocksize + initoff;
      initoff := 0;
    end else
    begin
      Move(PByte(PtrUInt(bh.data)+initoff)^, PByte(Buffer)^, Len);
      initoff := 0 ;
      FileDesc.FilePos := FileDesc.FilePos + Len;
      Len := 0 ;
    end;
    PutBlock(FileDesc.Inode.SuperBlock.BlockDevice,bh);
  end;
  Result := Count-Len;
  {$IFDEF DebugFS} WriteDebug('Ext2ReadFile: Result: %d, Filepos: %d\n', [Result, FileDesc.FilePos]); {$ENDIF}
end;

// Initialization of Ext2 Filesystem

initialization
  WriteConsoleF('Ext2 driver ... /Vinstalled/n\n',[]);
  Ext2Driver.name := 'ext2';
  Ext2Driver.ReadSuper := @Ext2ReadSuper;
  Ext2Driver.CreateInode := @Ext2CreateInode;
  Ext2Driver.CreateInodeDir := @Ext2CreateInodeDir;
  Ext2Driver.ReadInode := @Ext2ReadInode;
  Ext2Driver.WriteInode := @Ext2WriteInode;
  Ext2Driver.LookUpInode := @Ext2LookUpInode;
  Ext2Driver.ReadFile := @Ext2ReadFile;
  Ext2Driver.WriteFile := @Ext2WriteFile;
  RegisterFilesystem(@Ext2Driver);
end.
