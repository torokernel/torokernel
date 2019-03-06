../../builder/BuildMultibootKernel.sh TestMemory
kvm -m 256 -smp 1 -no-reboot -nographic -vnc :0 -kernel TestMemory.bin -serial file:testmemory.report -device isa-debug-exit,iobase=0xf4,iosize=0x04
