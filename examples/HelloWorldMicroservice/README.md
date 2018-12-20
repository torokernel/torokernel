# Hello World Microservice Example

This is a example of a microservice in Toro that sends "Hello World" on port 8080. To run this example, you need to firs create a bridge and tells qemu to use it. To do this, edit **/etc/qemu-ifup** and modify the line switch by **switch=toro-bridge**. Then, go to **examples** directory and run:

`virsh net-create toro-kvm-network.xml`

Second to compile and run the application on QEMU, go to the **HelloWorldMicroservice** directory and run:

`../CloudIt.sh HelloWorldMicroservice "" "-display gtk"` 

If you want to test without any graphical interface just run:

`../CloudIt.sh HelloWorldMicroservice`

If you want to redirect the screen through VNC just run:

`../CloudIt.sh HelloWorldMicroservice "" "-vnc :0"`

You can connect then connect the client to **localhost:5900**

If you want to change the default IP (192.100.200.100) to 192.100.200.40, run:

`../CloudIt.sh HelloWorldMicroservice "" "-vnc :0 -append 192.100.200.40"`

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just run:

`../CloudIt.sh HelloWorldMicroservice "-dEnableDebug -dDebugProcess"`

You will see how toro begins to initialize the unit by calling the scheduler.

If you want to forward ports between host and guest, execute:

`../Forward.sh 192.100.200.100 8080 80`

By doing this, you create a non-persistent rule that forwards connections to Host:80 to 192.100.200.100:8080. In this example, the IP corresponds with the guest IP. 

## Windows Users

Windows' users should use Lazarus to open **HelloWorldMicroservice.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
