#!/bin/sh
#
# CloudIt.sh <name>
#
# This script compiles the freepascal application in <name>
# within the Toro Kernel. This results in a disk image named 
# <name>.img. Then, this image is used to run a instance of 
# the app in a VM in QEMU. 
# 
# TODO: Parameters of QEMU should vary depending on the app.
#		It should be interested to have a separatly file that 
#		tells information about the platform.  
#
app="$1";
appsource="$app.pas";
appbin=$app;
appimg="$app.img";

# compiling
fpc $appsource -o$appbin -Fu../rtl/ -Fu../rtl/drivers
./build 2 $appbin boot.o $appimg
# calling qemu
#if [ "$OSTYPE" == "msys" ] ; then
	qemu-system-x86_64 -m 256 -hda $appimg -smp 2
#	  elif [ "$OSTYPE" == "linux-gnu" ] ; then
#	qemu-system-x86_64 -m 256 -hda $appimg -smp 2
#fi
