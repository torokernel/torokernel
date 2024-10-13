# Toro![build passing](https://api.travis-ci.org/torokernel/torokernel.svg?branch=master)
## Introduction
Toro is a unikernel dedicated to deploy applications as microVMs. Toro leverages on virtio-fs and virtio-vsocket to provide a minimalistic architecture.

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

## How try Toro?
You can try Toro by running the HelloWorld example using a Docker image that includes all the required tools. To do so, execute the following commands in a console (these steps require you to install before KVM and Docker):

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
sudo docker pull torokernel/torokernel-dev:latest
sudo docker run --privileged --rm -it torokernel/torokernel-dev:latest
```
You can share a directory from the host by running:
```bash
sudo docker run --privileged --rm --mount type=bind,source="$(pwd)",target=/root/torokernel -it torokernel/torokernel-dev:latest
```
You will find $pwd from host at `/root/torokernel` in the container.

## How build Toro locally?
Execute the commands in `ci/Dockerfile` to install the required components locally. Then, Go to `torokernel/examples` and edit `CloudIt.py` to set the correct paths to Qemu and fpc. Optionally, you can install vsock-socat from [here](https://github.com/stefano-garzarella/socat-vsock) and virtio-fs from [here](https://gitlab.com/virtio-fs/virtiofsd.git). You need to set the correct path to virtiofsd and socat.

## Run the HelloWorld Example
Go to `examples/HelloWorld/` and execute:
```bash
python3 ../CloudIt.py -a HelloWorld
```
![HelloWorld](https://github.com/torokernel/torokernel/wiki/images/helloworld.gif)

## Run the StaticWebServer Example
To run the StaticWebserver, you require virtiofsd and socat. To compile socat, execute the following commands:
```bash
git clone git@github.com:stefano-garzarella/socat-vsock.git
cd socat-vsock
autoreconf -fiv
./configure
make socat
```
Set the path to socat binary in CloudIt.py and then execute:
```bash
python3 ../CloudIt.py -a StaticWebServer -r -d /path-to-directory/ -f 4000:80
```
You have to replace the `/path-to-directory/` to a directory that containing the files, e.g., index.html. To try it, you can execute:
```
wget http://127.0.0.1:4000/index.html
```
The `-f` parameter indicates a forwarding of the 4000 port from the host to the 80 port in the guest using vsock.

![HelloWorld](https://github.com/torokernel/torokernel/wiki/images/staticwebser.gif)

## Run the Intercore Communication example
This example shows how cores can communicate by using the VirtIOBus device. In this example, core #0 sends a packet to every core in the system with the **ping** string. Each core responds with a packet that contains the message **pong**. This example is configured to use three cores. To launch it, simply executes the following commands in the context of the container presented above:
```bash
python3 ../CloudIt.py -a InterCoreComm
```
You will get the following output:
![InterComm](https://github.com/torokernel/torokernel/wiki/images/intercom.gif)

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
