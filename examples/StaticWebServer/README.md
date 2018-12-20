# Static Web Server Example

This example is a web server that answers every request with the content of **index.html**. The content of this file is statically loaded into memory. This example shows the use of the filesystem together with the networking stack. To run this example, you need to first create a bridge and tells Qemu to use it. To do this, edit **/etc/qemu-ifup** and modify the line switch by **switch=toro-bridge**. Go to **examples** directory and run:

`virsh net-create toro-kvm-network.xml`

If you already did this and you did not reboot the system, please do not do this again. 

Second to compile and try the application on QEMU, go to the **StaticWebServer** directory and run:

`../CloudIt.sh StaticWebServer "" "-display gtk"` 

If you want to test without graphical interface execute:

`../CloudIt.sh StaticWebServer`

If you want to redirect the screen through vnc execute:

`../CloudIt.sh StaticWebServer "" "-vnc :0"`

You can connect the vnc client to **localhost:5900**

If you want to change the default IP (192.100.200.100) to 192.100.200.40, run:

`../CloudIt.sh StaticWebServer "" "-vnc :0 -append 192.100.200.40"`

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just run:

`../CloudIt.sh StaticWebServer "-dEnableDebug -dDebugProcess"`

You will see how toro begins to initialize the unit by calling the scheduler.

If you want to forward ports between host and guest, execute:

`../Forward.sh 192.100.200.100 80 80`

By doing this, you create a non-persistent rule that forwards connections to Host:80 to 192.100.200.
100:80. In this example, the IP corresponds with the guest IP.

## Windows Users

Windows' users should use Lazarus to open **StaticWebServer.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
