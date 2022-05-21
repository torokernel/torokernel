# Hello World Example
This is a simple example of an application that outputs "Hello World" on the screen. In Linux to compile and run the application, go to the **HelloWorld** directory and execute:
```bash
../CloudIt.sh HelloWorld
```
If you want to enable some debug symbols in the unit **Process** and check what Toro is doing just execute:
```bash
../CloudIt.sh HelloWorld "-dEnableDebug -dDebugProcess"
```
You can open the file logs to see how toro initializes the unit by first calling the scheduler. Note that debugging always require to have a virtio-console device.

To debug Toro by using the GDBstub built-in and gdb, first edit qemu.args and modifiy the followingline:
```bash
-chardev socket,host=0.0.0.0,port=1234,server=on,wait=on,id=charconsole0
```
Then, execute:
```bash 
../CloudIt.sh HelloWorld "-gl -dUseGDBstub"
```
Finally, execute gdb by doing:
```bash
gdb HelloWorld -ex 'set arch i386:x86-64' -ex 'target remote localhost:1234'
```
You can set a breakpoint or continue the execution. For example, to set a breakpoint at the beginning of HelloWorld.pas program, execute:
```bash
b HelloWorld.pas:49
c
```
The execution will stop when the breakpoint is reached.
## NMI Shutdown
It is possible to shutdown an instance of Toro by using a NMI exception. To do this, create a Toro's instance with the following parameters:

```bash
../CloudIt.sh HelloWorld "-dShutdownWhenFinished"
```
Then from Qemu Monitor, execute the **nmi** command to shutdown the instance. It is also possible to define a shutdown procedure which will be invoked after the NMI is catched and before the system is shutdown. Check the source code of HelloWorld.pas to see how to register this procedure.   
## Windows Users
Windows' users should open **HelloWorld.lpi** and launch compilation and execution from the IDE by doing first **Compile** and then **Run**.
