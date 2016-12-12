#!/bin/sh
#
# CloudIt.sh <name>
#
# This script compiles the freepascal application in <name>
# within the Toro Kernel. This results in a disk image named 
# <name>.img. Then, this image is used to run a instance of 
# the app in a VM in QEMU. 
# 

app="$1";
appsource="$app.pas";
appbin=$app;
appimg="$app.img";
qemufile="$app.qemu"

# we get the parameters
qemuparam=`cat $qemufile`

# we compile the application
fpc $appsource -o$appbin -Fu../rtl/ -Fu../rtl/drivers
./build 2 $appbin boot.o $appimg

# we run the application in qemu
qemu-system-x86_64 $qemuparam -drive format=raw,file=$appimg
