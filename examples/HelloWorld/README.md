# Hello World Example

This is a simple example of an application that outputs "Hello World" on the screen. To open the project, you can use Lazarus to open **HelloWorld.lpi** or you can just use **CloudIt** form the command line to test it. The main code is in **HelloWorld.pas**. To compile and try the application on QEMU, go to the **HelloWorld** directory and run:

`../CloudIt.sh HelloWorld "" "-display gtk"` 

If you want to test without any graphical interface just run:

`../CloudIt.sh HelloWorld`

If you want to redirect the screen through VNC just run:

`../CloudIt.sh HelloWorld "" "-vnc :0"`

You can connect then connect the client to **localhost:5900**

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just run:

`../CloudIt.sh HelloWorld "-dEnableDebug -dDebugProcess"`

You will see how toro begins to initialize the unit by calling the scheduler.

To create the guest by using virsh run the following command:

`virsh create HelloWorld.xml`

Note that you need to first edit **HelloWorld.xml** to correct the path of the **HelloWorld.img**.

To reduce the size of the generated image, you can compile Toro as a multiboot kernel. This way you can launch a VM on Qemu by just using the **-kernel** option. To do so, first run:

`../../builder/BuildMultibootKernel.sh HelloWorld`

This generates HelloWorld.bin which is a valid multiboot kernel. The size of this binary is only around 130kb. Now you can just launch Qemu by doing: 

`kvm -m 512 -smp 2 -vnc :0 -kernel HelloWorld.bin -monitor stdio` 

By doing this, your kernel boots in only 150ms, well done!

If you want to speed up the booting time, you can use **QBoot**. To do this, just call **kvm** with the following parameters:

`kvm -bios ../../builder/bios.bin  -m 512 -smp 2 -vnc :0 -kernel HelloWorld.bin -monitor stdio`

## Windows Users

Windows' users can just use Lazarus to open **HelloWorld.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
