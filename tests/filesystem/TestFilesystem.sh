rm ../../rtl/*.ppu
rm ../../rtl/*.o
../../builder/BuildMultibootKernel.sh TestFilesystem "-dShutdownWhenFinished"
kvm -m 256 -smp 1 -nographic -monitor /dev/null -kernel TestFilesystem.bin -serial file:testfilesystem.report -drive file=fat:rw:testfiles,if=none,id=drive-virtio-disk0 -device virtio-blk-pci,drive=drive-virtio-disk0,addr=06 -device isa-debug-exit,iobase=0xf4,iosize=0x04
if grep -q FAILED "./testfilesystem.report"; then
  exit 1
fi
