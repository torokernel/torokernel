# Hello World Example
This is a simple example of an application that outputs "Hello World" on the screen. In Linux to compile and run the application, go to the **HelloWorld** directory and execute:
```bash
python3 ../CloudIt.py -a HelloWorld
```
## NMI Shutdown
It is possible to shutdown an instance of Toro by using a NMI exception. To do this, create a Toro's instance with the following parameters:

```bash
python3 ../CloudIt.py -a HelloWorld -s
```
Then from Qemu Monitor, execute the **nmi** command to shutdown the instance. It is also possible to define a shutdown procedure which will be invoked after the NMI is catched and before the system is shutdown. Check the source code of HelloWorld.pas to see how to register this procedure.   
