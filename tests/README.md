# Testing of Unit's interface
This folder contains tests for the different units of the kernel. Each folder contains a program that tests the interface of a unit. For example, the program *process/TestProcess.pas* tests the interface of the unit *Process.pas*. Not all the procedures and functions from an interface are tested. This is the enviroment that the tests expect to run:
* qemu is at ~/qemuvmm
* virtiofsd is at ~/qemuvmm/build/tools/viritofsd
* fpc is installed (3.2.0)
* RTL for Toro is at ~/fpc-3.2.0/

Each program is launched by using an script with the same name. For example, *TestProcess.pas* is compiled and launched by *TestProcess.sh*. This script parses the serial output to check if any tests has failed. In that case, the script outputs the serial console and exits with '1'. When this runs in the CI, this makes the travis job to fail. 
