# Static Web Server Example
This is a webserver appliance that servers files by using the http protocol. This example shows the use of the filesystem together with the networking stack. It also shows the use of the virtio-devices VirtioFS and VirtioVSocket. To try it, just execute the following command:
```bash
../CloudIt.sh StaticWebServer "-dShutdownWhenFinished"
```
This tells Toro to use the serial console as screen. Also, the VM can be shutdown by injecting an NMI (see HelloWorld.pas example). If you want to execute without console, edit qemu.args to append "noconsole" as the last parameter for "-append" kernel command line. In addition to launch qemu, you need to launch virtiofsd and socat.

The next command executes virtiofsd and shares the directory in source with the guest:

```bash
./virtiofsd -d --socket-path=/tmp/vhostqemu1 -o source=/root/qemulast/build/testdir/ -o cache=always -o log_level=debug
```
The next command forwards connections from localhost:4000 to guest:80. The CID is 5:

```bash
./socat TCP4-LISTEN:4000,reuseaddr,fork VSOCK-CONNECT:5:80
```
To debug this example by using gdb, please read HelloWorld/README.md to get the correct command-line.
