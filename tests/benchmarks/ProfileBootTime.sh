# guest memory in MB
mem=256
# time on qemu-kvm microvm in ms
test1=75
../../examples/CloudIt.sh TestBootTime "-dProfileBootTime" "-M maca"
starttime=$(($(date +%s%N)/1000000))
sudo ~/qemuforvmm/build/x86_64-softmmu/qemu-system-x86_64 -nographic -no-acpi -enable-kvm -M microvm,pic=off,pit=off,rtc=off -cpu host -kernel TestBootTime -m $mem -no-reboot
endtime=$(($(date +%s%N)/1000000))
test1_r=$((endtime-starttime))
res=0
if [ "$test1_r" -gt "$test1" ]
then
  echo "TestBootTime: FAILED"
  res=1
else
  echo "TestBootTime: PASSED"
fi
exit $res
