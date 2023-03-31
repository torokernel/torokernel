# use -M maca to not allow qemu run
../../examples/CloudIt.sh TestPerCPUAlign "-dShutdownWhenFinished -dEnableDebug" "-M maca"
sudo ~/qemuforvmm/build/x86_64-softmmu/qemu-system-x86_64 -nographic -enable-kvm -device virtio-serial-device,id=virtio-serial0 -chardev file,path=./testpercpualign.report,id=charconsole0 -device virtconsole,chardev=charconsole0,id=console0 -M microvm,pic=off,pit=off,rtc=off -no-reboot -cpu host -smp 1 -m 64 -d guest_errors -D qemu.log -global virtio-mmio.force-legacy=false -no-acpi -kernel TestPerCPUAlign
if grep -q FAILED "./testpercpualign.report"; then
  cat ./testpercpualign.report
  exit 1
fi
