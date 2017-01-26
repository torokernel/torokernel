#!/bin/sh
#
# CloudIt.sh <name>
#
# This script compiles the freepascal application in <name>
# within the Toro Kernel. This results in a disk image named 
# <name>.img. Then, this image is used to run a instance of 
# the app in a VM in QEMU. The script checks if the file <name>.qemu 
# exists. In that case, it uses the content of the file as parameters
# for qemu. The script also checks if the scripts <name>.pre and <name>.post
# exists. In that case, it executes those scripts as pre and post compilation.  
#
# Copyright (c) 2003-2016 Matias Vara <matiasevara@gmail.com>
# All Rights Reserved
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

app="$1";
appsource="$app.pas";
appbin=$app;
appimg="$app.img";
qemufile="$app.qemu"
prefile="$app.pre.sh"
postfile="$app.post.sh"

# we get the parameters
if [ -f $qemufile ]; then
	qemuparam=`cat $qemufile`
fi

# we execute the pre script
if [ -f $prefile ]; then
	sh $prefile
fi

# we compile the application
fpc $appsource -o$appbin -Fu../rtl/ -Fu../rtl/drivers

# we build the image
if [ -f boot.o ]; then 
	./build 2 $appbin boot.o $appimg
else
	echo "ERROR: boot.o not found, run make first"
	exit 
fi

# we execute the post compilation script
if [ -f $postfile ]; then
    # we run the application in qemu in background and 
	# we run the post compilation script
    qemu-system-x86_64 $qemuparam -drive format=raw,file=$appimg &
	sh $postfile
else
	# we run the application in qemu
	qemu-system-x86_64 $qemuparam -drive format=raw,file=$appimg
fi

