# Toro Kernel

## Introduction

Toro is a dedicated kernel that allows to run a single user application. Toro is a set of libraries that compile with the user application. This results in a image that can run on top of a hypervisor, e.g., KVM, Xen, VirtualBox, or baremetal. To know more about Toro, visit the [blog](http://www.torokernel.io) and the [wiki](https://github.com/MatiasVara/torokernel/wiki).

## Features

* Support to x86-64 architecture
* Support up to 512GB of RAM
* Cooperative Scheduler
* Virtual FileSystem
* Network Stack
* Network drivers:
  - Virtio-net, E1000, NE2000
* Disk Drivers:
  - ATA Disks
* FileSystems:
  - Ext2, Fat
* Fast boot up
* Small image

## Test Toro

Toro includes a set of examples that show basic functionalities of the kernel. These examples can be found in the examples directory. To start with these examples, go [here](https://github.com/MatiasVara/torokernel/wiki/My-first-three-applications-in-Toro). If you want to try Toro, follow a simple tutorial [here](https://github.com/mesarpe/torokernel-docker-qemu-webservices) that aims at running a ToroWebServer in a docker image. To compile and run the `Hello World` example, follow the next instructions:

Install Lazarus and Qemu:

`apt-get install lazarus`

`sudo apt-get install qemu-kvm libvirt-bin ubuntu-vm-builder bridge-utils virtinst`

In `torokernel/builder/`, compile the builder:

`fpc build.pas`

Finally in `torokernel/examples`, compile the application and generate the image:

`fpc -TLinux -O2 ToroHello.pas -oToroHello -Fu../rtl/ -Fu../rtl/drivers -MObjfpc`

`../builder/build 4 ToroHello ../builder/boot.o ToroHello.img`

`qemu-system-x86_64 -m 256 -smp 1 -drive format=raw,file=ToroHello.img`

If everything went well, you will get an instance of Toro running on top of Qemu that outputs `Hello World!`.

## Contributing

To contribute to Toro project, go [here](
https://github.com/MatiasVara/torokernel/wiki/How-to-Contribute)

## License

GPLv3

# References

[0] Matias Vara. A Dedicated Kernel named Toro. FOSDEM 2015.

[1] Matias Vara. Reducing CPU usage of a Toro Appliance. FOSDEM 2018.

[2] Matias Vara, Cesar Bernardini. Toro, a Dedicated Kernel for Microservices. Open Source Summit Europe 2018.

