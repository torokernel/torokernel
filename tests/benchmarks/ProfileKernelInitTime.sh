# guest memory in MB
mem=256
# time on qemu-kvm in ms
test1=180
../../examples/CloudIt.sh TestBootTime "-dShutdownWhenFinished" "-M maca"
starttime=$(($(date +%s%N)/1000000))
sudo ~/qemuforvmm/build/x86_64-softmmu/qemu-system-x86_64 -nographic -no-acpi -enable-kvm -M microvm,pic=off,pit=off,rtc=off -cpu host -kernel TestBootTime -m $mem -no-reboot
endtime=$(($(date +%s%N)/1000000))
test1_r=$((endtime-starttime))
res=0
if [ "$test1_r" -gt "$test1" ]
then
  echo "TestKernelInitTime: FAILED"
  res=1
else
  echo "TestKernelInitTime: PASSED"
fi
exit $res
