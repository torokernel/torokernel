../../examples/CloudIt.sh TestFilesystem "-dShutdownWhenFinished -dEnableDebug"
# ./virtiofsd -d --socket-path=/tmp/vhostqemu1 -o source=/root/torokernel/fixfor#408/tests/filesystem/testfiles -o cache=always &
~/qemuforvmm/build/x86_64-softmmu/qemu-system-x86_64 -nographic -enable-kvm -device virtio-serial-device,id=virtio-serial0 -chardev file,path=./testfilesystem.report,id=charconsole0 -device virtconsole,chardev=charconsole0,id=console0 -M microvm,pic=off,pit=off,rtc=off -no-reboot -cpu host -smp 1 -nographic -append virtiofs,FS -m 1G -object memory-backend-file,id=mem,size=1G,mem-path=/dev/shm,share=on -numa node,memdev=mem -chardev socket,id=char0,path=/tmp/vhostqemu1 -device vhost-user-fs-device,queue-size=1024,chardev=char0,tag=FS -d guest_errors -D qemu.log -global virtio-mmio.force-legacy=false -no-acpi -kernel TestFilesystem 
if grep -q FAILED "./testfilesystem.report"; then
  cat ./testfilesystem.report
  exit 1
fi
