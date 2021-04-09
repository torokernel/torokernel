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

## How compile ToroMicroVM?

### Step 1. Install Freepascal
```bash
apt-get install fpc
```
You have to install version 3.2.0.

### Step 2. Build Qemu-KVM (qemu 5.2.50 or #51204c2f)
```bash
apt-get install libcap-dev libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev libglib2.0-dev libpixman-1-dev libseccomp-dev -y
git clone https://github.com/qemu/qemu.git qemuforvmm
cd qemuforvmm
mkdir build 
cd build
../configure --target-list=x86_64-softmmu
make
```
Note that this step may require to install Ninja to build Qemu.

### Step 3. Get ToroMicroVM
```bash
git clone https://github.com/torokernel/torokernel.git
```

### Step 4. Get the RTL for ToroMicroVM
```bash
git clone https://github.com/torokernel/freepascal.git -b fpc-3.2.0 fpc-3.2.0
```

### Step 5. Edit path to Qemu and FPC in CloudIt.sh
Go to `torokernel/examples` and edit `CloudIt.sh` to set the correct paths to Qemu and fpc. Optionally, you can install vsock-socat from [here](https://github.com/stefano-garzarella/socat-vsock).

## Run the HelloWorld Example
You have to go to `examples/HelloWorld/` and execute:
```bash
../CloudIt.sh HelloWorld
```
And you will get the following output:
![HelloWorld](https://github.com/torokernel/torokernel/wiki/images/helloworld.gif)

## Run the StaticWebServer Example
To run the StaticWebServer example, you have first to compile vsock-socat and virtiofds. The latter is built during the building of Qemu. In a terminal, launch vsock-socat by executing:

```bash
./socat TCP4-LISTEN:4000,reuseaddr,fork VSOCK-CONNECT:5:80
```
In a second terminal, execute:

```bash
./virtiofsd -d --socket-path=/tmp/vhostqemu1 -o source=/root/qemulast/build/testdir/ -o cache=always
```

Replace `source` with the directory to serve. Finally, launch the static webserver by executing:  

```bash
../CloudIt.sh StaticWebServer "-dShutdownWhenFinished"
```

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
