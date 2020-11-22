# Exception Handling Example

In this example, we show how the handling of exceptions. The mechanism is the same that used in freepascal or delphi. You need to just wrap up your statements with the **try..except** keywords. Toro handles exceptions in the same way other kernel does. It invokes the user's code if an exception happens. In Linux, to compile and exceute the application on QEMU, go to the **ExceptionHandling** directory and execute:

`../CloudIt.sh ExceptionHandling "" "-display gtk"` 

If you want to test without graphical interface execute:

`../CloudIt.sh ExceptionHandling`

If you want to redirect the screen through VNC execute:

`../CloudIt.sh ExceptionHandling "" "-vnc :0"`

You can connect the vnc client to **localhost:5900**

If you want to enable some debug symbols in the unit **Process** and check what Toro is doing execute:

`../CloudIt.sh ExceptionHandling "-dEnableDebug -dDebugProcess"`

You will see how toro initializes the unit by calling the scheduler.

## Windows Users

Windows' users should open **ExceptionHandling.lpi** and launch the compilation and execution of the application directly from the IDE by doing first **Compile** and then **Run**.
