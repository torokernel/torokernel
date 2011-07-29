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
      name      : array [0..254] of char;
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
result:= nil;
if bh=nil then
begin
 WriteConsole('Ext2FS: Unabled to read SuperBlock\n',[]);
 exit;
end;
SuperExt2:= bh.data;
if (SuperExt2.magic <> $EF53) then
begin
 PutBlock(Super.BlockDevice,bh);
 WriteConsole('Ext2FS: Bad magic number in SuperBlock\n',[]);
 exit
end else if (SuperExt2.log_block_size>2) then
begin
 PutBlock(Super.BlockDevice,bh);
 WriteConsole('Ext2FS: Logical Block Size is not supported\n',[]);
 exit;
end;
case (SuperExt2.log_block_size) of
0:Super.BlockSize:= 1024;
1:Super.BlockSize:= 2048;
2:Super.BlockSize:= 4096;
end;
SpbInfo:= ToroGetMem(sizeof(Ext2_Sb_Info));
if SpbInfo=nil then
begin
 PutBlock(Super.BlockDevice,bh);
 exit;
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
// not more memory??
if SpbInfo.Group_Desc=nil then
begin
 ToroFreeMem(SpbInfo);
 PutBlock(Super.BlockDevice,bh);
 WriteConsole('Ext2FS: Not memory for Descriptor\n',[]);
 exit;
end;
pDesc:= @SpbInfo.Group_Desc;
for i:= 0 to (db_count-1) do
begin
 pDesc^:= GetBlock(Super.BlockDevice,SuperExt2.first_data_block+i+1,Super.BlockSize);
 if pDesc=nil then
 begin
  WriteConsole('EXT2Fs: Error reading Block Descriptors\n',[]);
  ToroFreeMem(SpbInfo);
  PutBlock(Super.BlockDevice,bh);
  exit;
 end;
 pDesc:= PDesc+1;
end;
// The Filesystem was mounted fine
Super.SbInfo:= SpbInfo;
// loading inode root
Super.InodeROOT:= GetInode(2);
result:= Super;
{$IFDEF DebugExt2FS}
 DebugTrace('Ext2FS: Ext2 Super Block Mounted , Information:',0,0,0);
 DebugTrace('Logic Block Size: %d',0,SpbInfo.log_block_size,0);
 DebugTrace('Inodes per Block: %d',0,SpbInfo.inodes_per_block,0);
 DebugTrace('Inodes Count: %d',0,SpbInfo.inodes_count,0);
 DebugTrace('Block Counts: %d',0,SpbInfo.blocks_count,0);
{$ENDIF}
end; 
 
//
// Ext2ReadInode : 
// Read Inode from Ext2 Filesystem
//
procedure Ext2ReadInode(Inode: PInode);
var
 block_group,group_desc,desc,offset,block,i: longint;
 SbInfo: P_Ext2_sb_info;
 bh: PBufferHead;
 gdp: P_ext2_group_desc;
 raw_inode: P_Ext2_Inode;
 InoInfo: ^ext2_inode_info;
begin
SbInfo:= Inode.Sb.SbInfo;
Inode.dirty:= true;
// Invalid inode number!
if (Inode.ino<>2) and(inode.ino<11) and
 (inode.ino > SbInfo.inodes_count) then
 exit;
block_group:= (Inode.ino-1) div (SbInfo.inodes_per_group);
// Invalid group!
if block_group >= SbInfo.groups_count then
 exit;
group_desc:= block_group div SbInfo.desc_per_block;
desc:= block_group and (SbInfo.desc_per_block -1);
bh:= SbInfo.group_desc+group_desc;
// Error in Read operations
If bh=nil then
 exit;
gdp:= bh.data;
// Offset in the  block
offset:= (Inode.ino -1) mod SbInfo.inodes_per_block * sizeof(ext2_inode);
// block where is the inode
block:= gdp^[desc].inode_table + (((inode.ino-1) mod SbInfo.inodes_per_group * sizeof(ext2_inode))
 shr (SbInfo.log_block_size +10));
bh:= GetBlock(Inode.Sb.BlockDevice,Block,Inode.Sb.BlockSize);
// error when was readed the inode
if bh=nil then
 exit;
raw_inode:= pointer(bh.data + offset);
// Block and Char Devices are not supported
If (raw_inode.mode and $4000 <> $4000) and (raw_inode.mode and $8000 <> $8000) then
begin
 PutBlock(Inode.Sb.BlockDevice,bh);
 {$IFDEF DebugExt2FS}
  DebugTrace('Ext2FS: Inode mode not supported , Inode: %d',0,Inode.ino,0);
 {$ENDIF}
 exit;
end;
Inode.InoInfo:= ToroGetMem(sizeof(ext2_inode_info));
// Not more memory?
if Inode.InoInfo=nil then
begin
 PutBlock(Inode.Sb.BlockDevice,bh);
 exit;
end;
InoInfo:= Inode.InoInfo;
InoInfo.block_group:= block_group;
Inode.dirty:= false;
Inode.atime:= Raw_Inode.atime;
Inode.ctime:= raw_Inode.ctime;
Inode.dtime:= raw_Inode.dtime;
Inode.mtime:= raw_Inode.atime;
Inode.size := raw_Inode.size;
// only direcotories and Regular files
if raw_inode.mode and $4000 = $4000 then
 Inode.mode:= INODE_DIR
else Inode.mode:= INODE_REG;
// loading direct and indirect blocks
for i:= 1 to 15 do
begin
 InoInfo.data[i]:= raw_inode.block[i];
end;
// return the block to the cache
PutBlock(Inode.Sb.BlockDevice,bh);
{$IFDEF DebugExt2FS}
 DebugTrace('Ext2FS: Inode %d ,Readed Ok',0,Inode.ino,0);
{$ENDIF}
end;

// Look for Inode name in Directory Inode  and return his inode.
// Only read from Directs blocks
function Ext2LookUpInode(Ino: PInode; const Name: string): PInode;
var
 i,j:longint;
 InoInfo: ^ext2_inode_info;
 bh : PBufferHead;
 ofs: longint;
 entry: P_Ext2_Dir_Entry;
label _next;
begin
InoInfo:= Ino.InoInfo;
result:= nil;

for i:= 1 to 12 do 
begin
 if InoInfo.data[i] <> 0 then
 begin
  bh:= GetBlock(Ino.Sb.BlockDevice,InoInfo.data[i],Ino.Sb.BlockSize);
  // error in read operations
  if bh= nil then
   exit;
  ofs:= 0;
  while (ofs < Ino.Sb.BlockSize) do
  begin
  _next:
   entry:= bh.data+ofs;
   ofs := ofs+entry.rec_len;
   // some size?
   if entry.name_len = Length(name) then
   begin
    for j:= 0 to (entry.name_len-1) do
     if entry.name[j] <> name[j+1] then
	  goto _next;
    // is the inode!
	result:= GetInode(entry.inode);
	{$IFDEF DebugFilesystem}
	 DebugTrace('Ext2LookUpInode: Inode found',0,0,0);
	{$ENDIF}
	PutBlock(Ino.Sb.BlockDevice,bh);
    exit
   end;
  end;
 end;
end;
{$IFDEF DebugFilesystem}
 DebugTrace('Ext2LookUpInode: Inode not found',0,0,0);
{$ENDIF}
end;

type
  TLongIntArray = array[0..0] of LongInt;
  PLongIntArray = ^TLongIntArray;


// Return a real block in inode structure , only for direct and indirect simple blocks
function Get_Real_Block(block: longint;Inode: PInode):longint;
var
  InoInfo: ^ext2_inode_info;
  tmp_block : longint;
  buffer: PLongIntArray;
  bh: PBufferHead;
begin
InoInfo:= Inode.InoInfo;
// directs blocks
if (block <= 12) then
 result:= InoInfo.data[block]
else if block <= (12 + Inode.Sb.BlockSize div 4) then
begin
 tmp_block:= InoInfo.data[13];
 bh:= GetBlock(Inode.Sb.BlockDevice,tmp_block,Inode.Sb.BlockSize);
 // error in read operations
 if bh=nil then
 begin
  result:=0;
  exit;
 end;
 buffer:= bh.data;
 result:= buffer^[(block-12)-1]
 // More Blocks are not supported
 end else
 result:=0;
end;
 
//
// Ext2ReadFile: 
// Read Regular File from Ext2 Filesystem , support up to 4MB per file , usign 4096 bytes physic blocks.
//
function Ext2ReadFile(FileDesc: PFileRegular;count: longint;Buffer: pointer): longint;
var 
 i,blocksize:longint;
 nb_block,start_block,real_block,initoff,len: longint;
// file_ofs: LongInt;
 bh : PBufferHead;
begin

if (FileDesc.filepos + count > FileDesc.Inode.size) then
 count:= FileDesc.Inode.size - FileDesc.filepos;
 
blocksize:= Filedesc.Inode.Sb.Blocksize;
nb_block:= count div blocksize;
initoff := FileDesc.filepos mod Blocksize;
start_block:= FileDesc.filepos div blocksize+1;

if (count mod blocksize) <> 0 then
  nb_block:= nb_block +1;

//file_ofs:= FileDesc.filepos;
len := count;

// reading
for i:= start_block to (start_block+nb_block-1) do
begin
 real_block:= Get_Real_Block(i,FileDesc.Inode);
 bh:= GetBlock(FileDesc.Inode.Sb.BlockDevice,real_block,BlockSize);
 // Hardware error
 if bh=nil then
  break;
 // count exced a one block
 If len>blocksize then
 begin
  move(PChar(bh.data+initoff)^, PChar(buffer)^, blocksize-initoff);
  FileDesc.filepos:= FileDesc.filepos + Blocksize - initoff;
  initoff := 0;
  buffer := buffer + Blocksize - initoff;
  len := len - Blocksize + initoff;
 end else
 begin
  move(PChar(bh.data+initoff)^, PChar(buffer)^, len);
  initoff := 0 ;
  FileDesc.filepos:= FileDesc.filepos + len;
  len := 0 ;
 end;
end;
result:= count - len;
end;

//
// Ext2Init : 
// Initialization of Ext2 Filesystem
//

initialization
WriteConsole('Ext2 VFS Driver ... /VOk!/n\n',[]);
Ext2Driver.name:= 'ext2';
Ext2Driver.ReadSuper:= @Ext2ReadSuper;
Ext2Driver.CreateInode:= nil;
Ext2Driver.ReadInode:= @Ext2ReadInode;
Ext2Driver.LookUpInode:= @Ext2LookUpInode;
Ext2Driver.ReadFile := @Ext2ReadFile;
Ext2Driver.WriteFile := nil;
RegisterFilesystem(@Ext2Driver);


end.
