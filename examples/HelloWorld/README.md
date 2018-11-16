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

## Windows Users

Windows' users can just use Lazarus to open **HelloWorld.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
