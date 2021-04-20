# use -M maca to not allow qemu run
../../examples/CloudIt.sh TestProcess "-dShutdownWhenFinished -dEnableDebug" "-M maca"
sudo ~/qemuforvmm/build/x86_64-softmmu/qemu-system-x86_64 -nographic -enable-kvm -device virtio-serial-device,id=virtio-serial0 -chardev file,path=./testprocess.report,id=charconsole0 -device virtconsole,chardev=charconsole0,id=console0 -M microvm,pic=off,pit=off,rtc=off -no-reboot -cpu host -smp 2 -m 256 -d guest_errors -D qemu.log -global virtio-mmio.force-legacy=false -no-acpi -kernel TestProcess
if grep -q FAILED "./testprocess.report"; then
  cat ./testprocess.report
  exit 1
fi
