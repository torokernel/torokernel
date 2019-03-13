# memory for guest in mb
mem=256
# time on qemu-kvm in ms
test1=1100
# time on qemu-kvm with qboot in ms
test2=780
rm ../../rtl/Kernel.ppu
rm ../../rtl/Kernel.o
../../builder/BuildMultibootKernel.sh TestBootTime "-dProfileKernelInit"
starttime=$(($(date +%s%N)/1000000))
kvm -nographic -kernel TestBootTime.bin -m $mem -device isa-debug-exit,iobase=0xf4,iosize=0x04
endtime=$(($(date +%s%N)/1000000))
test1_r=$((endtime-starttime))
if [ "$test1_r" -gt "$test1" ]
then
  echo "TestKernelInitTime: FAILED"
else
  echo "TestKernelInitTime: PASSED"
fi
starttime=$(($(date +%s%N)/1000000))
kvm -bios ../../builder/bios.bin -nographic -kernel TestBootTime.bin -m $mem -device isa-debug-exit,iobase=0xf4,iosize=0x04
endtime=$(($(date +%s%N)/1000000))
test2_r=$((endtime-starttime))
if [ "$test2_r" -gt "$test2" ]
then
  echo "TestKernelInitTime: Qboot, FAILED"
else
  echo "TestKernelInitTime: Qboot, PASSED"
fi
