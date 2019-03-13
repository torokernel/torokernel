rm ../../rtl/*.ppu
rm ../../rtl/*.o
../../builder/BuildMultibootKernel.sh TestProcess
kvm -m 256 -smp 2 -nographic -vnc :0 -monitor /dev/null -kernel TestProcess.bin -serial file:testprocess.report -device isa-debug-exit,iobase=0xf4,iosize=0x04
