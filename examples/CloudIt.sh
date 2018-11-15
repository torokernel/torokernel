#!/bin/bash
#
# CloudIt.sh <Application>
#
# Script to compile and run a Toro app in Linux. We base on wine 
# to generate the image and on KVM/QEMU to run it.
#
# Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
# All Rights Reserved
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
appsrc="$app.pas";
applpi="$app.lpi";
appimg="$app.img";
qemufile="qemu.args";

# check parameters
if [ "$#" -lt 1 ]; then
   echo "Usage: CloudIt.sh ApplicationName [CompilerOptions] [QemuOptions]"
   echo "Example: CloudIt.sh ToroHello \"-dEnableDebug -dDebugProcess\" \"\""
   exit 1
fi

# get the kvm parameters
if [ -f $qemufile ]; then
   qemuparams=`cat $qemufile`
else
   # parameters by default
   qemuparams="-m 512 -smp 2 -nographic"
fi

# remove all compiled files
rm -f ../../rtl/*.o ../../rtl/*.ppu
rm -f $appimg

# remove the application
rm -f $app "$app.o"

if [ -f $appsrc ]; then
   fpc -TLinux $2 -O2 $appsrc -o$app -Fu../../rtl/ -Fu../../rtl/drivers -MObjfpc
   if [ -f ../../builder/build ]; then
      ../../builder/build 4 $app ../../builder/boot.o $appimg
   else
      echo "Compile builder first!"
      exit 1
   fi
else
   echo "$appsrc does not exist, exiting"
   exit 1
fi

if [ -f $appimg ]; then
   echo "qemu.args=$qemuparams"
   echo "Press Ctrl-a x to exit emulator"
   kvm -drive format=raw,file=$appimg $qemuparams $3
   GuestPID=$!
   echo "Guest PID=$GuestPID"
else
   echo "$appimg does not exist, exiting"
   exit 1
fi
