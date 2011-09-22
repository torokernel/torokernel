#!/bin/sh
APP="ToroHello"
APPSOURCE="$APP.pas"
APPEXE=$APP
APPIMG="$APP.img"
# If DEBUG is up, we compile the kernel with debug symbols 
# and we connect GDB with QEMU for step by step emulation
if [ $1 = "DEBUG" ]; then
	fpc $APPSOURCE -g -Fu../rtl/ -Fu../rtl/drivers
	./build 2 $APPEXE boot.o $APPIMG
 	qemu-system-x86_64 -s -S -m 256 -hda $APPIMG -smp 2 &
	../../gdb-7.3/gdb/gdb $APPEXE 
# If it is not, we just compile it and call to qemu
else 
	fpc $APPSOURCE -Fu../rtl/ -Fu../rtl/drivers
	./build 2 $APPEXE boot.o $APPIMG
 	qemu-system-x86_64 -m 256 -hda $APPIMG -smp 2 
fi 



