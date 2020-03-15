# Hello World Example

This is a simple example of an application that outputs "Hello World" on the screen. In Linux to compile and run the application, go to the **HelloWorld** directory and execute:

`../CloudIt.sh HelloWorld "" "-display gtk"` 

If you want to output the screen through serial, run:

`../CloudIt.sh HelloWorld "-dUseSerialasConsole"`

If you want to redirect the screen through VNC, run:

`../CloudIt.sh HelloWorld "" "-vnc :0"`

You can connect the vnc client to **localhost:5900**

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just execute:

`../CloudIt.sh HelloWorld "-dEnableDebug -dDebugProcess"`

You will see how toro initializes the unit by first calling the scheduler.

If you want to speed up the booting time, you can use **QBoot**. To do this, use **CloudIt** with the following parameters:

`../CloudIt.sh HelloWorld "" "-bios ../../builder/bios.bin"`

## NMI Shutdown
It is possible to shutdown an instance of Toro by using a NMI exception. To do this, create a Toro's instance with the following parameters:

`../CloudIt.sh HelloWorld "-dUseSerialasConsole -dShutdownWhenFinished"` 

Then from Qemu Monitor, execute the **nmi** command to shutdown the instance. It is also possible to define a shutdown procedure which will be invoked after the NMI is catched and before the system is shutdown. Check the source code of HelloWorld.pas to see how to register this procedure.   
 
## Windows Users

Windows' users should open **HelloWorld.lpi** and launch compilation and execution from the IDE by doing first **Compile** and then **Run**.
