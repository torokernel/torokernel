# Hello World Example

This is a simple example of an application that outputs "Hello World" on the screen. In Linux to compile and run the application on QEMU-KVM, go to the **HelloWorld** directory and execute:

`../CloudIt.sh HelloWorld "" "-display gtk"` 

If you want to test without any graphical interface execute:

`../CloudIt.sh HelloWorld`

If you want to redirect the screen through VNC execute:

`../CloudIt.sh HelloWorld "" "-vnc :0"`

You can connect the vnc client to **localhost:5900**

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just execute:

`../CloudIt.sh HelloWorld "-dEnableDebug -dDebugProcess"`

You will see how toro initializes the unit by first calling the scheduler.

If you want to speed up the booting time, you can use **QBoot**. To do this, use **CloudIt** with the following parameters:

`../CloudIt.sh HelloWorld "" "-bios ../../builder/bios.bin"`

## Windows Users

Windows' users should open **HelloWorld.lpi** and launch compilation and execution from the IDE by doing first **Compile** and then **Run**.
