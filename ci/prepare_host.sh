#!/bin/bash
#
# prepare_host.sh
#
# This script is meant to be used to install qemu and fpc in a s1-2 ovh host. 
# The script downloads these packages at ~/. This is the location in which CloudIt.sh
# looks for fpc and qemu by default.
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
cd ~
sudo apt-get update
sudo apt-get install python3-pip make git libcap-dev libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev libglib2.0-dev libpixman-1-dev libseccomp-dev -y
pip3 install ninja
# uncomment to change PATH permanently
# echo 'export PATH=/home/debian/.local/bin:$PATH' >>~/.bashrc 
export PATH="/home/debian/.local/bin:$PATH"
git clone https://github.com/qemu/qemu.git qemuforvmm
cd qemuforvmm
git checkout 51204c2f
mkdir build 
cd build
../configure --target-list=x86_64-softmmu
make
cd ~/
wget https://sourceforge.net/projects/lazarus/files/Lazarus%20Linux%20amd64%20DEB/Lazarus%202.0.10/fpc-laz_3.2.0-1_amd64.deb/download
mv download fpc-laz_3.2.0-1_amd64.deb
sudo apt install ./fpc-laz_3.2.0-1_amd64.deb -y
rm fpc-laz_3.2.0-1_amd64.deb
git clone https://github.com/torokernel/freepascal.git -b fpc-3.2.0 fpc-3.2.0
