#!/bin/bash
app="StaticWebServer"
appbin="StaticWebServer.bin"
compileropt="-dUseVirtIOFS"
qemuparams="-M pc -cpu host -smp 1 -m 4G,maxmem=4G -object memory-backend-file,id=mem,size=4G,mem-path=/dev/shm,share=on -numa node,memdev=mem -chardev socket,id=char0,path=/tmp/vhostqemu -device vhost-user-fs-pci,queue-size=1024,chardev=char0,tag=myfstoro,addr=6 -nographic -net nic,model=virtio -net tap,ifname=tap0"

../../builder/BuildMultibootKernel.sh $app "$compileropt"
echo "qemu.args=$qemuparams"
echo "Press Ctrl-a x to exit emulator"
~/qemu-for-virtiofs/build/x86_64-softmmu/qemu-system-x86_64 --enable-kvm -kernel $appbin $qemuparams
