# Toro Kernel

## Introduction

Toro is a kernel that allows the user to dedicate a whole kernel to run a single application. Toro is a set of libraries that compiles together with the user application. This results in a image that can run on top of a hypervisor, e.g., KVM, Xen, VirtualBox, or baremetal. To know more about Toro, visit the [blog](http://www.torokernel.io) and the [wiki](https://github.com/MatiasVara/torokernel/wiki).

## Features

* Support to x86-64 architecture
* Support up to 512GB of RAM
* Support to KVM, Xen, HyperV, VirtualBox and Qemu-Lite
* Cooperative Scheduler
* Virtual FileSystem
* Network Stack
* Network drivers:
  - Virtio-net, E1000, NE2000
* Disk drivers:
  - ATA disks
* FileSystem drivers:
  - Ext2, Fat
* Fast boot up
* Tiny image

## Examples

The repository of Toro includes examples that show basic functionalities of the kernel. These examples are in the **examples** directory. Each example contains the instruction to compile it and run it on QEMU-KVM. We recommend to start with the **HelloWorld** example. Before go to the example, you need to install Lazarus and QEMU-KVM:

`apt-get install lazarus`

`sudo apt-get install qemu-kvm libvirt-bin ubuntu-vm-builder bridge-utils virtinst`

To try Toro, you can follow a simple tutorial [here](https://github.com/mesarpe/torokernel-docker-qemu-webservices) that aims at running a static web server inside a docker image. 

## Contributing

To contribute to Toro project, go [here](
https://github.com/MatiasVara/torokernel/wiki/How-to-Contribute)

## License

GPLv3

# References

[0] Matias Vara. A Dedicated Kernel named Toro. FOSDEM 2015.

[1] Matias Vara. Reducing CPU usage of a Toro Appliance. FOSDEM 2018.

[2] Matias Vara, Cesar Bernardini. Toro, a Dedicated Kernel for Microservices. Open Source Summit Europe 2018.

[3] Matias Vara. Speeding Up the Booting Time of a Toro Appliance. FOSDEM 2019.

