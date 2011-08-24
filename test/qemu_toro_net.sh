#!/bin/sh
iface=`sudo tunctl -b`
sudo qemu-system-x86_64 -S -s -m 256 -hda toro.img -smp 2 -net nic,model=e1000 -serial file:serial.txt -net tap,ifname=$iface 
#sudo tcpdump -i $iface -X #host 192.100.200.100 -X
