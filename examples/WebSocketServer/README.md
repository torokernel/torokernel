# Web Sockets Server Example

This example shows the use of WebSockets in Toro. It is made of two microservices: one microservice runs on port 80 and provides the main web page, i.e., index.html. The second microservice runs on port 880 and provides the web socket interface. To run this example, you need to first create a bridge and tells Qemu to use it. To do this, edit **/etc/qemu-ifup** and modify the line switch by **switch=toro-bridge**. Go to **examples** directory and run:

`virsh net-create toro-kvm-network.xml`

If you already did this and you did not reboot the system, please do not do it again. 

Second to compile and run the application on QEMU, go to the **WebSocketsServer** directory and run:

`../CloudIt.sh WebSocketsServer "" "-display gtk"` 

If you want to run without graphical interface execute:

`../CloudIt.sh WebSocketsServer`

If you want to redirect the screen through vnc execute:

`../CloudIt.sh WebSocketsServer "" "-vnc :0"`

You can connect the vnc client to **localhost:5900**

If you want to change the default IP (192.100.200.100) to 192.100.200.40, run:

`../CloudIt.sh WebSocketsServer "" "-vnc :0 -append 192.100.200.40"`

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just run:

`../CloudIt.sh WebSocketsServer "-dEnableDebug -dDebugProcess"`

You will see how toro begins to initialize the unit by calling the scheduler.

If you want to forward ports between host and guest, execute:

`../Forward.sh 192.100.200.100 80 80`

`../Forward.sh 192.100.200.100 880 880`

By doing this, you create a non-persistEnt rule that forwards connections to Host:80 to 192.100.200.
100:80. In this example, the IP corresponds with the guest IP.

## Windows Users

Windows' users should use Lazarus to open **WebSocketsServer.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
