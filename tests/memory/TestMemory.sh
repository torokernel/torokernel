rm ../../rtl/*.ppu
rm ../../rtl/drivers/*.ppu
rm ../../rtl/*.o
rm ../../rtl/drivers/*.o
../../builder/BuildMultibootKernel.sh TestMemory "-dShutdownWhenFinished -dEnableDebug"
qemu-system-x86_64 -m 256 -smp 1 -nographic -monitor /dev/null -kernel TestMemory.bin -serial file:testmemory.report -device isa-debug-exit,iobase=0xf4,iosize=0x04
if grep -q FAILED "./testmemory.report"; then
  cat ./testmemory.report
  exit 1
fi
