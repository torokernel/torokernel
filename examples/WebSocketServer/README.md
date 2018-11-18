# Web Sockets Server Example

This example shows the use of WebSockets  in Toro. It is made of two microservices. One microservice runs on port 80 and provides the main web page, e.g., index.html. The second microservice runs on port 880 and provides the web socket interface. To try this example, you need to first create a bridge and tells Qemu to use it. To do this, edit **/etc/qemu-ifup** and modify the line switch by **switch=toro-bridge**. Go to **examples** directory and run:

`virsh net-create toro-kvm-network.xml`

If you already did this and you did not reboot the system, please do not do it again. 

Second, you can use Lazarus to open **WebSocketsServer.lpi** or you can just use **CloudIt** form the command line to test it. The main code is in **WebSocketsServer.pas**. To compile and try the application on QEMU, go to the **WebSocketsServer** directory and run:

`../CloudIt.sh WebSocketsServer "" "-display gtk"` 

If you want to test without any graphical interface just run:

`../CloudIt.sh WebSocketsServer `

If you want to redirect the screen through VNC just run:

`../CloudIt.sh WebSocketsServer "" "-vnc :0"`

You can connect then connect the client to **localhost:5900**

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just run:

`../CloudIt.sh WebSocketsServer "-dEnableDebug -dDebugProcess"`

You will see how toro begins to initialize the unit by calling the scheduler.

To create the guest by using virsh run the following command:

`virsh create WebSocketsServer.xml`

Note that you need to first edit **WebSocketsServer.xml** to correct the path of the **WebSocketsServer.img**.

## Windows Users

Windows' users can just use Lazarus to open **WebSocketsServer.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
