#!/bin/sh
apt-get update
apt-get install qemu-kvm libvirt-bin ubuntu-vm-builder bridge-utils virtinst
rmmod kvm
modprobe -a kvm
virsh net-create toro-kvm-network.xml
cp qemu.conf /etc/libvirt/qemu.conf
cp hook-qemu /etc/libvirt/hooks/qemu
chmod +x /etc/libvirt/hooks/qemu
service libvirtd restart
