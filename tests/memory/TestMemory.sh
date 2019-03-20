../../builder/BuildMultibootKernel.sh TestMemory "-dShutdownWhenFinished"
kvm -m 256 -smp 1 -nographic -monitor /dev/null -kernel TestMemory.bin -serial file:testmemory.report -device isa-debug-exit,iobase=0xf4,iosize=0x04
if grep -q FAILED "./testmemory.report"; then
  exit 1
fi
