fpc ToroNetwork.pas -Fu../rtl/ -Fu../rtl/drivers
./build 2 ToroNetwork boot.o ToroNetwork.img  
iface=`sudo tunctl -b`
sudo qemu-system-x86_64 -m 256 -hda ToroNetwork.img -smp 2 -net nic,model=e1000 -net tap,ifname=$iface
