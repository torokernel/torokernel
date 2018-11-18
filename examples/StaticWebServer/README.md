# Static Web Server Example

This is a very simple web server that answers every request with the content of **index.html**. The content of this file is statically loaded in memory. This example shows the use of the filesystem together with the networking stack. To try this example, you need to first create a bridge and tells Qemu to use it. To do this, edit **/etc/qemu-ifup** and modify the line switch by **switch=toro-bridge**. Go to **examples** directory and run:

`virsh net-create toro-kvm-network.xml`

If you already did this and you did not reboot the system, please do not do this again. 

Second, you can use Lazarus to open **StaticWebServer.lpi** or you can just use **CloudIt** form the command line to test it. The main code is in **StaticWebServer.pas**. To compile and try the application on QEMU, go to the **StaticWebServer** directory and run:

`../CloudIt.sh StaticWebServer "" "-display gtk"` 

If you want to test without any graphical interface just run:

`../CloudIt.sh StaticWebServer`

If you want to redirect the screen through VNC just run:

`../CloudIt.sh StaticWebServer "" "-vnc :0"`

You can connect then connect the client to **localhost:5900**

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just run:

`../CloudIt.sh StaticWebServer "-dEnableDebug -dDebugProcess"`

You will see how toro begins to initialize the unit by calling the scheduler.

To create the guest by using virsh run the following command:

`virsh create StaticWebServer.xml`

Note that you need to first edit **StaticWebServer.xml** to correct the path of the **StaticWebServer.img**.

## Windows Users

Windows' users can just use Lazarus to open **StaticWebServer.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
