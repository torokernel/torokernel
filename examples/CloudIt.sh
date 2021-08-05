#!/bin/bash
#
# CloudIt.sh <Application> [CompilerOptions] [QemuOptions]
#
# Example: CloudIt.sh HelloWorld
#
# Copyright (c) 2003-2021 Matias Vara <matiasevara@gmail.com>
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
qemufile="qemu.args";
compileropt="$2";
# if you change it, do not commit it because CI wont work
# if you sudo CloudIt, this may contain an incorrect USER
fpcrtlsource="$(eval echo ~$USER)/fpc-3.2.0/rtl/";
# change to -O- for debugging
compileropti="-O2 -v0"
qemudir="$(eval echo ~$USER)/qemuforvmm/build/x86_64-softmmu"

export KERNEL_HEAD=$(git rev-parse HEAD|cut -c1-7)
export BUILD_TIME=$(date)

# check parameters
if [ "$#" -lt 1 ]; then
   echo "Usage: CloudIt.sh ApplicationName [CompilerOptions] [QemuOptions]"
   echo "Example: CloudIt.sh ToroHello \"-dEnableDebug -dDebugProcess\" \"vnc :0\""
   exit 1
fi

# get the qemu parameters
if [ -f $qemufile ]; then
   qemuparams=`cat $qemufile`
else
   # parameters by default
   qemuparams="-no-acpi -enable-kvm -M microvm,pic=off,pit=off,rtc=off -cpu host -m 128 -smp 1 -nographic -D qemu.log -d guest_errors -no-reboot -global virtio-mmio.force-legacy=false"
fi

# remove all compiled files
rm -f ../../rtl/*.o ../../rtl/*.ppu ../../rtl/drivers/*.o ../../rtl/drivers/*.ppu

# remove the application
rm -f $app "$app.o"

# NOTE: It is very important to set up -Fu otherwise fpc will use the installed units
if [ -f $appsrc ]; then
   # The symbols defined/undefined are the same than in system.pp
fpc -v0 -dFPC_NO_DEFAULT_MEMORYMANAGER -dHAS_MEMORYMANAGER -uFPC_HAS_INDIRECT_ENTRY_INFORMATION -dx86_64 -I$fpcrtlsource/objpas/sysutils/ -I$fpcrtlsource/linux/x86_64/ -I$fpcrtlsource/x86_64/ -I$fpcrtlsource/linux/ -I$fpcrtlsource/inc/ -I$fpcrtlsource/unix/ -Fu$fpcrtlsource/unix/ -Fu$fpcrtlsource/linux/ -MObjfpc $fpcrtlsource/linux/si_prc.pp -Fu$fpcrtlsource/objpas -Fu$fpcrtlsource/inc
fpc -v0 -Us -dx86_64 -I$fpcrtlsource/objpas/sysutils/ -I$fpcrtlsource/linux/x86_64/ -I$fpcrtlsource/x86_64/ -I$fpcrtlsource/linux/ -I$fpcrtlsource/inc/ -I$fpcrtlsource/unix/ -Fu$fpcrtlsource/unix -Fu$fpcrtlsource/linux -Fu$fpcrtlsource/objpas -Fu$fpcrtlsource/inc $fpcrtlsource/linux/system.pp
fpc -TLinux -I$fpcrtlsource/objpas/sysutils/ -I$fpcrtlsource/linux/x86_64 -I$fpcrtlsource/x86_64/ -I$fpcrtlsource/linux/ -I$fpcrtlsource/inc/ -I$fpcrtlsource/unix/ $compileropt -Xm -Si $compileropti $appsrc -o$app -Fu../../rtl -Fu../../rtl/drivers -Fu$fpcrtlsource/unix -Fu$fpcrtlsource/linux -Fu$fpcrtlsource/objpas -Fu$fpcrtlsource/inc -MObjfpc -kprt0.o
   sudo $qemudir/qemu-system-x86_64 -kernel $app $qemuparams $3
else
   echo "$appsrc does not exist, exiting"
   exit 1
fi
