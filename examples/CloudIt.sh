#!/bin/bash
#
# CloudIt.sh <Application> [CompilerOptions] [QemuOptions]
#
# Example: CloudIt.sh ToroHello "-dEnableDebug -dDebugProcess" "vnc :0"
#
# Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
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
appbin="$app.bin";
qemufile="qemu.args";
compileropt="$2";

# check parameters
if [ "$#" -lt 1 ]; then
   echo "Usage: CloudIt.sh ApplicationName [CompilerOptions] [QemuOptions]"
   echo "Example: CloudIt.sh ToroHello \"-dEnableDebug -dDebugProcess\" \"vnc :0\""
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
   ../../builder/BuildMultibootKernel.sh $app "$compileropt"
else
   echo "$appsrc does not exist, exiting"
   exit 1
fi

if [ -f $appbin ]; then
   echo "qemu.args=$qemuparams"
   echo "Press Ctrl-a x to exit emulator"
   kvm -kernel $appbin $qemuparams $3
else
   echo "$appbin does not exist, exiting"
   exit 1
fi
