#!/bin/sh
APP="ToroNetwork2"
APPSOURCE="$APP.pas"
APPEXE=$APP
APPIMG="$APP.img"
iface=`sudo tunctl -b`
# If DEBUG is up, we compile the kernel with debug symbols 
# and we connect GDB with QEMU for step by step emulation
if [ $1 = "DEBUG" ]; then
	fpc $APPSOURCE -g -Fu../rtl/ -Fu../rtl/drivers
	./build 2 $APPEXE boot.o $APPIMG
 	sudo qemu-system-x86_64 -s -S -m 256 -hda $APPIMG -smp 2 -net nic,model=ne2k_pci -net tap,ifname=$iface &
	../../gdb-7.3/gdb/gdb $APPEXE 
# If it is not, we just compile it and call to qemu
else 
	fpc $APPSOURCE -Fu../rtl/ -Fu../rtl/drivers
	./build 2 $APPEXE boot.o $APPIMG
	sudo qemu-system-x86_64 -m 256 -hda $APPIMG -smp 2 -net nic,model=ne2k_pci -net tap,ifname=$iface
fi 

