# Toro Kernel ![build passing](https://api.travis-ci.org/torokernel/torokernel.svg?branch=master)

## Introduction

Toro is a kernel that allows the user to dedicate a whole kernel to run a single application. Toro is a set of libraries that compiles together with the user application. This results in a image that can run on top of a hypervisor, e.g., KVM, Xen, VirtualBox, or baremetal. To know more about Toro, visit the [blog](http://www.torokernel.io) and the [wiki](https://github.com/MatiasVara/torokernel/wiki).

## Features

* Support to x86-64 architecture
* Support up to 512GB of RAM
* Support to KVM, Xen, HyperV, VirtualBox and Firecraker
* Cooperative Scheduler
* Virtual FileSystem
* Network Stack
* Network drivers:
  - Virtio-socket, Virtio-net, E1000, NE2000
* Disk drivers:
  - Virtio-blk, ATA
* FileSystem drivers:
  - Ext2, Fat, VirtioFS
* Fast boot up
* Tiny image

## Examples

The repository of Toro includes examples that show basic functionalities of the kernel. These examples are in the **examples** directory. Each example contains the instruction to compile it and run it on QEMU-KVM. We recommend to start with the **HelloWorld** example. Before go to the example, you need to install Lazarus and QEMU-KVM:

`apt-get install lazarus`

`sudo apt-get install qemu-kvm libvirt-bin ubuntu-vm-builder bridge-utils virtinst`

To try Toro, you can follow a simple tutorial [here](https://github.com/mesarpe/torokernel-docker-qemu-webservices) that aims at running a static web server inside a docker image. 

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

[5] Leveraging Virtio-fs and Virtio-vsocket in Toro Unikernel. Matias Vara. DevConfCZ 2019.