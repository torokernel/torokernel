#!/bin/sh
app="ToroKeyb"
appsource="$app.pas"
appexe=$app
appimg="$app.img"
debug=false;
emulate=false;
# checking the command line
while [ $# -gt 0 ]
do
    case "$1" in
        -d)  debug=true;;
 	-e)  emulate=true;;
    esac
    shift
done
# making the magic
if $debug ; then
	fpc $appsource -g -Fu../rtl/ -Fu../rtl/drivers
	./build 2 $appexe boot.o $appimg
 	qemu-system-x86_64 -s -S -m 256 -hda $appimg -smp 2 &
        # at this point we need a gdb patched
	../../gdb-7.3/gdb/gdb $appexe 
else
       # calling the compiler
       fpc $appsource -Fu../rtl/ -Fu../rtl/drivers
	./build 2 $appexe boot.o $appimg
       # calling qemu as emulator
	if $emulate ; then
	 	qemu-system-x86_64 -m 256 -hda $appimg -smp 2
        fi
fi 

