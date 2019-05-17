//
// Fat.pas
//
// This unit contains the driver for fat16. It is meant to work with the vfat interface
// that qemu provides.
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
Unit Fat;

interface

{$I ..\Toro.inc}

//{$DEFINE DebugFatFS}

uses
  {$IFDEF EnableDebug} Debug, {$ENDIF}
  Console, Arch, FileSystem, Process, Memory;

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
    RootDirStart: LongInt;
    RootDirEnd: Longint;
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
  pfat, tmpfat : ^Byte;
begin
  Result := False;
  sb_fat := sb.SbInfo;
  pfat := ToroGetMem(sb_fat^.pbpb^.bpb_fatsz16 * sb_fat^.pbpb^.bpb_bytspersec);
  Panic ( pfat = nil, 'FatLoadTable: out of memory', []);
  tmpfat := pfat;
  for j := 1 to (1 + sb_fat^.pbpb^.bpb_fatsz16 - 1) do
  begin
   bh := GetBlock(sb.BlockDevice, j, sb_fat^.pbpb^.bpb_bytspersec);
   if bh = nil then
   begin
     WriteConsoleF('FatLoadTable: Error when loading Fat\n',[]);
     Exit;
   end;
   Move(bh^.data^, pfat^, sb_fat^.pbpb^.bpb_bytspersec);
   Inc(pfat, sb_fat^.pbpb^.bpb_bytspersec);
  end;
  sb_fat^.pfat := tmpfat;
  Result := True;
end;

function FatReadSuper (Super: PSuperBlock): PSuperBlock;
var
  bh: PBufferHead;
  pfatboot: pfat_boot_sector;
  pfat: psb_fat ;
begin
  Result := nil;
  // do not return block 0
  bh := GetBlock (Super.BlockDevice, 0, 512);
  pfatboot := bh.data;
  // look for FAT16 string
  if (pfatboot.BS_FilSysType[1] = 'F') and (pfatboot.BS_FilSysType[5] = '6') then
  begin
    pfat := ToroGetMem(sizeof(super_fat));
    Panic(pfat = nil, 'FatReadSuper: out of memory', []);
    pfat.InodesQueue:= nil;
    pfat.InodesQueueTail:= nil;
    pfat.pbpb := pfatboot;
    Super.SbInfo := pfat;
    Super.BlockSize := pfat.pbpb.BPB_BytsPerSec;
    pfat.RootDirStart := ((pfat.pbpb.BPB_FATSz16 *2) + pfat.pbpb.BPB_RsvdSecCnt);
    pfat.RootDirEnd :=  ((pfat.pbpb.BPB_FATSz16 *2) + pfat.pbpb.BPB_RsvdSecCnt + (pfat.pbpb.BPB_RootEntCnt * 32) div pfat.pbpb.BPB_BytsPerSec);
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
  Result := Super;
end;

function UnicodeToUnix (longname: pvfatdirectory_entry; Dest: Pchar; start: LongInt): LongInt;
var
  count: dword ;
begin
  Result := start;
  for count := 1 downto 0 do
  begin
    if (longname^.name3[(count*2)+1] = #0) or (longname^.name3[(count*2)+1] = #$ff) then
      continue;
    Dest[Result] :=  longname^.name3[(count*2)+1];
    Inc(Result);
  end;
  for count := 5 downto 0 do
  begin
    if (longname^.name2[(count*2)+1] = #0) or (longname^.name2[(count*2)+1] = #$ff) then
      continue;
    Dest[Result] := longname^.name2[(count*2)+1] ;
    Inc(Result);
  end;
  for count := 4 downto 0 do
  begin
    if (longname^.name1[(count*2)+1] = #0) or (longname^.name1[(count*2)+1] = #$ff) then
      continue;
    Dest[Result] := longname^.name1[(count*2)+1] ;
    Inc(Result);
  end;
end;

procedure UnixName (fatname: pchar; Dest: Pchar);
var
  tmp: array[0..11] of char;
  count, ret: dword;
begin
  FillByte (tmp, 11, 32);
  for count := 0 to 7 do
  begin
    if fatname[count] = #32 then
      break;
    tmp[count] := fatname[count];
  end;
  Inc(count);
  if fatname[8] = #32 then
  begin
    Move(tmp, Dest^, count);
    Dest[count] := #0;
    Exit;
  end;
  tmp[count] := #46 ;
  Inc(count);
  for ret := 8 to 11 do
  begin
    if fatname[ret]= #32 then
      break
    else
      tmp[count] := fatname[ret];
    Inc(count);
  end;
  Move(tmp, Dest^, count);
  Dest[count] := #0;
end;

function AllocInodeFat(sb: psb_fat; entry: pdirectory_entry): pfat_inode_info;
var
  tmp : pfat_inode_info;
begin
  tmp := ToroGetMem(sizeof(fat_inode_info));
  if tmp = nil then
  begin
   Result := nil;
   Exit;
  end;
  tmp.dir_entry := entry ;
  tmp.ino := entry.FATEntry ;
  tmp.sb := sb ;
  tmp.NextInode := nil;
  if sb.InodesQueue = nil then
    sb.InodesQueue := tmp;
  sb.InodesQueueTail.NextInode := tmp;
  sb.InodesQueueTail := tmp;
  Result := tmp;
end;


function StrCmpforFat(buff, name: pchar; len: Longint): Boolean;
var
 tmp: pchar;
 j: Longint;
begin
  Result := True;
  if StrLen(buff) <> StrLen(name) then
  begin
    Result:= False;
    Exit;
  end;
  tmp := buff + len -1;
  for j:= 0 to len-1 do
  begin
    if name^ <> tmp^ then
    begin
      Result := False;
      Exit;
    end;
    Inc(name);
    Dec(tmp);
  end;
end;

function GetNextCluster (pfat: psb_fat; Cluster: DWORD): Word ;
var
  lsb, msb: byte;
  ret: word;
  offset: dword;
begin
  offset := Cluster * sizeof(Word);
  lsb := PByte(Pointer(pfat.pfat) + offset)^;
  msb := PByte(Pointer(pfat.pfat) + offset + 1)^;
  ret := (msb shl 8) or lsb;
  if ret >= $FFF8 then
    Result := LAST_SECTOR_FAT
  else
    Result := ret;
end;

function FindDirinDir(FatInode: pfat_inode_info; Ino: PInode; name: pchar; out res: pdirectory_entry): Boolean;
var 
  buff: array[0..254] of char;
  start, j, i: Dword;
  pdir: pdirectory_entry;
  pdirlong: pvfatdirectory_entry;
  ch: Byte;
  pfat:psb_fat;
  NextCluster, Sector: LongInt;
  bh: PBufferHead;
begin
  Result := False;
  res := nil;
  pfat := Ino.SuperBlock.SbInfo;
  nextCluster := FatInode.dir_entry.FATEntry;
  start := 0;
  while nextCluster <> LAST_SECTOR_FAT do
  begin
    Sector := (nextCluster - 2) * pfat.pbpb.BPB_SecPerClus + ((pfat.pbpb.BPB_FATSz16 *2) + pfat.pbpb.BPB_RsvdSecCnt + (pfat.pbpb.BPB_RootEntCnt * 32) div pfat.pbpb.BPB_BytsPerSec);
    for i:= 0 to pfat.pbpb.BPB_SecPerClus-1 do
    begin
      bh := GetBlock(Ino.SuperBlock.BlockDevice, Sector + i, Ino.SuperBlock.BlockSize);
      pdir := Pointer(bh.data);
      while PtrUInt(pdir) < PtrUInt(Pointer(bh.data + bh.size))  do
      begin
        if (pdir.name[1] = #0) or (pdir.name[1] = #$E5)  then
        begin
          Inc(pdir);
          continue;
        end;
        // long entries
        if pdir.attr = $0F then
        begin
          pdirlong := Pointer(pdir);
          while (pdirlong.res <> $41) and (pdirlong.res <> 1) and (PtrUInt(pdirlong) < PtrUInt(Pointer(bh.data + bh.size))-1) do
          begin
            start := UnicodeToUnix (pdirlong, buff, start);
            Inc(pdirlong);
          end;
          if PtrUInt(pdirlong) > PtrUInt(Pointer(bh.data + bh.size))-1 then
          begin
            pdir := Pointer(pdirlong);
            continue;
          end;
          start := UnicodeToUnix (pdirlong, buff, start);
          buff[start] := #0;
          for j:= 0 to (StrLen(@buff)-1) do
          begin
            if (buff[j] >= 'a') or (buff[j] <= 'z') then
            begin
              ch := Byte(buff[j]) xor $20;
              buff[j] := Char(ch);
            end;
          end;
          Inc(pdirlong);
          if PtrUInt(pdirlong) > PtrUInt(Pointer(bh.data + bh.size))-1 then
          begin
            pdir := Pointer(pdirlong);
            continue;
          end;
          if (StrLen(@buff) <> 0) and (StrCmpforFat(@buff, name, StrLen(name))) then
          begin
            res := Pointer(pdirlong);
            Result := True;
            Exit;
          end;
          pdir := Pointer(pdirlong);
          start := 0;
        // short entries
        end else
        begin
          if start <> 0 then
          begin
            if (StrLen(@buff) <> 0) and (StrCmpforFat(@buff, name, StrLen(name))) then
            begin
              res := pdir;
              Result := True;
              Exit;
            end;
            start := 0
          end else
          begin
            UnixName (@pdir.name, @buff);
            if (StrLen(@buff) <> 0) and StrCmp(@buff, name, StrLen(name)) then
            begin
              res := pdir;
              Result := true;
              Exit;
            end;
          end;
        end;
        Inc(pdir);
      end;
      PutBlock(Ino.SuperBlock.BlockDevice, bh);
    end;
    nextCluster := GetNextCluster(pfat, nextCluster);
    end;
end;

function FindDirinRoot(Ino: PInode; name: pchar; out res: pdirectory_entry): Boolean;
var
  buff: array[0..254] of char;
  start, j, blk: Dword;
  pfat: psb_fat;
  pdir: pdirectory_entry;
  pdirlong: pvfatdirectory_entry;
  ch: Byte;
  bh: PBufferHead;
begin
  Result := False;
  res := nil;
  pfat := Ino.SuperBlock.SbInfo;
  start := 0;
  for blk := pfat.RootDirStart to pfat.RootDirEnd do
  begin
    bh := GetBlock (Ino.SuperBlock.BlockDevice, blk, Ino.SuperBlock.BlockSize);
    pdir := Pointer(bh.data);
    while PtrUInt(pdir) < PtrUInt(Pointer(bh.data + bh.size))  do
    begin
      if (pdir.name[1] = #0) or (pdir.name[1] = #$E5)  then
      begin
        Inc(pdir);
        continue;
      end;
      // long entries
      if pdir.attr = $0F then
      begin
        pdirlong := Pointer(pdir);
        while (pdirlong.res <> $41) and (pdirlong.res <> 1) and (PtrUInt(pdirlong) < PtrUInt(Pointer(bh.data + bh.size))-1) do
        begin
          start := UnicodeToUnix (pdirlong, buff, start);
          Inc(pdirlong);
        end;
        if PtrUInt(pdirlong) > PtrUInt(Pointer(bh.data + bh.size))-1 then
        begin
          pdir := Pointer(pdirlong);
          continue;
        end;
        start := UnicodeToUnix (pdirlong, buff, start);
        buff[start] := #0;
        for j:= 0 to (StrLen(@buff)-1) do
        begin
          if (buff[j] >= 'a') or (buff[j] <= 'z') then
          begin
            ch := Byte(buff[j]) xor $20;
            buff[j] := Char(ch);
          end;
        end;
        Inc(pdirlong);
        // not sure how to handle this
        if PtrUInt(pdirlong) > PtrUInt(Pointer(bh.data + bh.size))-1 then
        begin
          pdir := Pointer(pdirlong);
          continue;
        end;
        if (StrLen(@buff) <> 0) and (StrCmpforFat(@buff, name, StrLen(name))) then
        begin
          res := Pointer(pdirlong);
          Result := True;
          Exit;
        end;
        pdir := Pointer(pdirlong);
        start := 0;
      // short entries
      end else
      begin
        if start <> 0 then
        begin
          if (StrLen(@buff) <> 0) and (StrCmpforFat(@buff, name, StrLen(name))) then
          begin
            res := pdir;
            Result := True;
            Exit;
          end;
          start := 0
        end else
        begin
          UnixName (@pdir.name, @buff);
          if (StrLen(@buff) <> 0) and StrCmp(@buff, name, StrLen(name)) then
          begin
            res := pdir;
            Result := true;
            Exit;
          end;
        end;
      end;
      Inc(pdir);
    end;
  end;
end;

function FatLookUpInode(Ino: PInode; Name: PXChar): PInode;
var
  j: LongInt;
  ch: Byte;
  NameFat: Pchar;
  pdir:  pdirectory_entry;
  pfat: psb_fat;
  FatInode: pfat_inode_info;
begin
  Result := nil;
  NameFat := ToroGetMem(Length(Name)+1);
  if NameFat = nil then
  begin
    Exit;
  end;
  pfat := Ino.SuperBlock.SbInfo;
  for j := 0 to (Length(Name) - 1) do
  begin
   if (Name[j] >= 'a') or (Name[j] <= 'z') then
   begin
     ch := Byte(Name[j]) xor $20;
     NameFat[j] := Char(ch);
   end else
   begin
     NameFat[j] := Name[j];
   end;
  end;
  NameFat[Length(Name)] := #0;
  if Ino.ino = 1 then
  begin
    if FindDirinRoot (Ino, NameFat, pdir) then
    begin
      AllocInodeFat(pfat, pdir);
      Result := GetInode(pdir.FATEntry);
    end;
    ToroFreeMem(NameFat);
    Exit;
  end else
  begin
    FatInode := pfat.InodesQueue;
    while (FatInode <> nil) do
    begin
      if FatInode.ino = Ino.ino then
      begin
        if FindDirinDir(FatInode, Ino, NameFat, pdir) then
        begin
          AllocInodeFat(pfat, pdir);
          Result := GetInode(pdir.FATEntry);
        end;
        ToroFreeMem(NameFat);
        Exit;
      end;
      FatInode := FatInode.NextInode;
    end;
    ToroFreeMem(NameFat);
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
  while FatInode <> nil do
  begin
    if FatInode.ino = Inode.ino then
    begin
      Inode.InoInfo:= FatInode;
      Inode.Size := FatInode.dir_entry.size;
      if FatInode.dir_entry.attr and FAT_DIR = FAT_DIR then
        Inode.Mode := INODE_DIR
      else if FatInode.dir_entry.attr and FAT_FILE = FAT_FILE then
        Inode.Mode:= INODE_REG;
      // TODO: add time
      Inode.ATime := 0;
      Inode.MTime := 0;
      Inode.CTime := 0;
      Inode.Dirty:= false;
      Exit;
    end;
    FatInode := FatInode.NextInode;
  end;
end;


function FatReadFile(FileDesc: PFileRegular; Count: LongInt; Buffer: Pointer): longint;
var
  bh: PBufferHead;
  Cnt: DWORD;
  initblk, initoff, startblk: DWORD;
  j: LongInt;
  nextCluster, Sector: DWORD;
  pfat: psb_fat;
  tmp: pfat_inode_info;
begin
  if FileDesc.FilePos + Count > FileDesc.Inode.Size then
  begin
    {$IFDEF DebugFat} WriteDebug('FatReadFile: reading after end, pos:%d, size:%d\n', [FileDesc.FilePos, FileDesc.Inode.Size ]); {$ENDIF}
    Count:= FileDesc.Inode.Size - FileDesc.FilePos;
  end;
  pfat := FileDesc.Inode.SuperBlock.SbInfo;
  tmp := FileDesc.Inode.InoInfo;
  initblk := FileDesc.FilePos div (FileDesc.Inode.SuperBlock.BlockSize * pfat.pbpb.BPB_SecPerClus);
  initoff := FileDesc.FilePos mod FileDesc.Inode.SuperBlock.BlockSize;
  startblk := (FileDesc.FilePos mod (FileDesc.Inode.SuperBlock.BlockSize * pfat.pbpb.BPB_SecPerClus)) div FileDesc.Inode.SuperBlock.BlockSize;
  nextCluster := tmp.dir_entry.FATEntry;
  If initblk = 0 then
   Sector := (nextCluster - 2) * pfat.pbpb.BPB_SecPerClus + ((pfat.pbpb.BPB_FATSz16 *2) + pfat.pbpb.BPB_RsvdSecCnt + (pfat.pbpb.BPB_RootEntCnt * 32) div pfat.pbpb.BPB_BytsPerSec)
  else
  begin
    for j := 0 to initblk do
    begin
      nextCluster := GetNextCluster(FileDesc.Inode.SuperBlock.SbInfo, nextCluster);
      if Sector = LAST_SECTOR_FAT then
      begin
        Result:= 0;
        Exit;
      end;
    end;
    Sector := (nextCluster - 2) * pfat.pbpb.BPB_SecPerClus + ((pfat.pbpb.BPB_FATSz16 *2) + pfat.pbpb.BPB_RsvdSecCnt + (pfat.pbpb.BPB_RootEntCnt * 32) div pfat.pbpb.BPB_BytsPerSec)
  end;
  cnt := Count ;
  repeat
    // read a whole cluster
    for j:= startblk to pfat.pbpb.BPB_SecPerClus-1 do
    begin
      bh := GetBlock(FileDesc.Inode.SuperBlock.BlockDevice, Sector + j, FileDesc.Inode.SuperBlock.BlockSize);
      {$IFDEF DebugFat} WriteDebug('FatReadFile: nextSector: %d, ClusterSize: %d, Count: %d, startblk: %d, initoff: %d\n',[Sector, FileDesc.Inode.SuperBlock.BlockSize*pfat.pbpb.BPB_SecPerClus, cnt, startblk, initoff]); {$ENDIF}
      if bh = nil then
      begin
        Result := Count - cnt;
        Exit;
      end;
      if cnt > (FileDesc.Inode.SuperBlock.BlockSize) then
      begin
        Move (PByte(bh.data+initoff)^, Pbyte(Buffer)^, FileDesc.Inode.SuperBlock.BlockSize);
        Inc(FileDesc.FilePos, FileDesc.Inode.SuperBlock.BlockSize);
        initoff := 0;
        startblk := 0;
        Dec(cnt, FileDesc.Inode.SuperBlock.BlockSize);
        Inc(Buffer, FileDesc.Inode.SuperBlock.BlockSize);
        PutBlock(FileDesc.Inode.SuperBlock.BlockDevice, bh);
      end else
      begin
        Move(PByte(bh.data+initoff)^, Pbyte(Buffer)^, cnt);
        initoff := 0;
        startblk := 0;
        Inc(FileDesc.FilePos, cnt);
        cnt := 0 ;
        PutBlock(FileDesc.Inode.SuperBlock.BlockDevice, bh);
        Break;
      end;
    end;
    nextCluster := GetNextCluster(FileDesc.Inode.SuperBlock.SbInfo, nextCluster);
    if nextCluster = LAST_SECTOR_FAT then
      break;
    Sector := (nextCluster - 2) * pfat.pbpb.BPB_SecPerClus + ((pfat.pbpb.BPB_FATSz16 *2) + pfat.pbpb.BPB_RsvdSecCnt + (pfat.pbpb.BPB_RootEntCnt * 32) div pfat.pbpb.BPB_BytsPerSec);
  until cnt = 0;
  Result := Count - cnt;
  {$IFDEF DebugFat} WriteDebug('FatReadFile: Result: %d\n',[Result]); {$ENDIF}
end;

initialization
  WriteConsoleF('Fat driver ... /Vinstalled/n\n',[]);
  FatDriver.name := 'fat';
  FatDriver.ReadSuper := @FatReadSuper;
  FatDriver.ReadInode := @FatReadInode;
  FatDriver.LookUpInode := @FatLookUpInode;
  FatDriver.ReadFile := @FatReadFile;
  FatDriver.OpenFile := nil;
  FatDriver.CloseFile := nil;
  RegisterFilesystem(@FatDriver);
end.
