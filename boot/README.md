# Compiling Toro's Bootloaders
This bootloader is based on the notion of PVH kernel in which the generated ELF64 has a special header, e.g., ELFNOTE, that points to the entry of the kernel. In this case, the bootloader is compiled into prt0.o which is linked automatically by FPC. 

`nasm -felf64 pvhbootloader.asm -o prt0.o`
