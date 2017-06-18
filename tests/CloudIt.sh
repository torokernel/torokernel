#!/bin/sh
#
# CloudIt.sh <Application>
#
# Script that helps to compile and run an app in Linux. To compile we base on
# wine and to run we base on KVM.
#
# Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
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
applpi="$app.lpi";
appimg="$app.img";

# remove all compiled files
rm -f ../rtl/*.o ../rtl/*.ppu
rm -f $appimg

# remove the application
rm -f $app "$app.o"

# force to compile the application
wine c:/lazarus/lazbuild.exe $applpi

# destroy any previous instance
sudo virsh destroy $app 
sudo virsh undefine $app

# TODO parameters should come from the .pas
# VNC is open at port 590X
sudo virt-install --name=$app --vcpus=2 --ram=512 --disk path=$appimg --boot hd --graphics vnc
