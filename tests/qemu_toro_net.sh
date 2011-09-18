#!/bin/sh
make clean
make DEBUG_INFO=1
iface=`sudo tunctl -b`
sudo qemu-system-x86_64 -s -S -m 256 -hda toro.img -smp 2 -net nic,model=e1000 -serial file:serial.txt -net tap,ifname=$iface &
../../gdb-7.3/gdb/gdb Toro 
#sudo tcpdump -i $iface -X host 192.100.200.100 
