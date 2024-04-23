# Static Web Server Example
This is a webserver appliance that servers files by using the http protocol. This example shows the use of the filesystem together with the networking stack. It also shows the use of the virtio-devices VirtioFS and VirtioVSocket. To try it, just execute the following command:
```python
python3 ../CloudIt.py -a StaticWebServer -r
```
If you want to execute without console, edit qemu.args to append "noconsole" as the last parameter for "-append" kernel command line. Before launching qemu, you need to launch virtiofsd and socat.

The next command executes virtiofsd and shares the directory in source with the guest:

```bash
./virtiofsd --socket-path=/tmp/vhostqemu1 --shared-dir /root/qemulast/build/testdir/
```
The next command forwards connections from localhost:4000 to guest:80:

```bash
./socat TCP4-LISTEN:4000,reuseaddr,fork VSOCK-CONNECT:5:80
```
To debug this example by using gdb, please read HelloWorld/README.md to get the correct command-line.
