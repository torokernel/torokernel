# Toro Kernel ![build passing](https://api.travis-ci.org/torokernel/torokernel.svg?branch=master)
## Introduction
Toro is a kernel dedicated to run a single application. The kernel compiles together with the user application and this results in a binary that user can run on top of a hypervisor, e.g., KVM, Xen, VirtualBox, or baremetal. To know more about Toro, visit the [blog](http://www.torokernel.io) and the [wiki](https://github.com/MatiasVara/torokernel/wiki). Currently Toro is focus on microVM technologies like QEMU microvm or Firecracker, and on the devices virtio-fs for filesystem and virtio-vsocket for networking. 

## Features
* Support x86-64 architecture
* Support up to 512GB of RAM
* Support KVM, Xen, HyperV, VirtualBox
* Support QEMU microvm and Firecracker
* Cooperative and I/O bound threading scheduler
* Virtual FileSystem
* Network Stack
* Network drivers:
  - Virtio-vsocket, Virtio-net, E1000, NE2000
* Disk drivers:
  - Virtio-blk, ATA
* FileSystem drivers:
  - Ext2, Fat, VirtioFS
* Fast boot up
* Tiny image

## Examples
The repository of Toro includes examples that show basic functionalities of the kernel. These examples are in the **examples** directory. Each example contains the instruction to compile it and run it on QEMU-KVM. We recommend to start with the **HelloWorld** example. Before go to the example, you need to install Lazarus and QEMU-KVM:

`apt-get install lazarus`

To install qemu-kvm and build a CephFS cluster to create you can follow [here](https://github.com/torokernel/torocloudscripts). 

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
