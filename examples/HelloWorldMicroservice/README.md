# Hello World Microservice Example

This is a example of a microservice in Toro that shows the use of the network stack. This is a very simple microservice that just answers "Hello World" on port 8080. To try this example, you need to firs create a bridge and tells qemu to use it. To do this, edit **/etc/qemu-ifup** and modify the line switch by **switch=toro-bridge**. Then, go to **examples** directory and run:

`virsh net-create toro-kvm-network.xml`

Second, you can use Lazarus to open **HelloWorldMicroservice.lpi** or you can just use **CloudIt** form the command line to test it. The main code is in **HelloWorldMicroservice.pas**. To compile and try the application on QEMU, go to the **HelloWorldMicroservice** directory and run:

`../CloudIt.sh HelloWorldMicroservice "" "-display gtk"` 

If you want to test without any graphical interface just run:

`../CloudIt.sh HelloWorldMicroservice`

If you want to redirect the screen through VNC just run:

`../CloudIt.sh HelloWorldMicroservice "" "-vnc :0"`

You can connect then connect the client to **localhost:5900**

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just run:

`../CloudIt.sh HelloWorldMicroservice "-dEnableDebug -dDebugProcess"`

You will see how toro begins to initialize the unit by calling the scheduler.

To create the guest by using virsh run the following command:

`virsh create HelloWorldMicroservice.xml`

Note that you need to first edit **HelloWorldMicroservice.xml** to correct the path of the **HelloWorldMicroservice.img**.

## Windows Users

Windows' users can just use Lazarus to open **HelloWorldMicroservice.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
