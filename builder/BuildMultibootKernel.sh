fpc -s -TLinux $2 -O2 $1.pas -Fu../../rtl/ -Fu../../rtl/drivers -MObjfpc
ld -S -nostdlib -nodefaultlibs -T $1.link  -o kernel64.elf64
readelf -SW "kernel64.elf64" | python ../../builder/getsection.py 0x440000 kernel64.elf64 kernel64.section
objcopy --add-section .KERNEL64="kernel64.section" --set-section-flag .KERNEL64=alloc,data,load,contents ../../builder/multiboot.o kernel64.o
readelf -sW "kernel64.elf64" | python ../../builder/getsymbols.py "start64"  kernel64.symbols
ld -melf_i386 -T ../../builder/link_start64.ld -T kernel64.symbols kernel64.o -o $1.bin 
