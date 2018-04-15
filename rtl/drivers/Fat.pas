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

const

  FAT_DIR = $10;
  FAT_FILE = $20;

  LAST_SECTOR_FAT = $ffff;

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

  pfat_inode_info = ^fat_inode_info;
  psb_fat = ^super_fat;

  super_fat = record
    tfat : dword ;
    pfat : ^byte ;
    pbpb : pfat_boot_sector ;
    InodesQueue: pfat_inode_info;
    InodesQueueTail: pfat_inode_info;
  end;


  pdirectory_entry = ^directory_entry ;

  directory_entry = packed record
    name : array[1..11] of char ;
    attr : byte ;
    res : array[1..10] of byte ;
    mtime : word ;
    mdate : word;
    FATEntry  :word ;
    size : dword ;
  end;


  fat_inode_info = record
    dir_entry : pdirectory_entry ;
    bh : PBufferHead ;
    ino : dword ;
    sb : psb_fat ;
    NextInode: pfat_inode_info;
  end;

  pvfatdirectory_entry = ^vfatdirectory_entry  ;

  vfatdirectory_entry = record
    res : byte ;
    name1 : array[1..10] of char ;
    attr : byte ;
    tpe : byte ;
    check : byte ;
    name2 :array [1..12] of char ;
    res1 : word ;
    name3 : array[1..4] of char ;
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
  //WriteConsoleF('FatLoadTable: Fat has been loaded correctly\n',[]);
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
    pfat := ToroGetMem(sizeof(super_fat));
    pfat.InodesQueue:= nil;
    pfat.InodesQueueTail:= nil;
    pfat.pbpb := pfatboot;
    Super.SbInfo:= pfat;
    Super.BlockSize:= pfat.pbpb.BPB_BytsPerSec;
    //WriteConsoleF('FatReadSuper: FAT16 partition found, sectors per fat: %d, reserved: %d\n',[pfat.pbpb.BPB_FATSz16, pfat.pbpb.BPB_RsvdSecCnt]);
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
  Super.InodeROOT:= GetInode(1);
  // we return the bh to cache
  PutBlock(Super.BlockDevice,bh);
  Result := Super;
end;


procedure UnicodeToUnix (longname: pvfatdirectory_entry; Dest: Pchar);
var
  count, i: dword ;
begin
  i:= 0;
  for count := 0 to 4 do
  begin
   if longname^.name1[(count*2)+1] = #0 then
   begin
    Exit
   end
   else
    begin
     Dest[i] := longname^.name1[(count*2)+1] ;
     Inc(i);
    end;
  end;
  for count := 0 to 5 do
  begin
   if longname^.name2[(count*2)+1] = #0 then
   begin
    Exit
   end
   else
    begin
     Dest[i] := longname^.name2[(count*2)+1] ;
     Inc(i);
    end;
  end;
  for count := 0 to 1 do
  begin
   if longname^.name3[(count*2)+1] = #0 then
   begin
    Exit
   end
   else
    begin
     Dest[i] :=  longname^.name3[(count*2)+1] ;
     Inc(i);
    end;
  end;
  Dest[i]:= #0;
end;

procedure UnixName (fatname: pchar; Dest: Pchar);
var tmp : array[0..11] of char ;
    count ,ret: dword ;
label _ext , _exit ;
begin
  FillByte (tmp, 11, 32);
  for count := 0 to 7 do
  begin
   if fatname[count] = #32 then goto _ext ;
   tmp[count] := fatname[count];
  end;
  Inc(count);

_ext :

 if fatname[8] = #32 then goto _exit;

 tmp[count] := #46 ;
 count += 1;

 for ret := 8 to 11 do
 begin
  if fatname[ret]= #32 then break
  else tmp[count] := fatname[ret];
  count += 1;
 end;

_exit :

 Move(tmp, Dest^, count);
 Dest[count] := #0;
end;


function AllocInodeFat(sb: psb_fat; entry: pdirectory_entry; bh: PBufferHead): pfat_inode_info;
var
  tmp : pfat_inode_info;
begin
  tmp := ToroGetMem(sizeof(pfat_inode_info));
  if tmp = nil then
  begin
   Result := nil;
   Exit;
  end;
  tmp.dir_entry := entry ;
  tmp.bh := bh ;
  tmp.ino := entry.FATEntry ;
  tmp.sb := sb ;
  // enqueue the inode
  tmp.NextInode := nil;
  if sb.InodesQueue = nil then
   sb.InodesQueue := tmp;
  sb.InodesQueueTail.NextInode := tmp;
  sb.InodesQueueTail := tmp;
  Result := tmp;
end;



function FindRootDir (bh: PBufferHead; name: pchar; var res : pdirectory_entry): Boolean;
var count  , cont : dword ;
    pdir : pdirectory_entry ;
    plgdir : pvfatdirectory_entry ;
    buff : array[0..254] of char;
    lgcount : dword ;
    J: LongInt;
    ch: Byte;
begin
  Result := False;
  res := nil ;
  pdir := bh.data;
  count := 1;
  lgcount := 0;
  repeat
    case pdir.name[1] of
    #0 : Exit;
    #$E5 : lgcount := 0 ;
    else
      begin
       // long name entry
       if (pdir^.attr = $0F) and (count <= (512 div sizeof (directory_entry))) then
          lgcount += 1
      else
       begin
        if (lgcount > 0 ) then
         begin
          plgdir := pointer (pdir);
          for cont := 0 to (lgcount-1) do
          begin
           Dec(plgdir);
           // TODO: buff is 255 long
           UnicodeToUnix (plgdir, @buff);
          end;
          // convert buff to upper case
          for j:= 0 to (StrLen(@buff)-1) do
          begin
           if (buff[j] >= 'a') or (buff[j] <= 'z') then
           begin
            ch := Byte(buff[j]) xor $20;
            buff[j] := Char(ch);
           end;
          end;
          buff[StrLen(@buff)] := #0;
          // check and exit
          if (StrLen(@buff) <> 0) and (StrCmp(@buff, name, StrLen(name))) then
          begin
           res := pdir ;
           Result := True;
           Exit;
          end;
         end
          else
           begin
             UnixName (@pdir.name, @buff);
             if (StrLen(@buff) <> 0) and StrCmp(@buff, name, StrLen(name)) then
             begin
              res := pdir ;
              Result := true;
              Exit;
             end;
           end;
        lgcount := 0 ;
       end;
      end;
    end;
    Inc(pdir);
    Inc(count);
  until (count > (512 div sizeof (directory_entry))) ;
end;





function FatLookUpInode(Ino: PInode; const Name: AnsiString): PInode;
var
  j, blk: LongInt;
  ch: Byte;
  NameFat: Pchar;
  bh: PBufferHead;
  pdir:  pdirectory_entry;
  pfat: psb_fat;
begin
  Result := nil;
  NameFat := ToroGetMem(Length(Name)+1);
  pfat := Ino.SuperBlock.SbInfo;
  // conver Name to upper case
  for j:= 1 to Length(Name) do
  begin
   if (Name[j] >= 'a') or (Name[j] <= 'z') then
   begin
     ch := Byte(Name[j]) xor $20;
     NameFat[j-1] := Char(ch);
   end else
   begin
    NameFat[j-1] := Name[j];
   end;
  end;
  NameFat[Length(Name)] := #0;
  // inode root
  if Ino.ino = 1 then
  begin
    // root directory
    for blk := ((pfat.pbpb.BPB_FATSz16 *2) + pfat.pbpb.BPB_RsvdSecCnt) to ((pfat.pbpb.BPB_FATSz16 *2) + pfat.pbpb.BPB_RsvdSecCnt + (pfat.pbpb.BPB_RootEntCnt * 32) div pfat.pbpb.BPB_BytsPerSec) do
    begin
     bh := GetBlock (Ino.SuperBlock.BlockDevice, blk, Ino.SuperBlock.BlockSize);
     if FindRootDir (bh, NameFat, pdir) then
     begin
      AllocInodeFat(pfat, pdir, bh);
      Result := GetInode(pdir.FATEntry);
      PutBlock(Ino.SuperBlock.BlockDevice, bh);
      ToroFreeMem(NameFat);
      Exit;
     end;
     PutBlock(Ino.SuperBlock.BlockDevice, bh);
    end;
    ToroFreeMem(NameFat);
    Exit
  end else
  begin
   WriteConsoleF('FatLookUpInode: otro que root\n',[]);
   while true do;
   Exit;
  end;
end;

procedure FatReadInode(Inode: PInode);
var
  pfat: psb_fat;
  FatInode: pfat_inode_info;
  rootSize: LongInt;
begin
  pfat := Inode.SuperBlock.SbInfo;

  if Inode.ino = 1 then
  begin
    Inode.InoInfo:= nil;
    rootSize := pfat.pbpb.BPB_RootEntCnt * sizeof(directory_entry);
    Inode.Size := rootSize;
    Inode.Mode := INODE_DIR;
    Inode.Count:= 0;
    Exit;
  end;

  pfat := Inode.SuperBlock.SbInfo;
  FatInode := pfat.InodesQueue;

  while (FatInode <> nil) do
  begin
   if FatInode.ino = Inode.ino then
   begin
    Inode.InoInfo:= FatInode;
    Inode.Size := FatInode.dir_entry.size;

    if FatInode.dir_entry.attr and FAT_DIR = FAT_DIR then
      Inode.Mode := INODE_DIR
    else if FatInode.dir_entry.attr and FAT_FILE = FAT_FILE then
      Inode.Mode:= INODE_REG;

    Inode.ATime := 0;
    Inode.MTime := 0;
    Inode.CTime := 0;
    Inode.Dirty:= false;
    Exit;
   end;
   FatInode := FatInode.NextInode;
  end;
end;

// TODO: to check this
function GetFatSector (sb_fat: psb_fat; sector: DWORD): Word ;
var lsb , msb  : byte ;
    offset: dword ;
    ret : word ;
begin
 Sector -= ((sb_fat.pbpb.BPB_FATSz16 *2) + sb_fat.pbpb.BPB_RsvdSecCnt + (sb_fat.pbpb.BPB_RootEntCnt * 32) div sb_fat.pbpb.BPB_BytsPerSec) - 2 ;
 offset := (sector * 3 ) shr 1 ;
 lsb := PByte(Pointer(sb_fat.pfat) + offset)^;
 msb := PByte(Pointer(sb_fat.pfat) + offset + 1)^;
 if (sector mod 2 ) <>  0  then
  ret := ((msb shl 8 ) or lsb ) shr 4
 else
 ret := ((msb shl 8) or lsb ) and $FFF ;
 if (ret = $FFF) then
  Result := LAST_SECTOR_FAT
 else
  Result := ((sb_fat.pbpb.BPB_FATSz16 *2) + sb_fat.pbpb.BPB_RsvdSecCnt + (sb_fat.pbpb.BPB_RootEntCnt * 32) div sb_fat.pbpb.BPB_BytsPerSec) - 2 + ret ;
end;


function FatReadFile(FileDesc: PFileRegular; Count: longint; Buffer: Pointer): longint;
var
  tmp: pfat_inode_info;
  initblk, initoff, nextCluster, nextSector, Cnt: DWORD;
  j: LongInt;
  bh: PBufferHead;
  pfat: psb_fat;
begin
  if FileDesc.FilePos + Count > FileDesc.Inode.Size then
  begin
    {$IFDEF DebugFS} WriteDebug('Ext2ReadFile: reading after end, pos:%d, size:%d\n', [FileDesc.FilePos, FileDesc.Inode.Size ]); {$ENDIF}
    Count:= FileDesc.Inode.Size - FileDesc.FilePos;
  end;

  pfat := FileDesc.Inode.SuperBlock.SbInfo;

  tmp := FileDesc.Inode.InoInfo;
  initblk := FileDesc.FilePos div FileDesc.Inode.SuperBlock.BlockSize;
  initoff := FileDesc.FilePos mod FileDesc.Inode.SuperBlock.BlockSize;
  nextCluster := tmp.dir_entry.FATEntry;

  If initblk = 0 then
   nextSector := (nextCluster - 2) * pfat.pbpb.BPB_SecPerClus + ((pfat.pbpb.BPB_FATSz16 *2) + pfat.pbpb.BPB_RsvdSecCnt + (pfat.pbpb.BPB_RootEntCnt * 32) div pfat.pbpb.BPB_BytsPerSec)
  else
   begin
    for j := nextCluster to (nextCluster + initblk - 1 ) do
    begin
     // TODO: to check this function
     nextSector := GetFatSector(FileDesc.Inode.SuperBlock.SbInfo, j);
     if nextSector = LAST_SECTOR_FAT then
     begin
      Result:= 0;
      Exit;
     end;
    end;
   end;

  cnt := Count ;

  repeat
   bh := GetBlock(FileDesc.Inode.SuperBlock.BlockDevice, nextSector, FileDesc.Inode.SuperBlock.BlockSize);
   if bh = nil then
   begin
    Break;
   end;
   if (cnt > FileDesc.Inode.SuperBlock.BlockSize) then
   begin
    Move (PByte(bh.data+initoff)^, Pbyte(Buffer)^, FileDesc.Inode.SuperBlock.BlockSize);
    Inc(FileDesc.FilePos, FileDesc.Inode.SuperBlock.BlockSize);
    initoff := 0 ;
    Dec(cnt, FileDesc.Inode.SuperBlock.BlockSize);
    Inc(Buffer, FileDesc.Inode.SuperBlock.BlockSize);
   end else
   begin
    //Move(PByte(bh.data+initoff)^, Pbyte(Buffer)^, cnt);
    //error en el numero de sector!!
      WriteConsoleF('NextSector: %d\n', [nextSector]);
      WriteConsoleF('leyendo initoff: %p\n',[PtrUInt(Pointer(bh.data+initoff))]);
  while true do;
    initoff := 0 ;
    Inc(FileDesc.FilePos, cnt);
    cnt := 0 ;
   end;
   PutBlock(FileDesc.Inode.SuperBlock.BlockDevice, bh);
   nextSector :=  GetFatSector(FileDesc.Inode.SuperBlock.SbInfo,nextSector);
   if nextSector = LAST_SECTOR_FAT then
   begin
    break;
   end;
  until cnt = 0;

  Result := Count - cnt;
end;

initialization
  WriteConsoleF('Fat driver ... /Vinstalled/n\n',[]);
  FatDriver.name := 'fat';
  FatDriver.ReadSuper := @FatReadSuper;
  FatDriver.ReadInode := @FatReadInode;
  FatDriver.LookUpInode := @FatLookUpInode;
  FatDriver.ReadFile := @FatReadFile;
  {Ext2Driver.CreateInode := @Ext2CreateInode;
  Ext2Driver.CreateInodeDir := @Ext2CreateInodeDir;
  Ext2Driver.ReadInode := @Ext2ReadInode;
  Ext2Driver.WriteInode := @Ext2WriteInode;
  Ext2Driver.LookUpInode := @Ext2LookUpInode;
  Ext2Driver.ReadFile := @Ext2ReadFile;
  Ext2Driver.WriteFile := @Ext2WriteFile;}
  RegisterFilesystem(@FatDriver);
end.
