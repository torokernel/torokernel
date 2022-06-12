# use -M maca to not allow qemu run
../../examples/CloudIt.sh TestNetworking "-dShutdownWhenFinished -dEnableDebug" "-M maca"
# TODO: add client and server mode in append
sudo ~/qemuforvmm/build/x86_64-softmmu/qemu-system-x86_64 -nographic -enable-kvm -device vhost-vsock-device,guest-cid=5 -append virtiovsocket,server -device virtio-serial-device,id=virtio-serial0 -chardev file,path=./testnetworking.report,id=charconsole0 -device virtconsole,chardev=charconsole0,id=console0 -M microvm,pic=off,pit=off,rtc=off -no-reboot -cpu host -smp 1 -m 512 -d guest_errors -D qemu.log -global virtio-mmio.force-legacy=false -no-acpi -kernel TestNetworking
if grep -q FAILED "./testnetworking.report"; then
  cat ./testnetworking.report
  exit 1
fi
