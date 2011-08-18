sudo qemu-system-x86_64 -m 256 -hda toro.img -smp 2 -net nic,model=e1000 -serial file:serial.txt &
#sudo tcpdump -i tap0 -X #host 192.100.200.100 -X
