rm ../../rtl/*.ppu
rm ../../rtl/*.o
../../builder/BuildMultibootKernel.sh TestFilesystem
kvm -m 256 -smp 1 -nographic -vnc :0 -monitor /dev/null -kernel TestFilesystem.bin -serial file:testfilesystem.report -drive file=fat:rw:testfiles,if=none,id=drive-virtio-disk0 -device virtio-blk-pci,drive=drive-virtio-disk0,addr=06 -device isa-debug-exit,iobase=0xf4,iosize=0x04
