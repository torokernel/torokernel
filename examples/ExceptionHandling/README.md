# Exception Handling Example

In this example, we show how users can handle exceptions. The mechanism is the same that used in freepascal or delphi. You need to just wrap up your statements with the try..except keywords. Toro handles exception in the same way other kernel does. It just invokes the rigth user's code if an exception happens. To open the project, you can use Lazarus to open **ExceptionHandling.lpi** or you can just use **CloudIt** form the command line to test it. The main code is in **ExceptionHandling.pas**. To compile and try the application on QEMU, go to the **ExceptionHandling** directory and run:

`../CloudIt.sh ExceptionHandling "" "-display gtk"` 

If you want to test without any graphical interface just run:

`../CloudIt.sh ExceptionHandling`

If you want to redirect the screen through VNC just run:

`../CloudIt.sh ExceptionHandling "" "-vnc :0"`

You can connect then connect the client to **localhost:5900**

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just run:

`../CloudIt.sh ExceptionHandling "-dEnableDebug -dDebugProcess"`

You will see how toro begins to initialize the unit by calling the scheduler.

To create the guest by using virsh run the following command:

`virsh create ExceptionHandling.xml`

Note that you need to first edit **ExceptionHandling.xml** to correct the path of the **ExceptionHandling.img**.

## Windows Users

Windows' users can just use Lazarus to open **ExceptionHandling.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
