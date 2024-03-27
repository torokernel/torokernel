# ToroMicroVM ![build passing](https://api.travis-ci.org/torokernel/torokernel.svg?branch=master)
## Introduction
ToroMicroVM is a unikernel dedicated to deploy microservices as microVMs. ToroMicroVM leverages on virtio-fs and virtio-vsocket to provide a minimalistic architecture. Microservices are deployed as Toro guests in which binaries and files are distributed in a Ceph cluster. The common fileystem allows to easely launch microvms from any node of the cluster.

## Features
* Support x86-64 architecture
* Support up to 512GB of RAM
* Support QEMU-KVM microvm and Firecracker
* Cooperative and I/O bound threading scheduler
* Support virtio-vsocket for networking
* Support virtio-fs for filesystem
* Fast boot up
* Tiny image
* Built-in gdbstub

## How try ToroMicroVM?
You can quickly get a first taste of ToroMicroVM by running the HelloWorld example by building a docker image that includes all the required tools. To do so, execute the following commands in a console (These steps require KVM and Docker):

```bash
wget https://raw.githubusercontent.com/torokernel/torokernel/master/ci/Dockerfile
sudo docker build -t torokernel-dev .
sudo docker run --privileged --rm -it torokernel-dev
cd examples/HelloWorld
python3 ../CloudIt.py -a HelloWorld
```
If these commands execute successfully, you will get the output of the HelloWorld example. 
You can also pull the image from dockerhub instead of building it:
```bash
sudo docker pull torokernel/toro-kernel-dev-debian-10
sudo docker run --privileged --rm -it torokernel/toro-kernel-dev-debian-10
```
You can share a directory from the host by running:
```bash
sudo docker run --privileged --rm --mount type=bind,source="$(pwd)",target=/root/torokernel-host -it torokernel/toro-kernel-dev-debian-10
```
You will find $pwd from host at /root/torokernel-host in the container.

## How build ToroMicroVM locally?
### Step 1. Install Freepascal 3.2.0
```bash
wget https://sourceforge.net/projects/lazarus/files/Lazarus%20Linux%20amd64%20DEB/Lazarus%202.0.10/fpc-laz_3.2.0-1_amd64.deb/download
mv download fpc-laz_3.2.0-1_amd64.deb
apt install ./fpc-laz_3.2.0-1_amd64.deb -y
```
### Step 2. Build Qemu-KVM (qemu 5.2.50 or #51204c2f)
```bash
apt-get update
apt-get install python3-pip make git libcap-dev libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev libglib2.0-dev libpixman-1-dev libseccomp-dev -y
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
```
### Step 3. Get ToroMicroVM
```bash
git clone https://github.com/torokernel/torokernel.git
```
### Step 4. Get the RTL for ToroMicroVM
```bash
git clone https://github.com/torokernel/freepascal.git -b fpc-3.2.0 fpc-3.2.0
```
Note that Step 1, 2, 3 and 4 can be found in the script at `ci/prepare_host.sh`.

### Step 5. Edit path to Qemu and FPC in CloudIt.py
Go to `torokernel/examples` and edit `CloudIt.py` to set the correct paths to Qemu and fpc. Optionally, you can install vsock-socat from [here](https://github.com/stefano-garzarella/socat-vsock).

## Run the HelloWorld Example
You have to go to `examples/HelloWorld/` and execute:
```bash
python3 ../CloudIt.py -a HelloWorld
```
![HelloWorld](https://github.com/torokernel/torokernel/wiki/images/helloworld.gif)

## Run the StaticWebServer Example
You can easily get the StaticWebServer up and running by following the tutorial at [here](https://github.com/torokernel/torowebserverappliance). This would require only a Debian 10 installation. For example, you can get a s1-2 host from OVH. If you prefer to run it step by step, follow the next instructions. You have first to compile vsock-socat and virtiofds. The latter is built during the building of Qemu. The former can be built by executing:
```bash
git clone git@github.com:stefano-garzarella/socat-vsock.git
cd socat-vsock
autoreconf -fiv
./configure
make socat
```
Then, launch vsock-socat by executing:

```bash
./socat TCP4-LISTEN:4000,reuseaddr,fork VSOCK-CONNECT:5:80
```
In a second terminal, execute:

```bash
./virtiofsd -d --socket-path=/tmp/vhostqemu1 -o source=/root/qemulast/build/testdir/ -o cache=always
```

Replace `source` with the directory to serve. Finally, launch the static webserver by executing:  

```bash
python3 ../CloudIt.py -a StaticWebServer
```
![HelloWorld](https://github.com/torokernel/torokernel/wiki/images/staticwebser.gif)

## Run the Intercore Communication example
This example shows how cores can communicate by using the VirtIOBus device. In this example, core #0 sends a packet to every core in the system with the **ping** string. Each core responds with a packet that contains the message **pong**. This example is configured to use three cores. To launch it, simply executes the following commands in the context of the container presented above:
```bash
python3 ../CloudIt.py -a InterCoreComm
```
You will get the following output:
![InterComm](https://github.com/torokernel/torokernel/wiki/images/intercom.gif)

## Building Toro in Windows by using Lazarus
First you have to follow [this](https://github.com/torokernel/torokernel/wiki/How-to-get-a-Crosscompiler-of-Freepascal-for-a-Windows-host-and-Linux-target) tutorial to get a FPC cross-compiler from Windows to Linux.  Then, you have to execute the following script which compiles the RTL for Toro and outputs the generated files in the *x86_64-linux* directory. Note that this script overwrites the RTL for Linux, which is used when the *-TLinux* parameter is passed. This script requires three paths to set up:

1.  *fpcrtlsource*, which is the path to the repository from https://github.com/torokernel/freepascal
2.  *fpcrtllinuxbin*, which is the path to the cross-compiled linux RTL
3. *fpcbinlinux*, which is the path to the fpc compiler.

```bash
fpcrtlsource="c:\Users\Matias\Desktop\fpc-3.2.0\rtl"
fpcrtllinuxbin="c:\fpcupdeluxefortoromicrovm\fpc\bin\x86_64-linux"
fpcbinlinux="c:\fpcupdeluxefortoromicrovm\fpc\bin\x86_64-win64"

$fpcbinlinux/ppcx64.exe -TLinux -dFPC_NO_DEFAULT_MEMORYMANAGER -dHAS_MEMORYMANAGER -uFPC_HAS_INDIRECT_ENTRY_INFORMATION -dx86_64 -I$fpcrtlsource/objpas/sysutils/ -I$fpcrtlsource/linux/x86_64/ -I$fpcrtlsource/x86_64/ -I$fpcrtlsource/linux/ -I$fpcrtlsource/inc/ -I$fpcrtlsource/unix/ -Fu$fpcrtlsource/unix/ -Fu$fpcrtlsource/linux/ -MObjfpc $fpcrtlsource/linux/si_prc.pp -Fu$fpcrtlsource/objpas -Fu$fpcrtlsource/inc -FE$fpcrtllinuxbin

$fpcbinlinux/ppcx64.exe -Us -TLinux -dx86_64 -I$fpcrtlsource/objpas/sysutils/ -I$fpcrtlsource/linux/x86_64/ -I$fpcrtlsource/x86_64/ -I$fpcrtlsource/linux/ -I$fpcrtlsource/inc/ -I$fpcrtlsource/unix/ -Fu$fpcrtlsource/unix -Fu$fpcrtlsource/linux -Fu$fpcrtlsource/objpas -Fu$fpcrtlsource/inc $fpcrtlsource/linux/system.pp -FE$fpcrtllinuxbin
```

Then, you have to go to Lazarus and open the project **HelloWorld.lpi**. You are able to compile the project from compile.

## Create your own distributed filesystem with CephFS
To create a CephFS cluster you can follow these [instructions](https://github.com/torokernel/torocloudscripts).

## Contributing
You have many ways to contribute to Toro. One of them is by joining the Google Group [here](https://groups.google.com/forum/#!forum/torokernel). In addition, you can find more information [here](
https://github.com/MatiasVara/torokernel/wiki/How-to-Contribute).

## License
GPLv3

# References
[0] A Dedicated Kernel named Toro. Matias Vara. FOSDEM 2015.

[1] Reducing CPU usage of a Toro Appliance. Matias Vara. FOSDEM 2018.

[2] Toro, a Dedicated Kernel for Microservices. Matias Vara and Cesar Bernardini. Open Source Summit Europe 2018.

[3] Speeding Up the Booting Time of a Toro Appliance. Matias Vara. FOSDEM 2019.

[4] Developing and Deploying Microservices with Toro Unikernel. Matias Vara. Open Source Summit Europe 2019.

[5] Leveraging Virtio-fs and Virtio-vsocket in Toro Unikernel. Matias Vara. DevConfCZ 2020.

[6] Building a Cloud Infrastructure to Deploy Microservices as Microvm Guests. Matias Vara. KVM Forum 2020.

[7] Running MPI applications on Toro unikernel. Matias Vara. FOSDEM 2023.

[8] Is Toro unikernel faster for MPI?. Matias Vara. FOSDEM 2024.
