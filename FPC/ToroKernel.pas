{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit ToroKernel;

{$warn 5023 off : no warning about unused units}
interface

uses
  Arch, Debug, Errno, Filesystem, fpintres, Kernel, Libc, Memory, Network, 
  Process, SysUtils, Console, E1000, Ext2, IdeDisk, Ne2000, Pci, 
  LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('ToroKernel', @Register);
end.
