echo Converting %1.img to %1.vmdk
qemu-img convert -f raw -O vmdk %1.img %1.vmdk
