echo Converting %1.img to %1.vhdx
Import-Module 'C:\Program Files\Microsoft Virtual Machine Converter\MvmcCmdlet.psd1'
qemu-img convert -f raw -O vmdk %1.img %1.vmdk
ConvertTo-MvmcVirtualHardDisk -SourceLiteralPath %1.vmdk -VhdType DynamicHardDisk -VhdFormat vhdx -destination .
