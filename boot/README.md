# Compiling Toro's Bootloaders

## Introducction
This README explains how to compile the bootloaders for Toro. There are three ways to boot up:
* Baremetal
* Multiboot
* PVH Kernel

The first method is the classical way to boot up in which the first 512-bytes of disk store the bootloader. The second method uses the possibility to boot up multiboot kernels in QEMU. The third method compiles the kernel as a PVH kernel. In particular, the third methodallows Toro to boot on the microvm machine. 

## Baremetal
The bootloader for baremetal is in x86_64.s. The binary must be located in the first 512-bytes of the disk. The bootloader loads long-mode and jumps to kernel entry point.

`nasm -o boot.bin -fbin x86_64.s`

## Multiboot
This bootloader allows Toro to boot as a multiboot kernel. The bootloader first loads protect-mode and then jumps to long-mode.  

`nasm -felf32 multiboot.s`
`nasm -felf64 jump64.s`

## PVH Kernel 
This bootloader is based on the notion of PVH kernel in which the generated ELF64 has a special header, e.g., ELFNOTE, that points to the entry of the kernel. In this case, the bootloader is compiled into prt0.o which is linked automatically by FPC. 

`nasm -felf64 pvhbootloader.asm -o prt0.o`
