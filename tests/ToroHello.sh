fpc ToroHello.pas -Fu../rtl/ -Fu../rtl/drivers
./build 2 ToroHello boot.o ToroHello.img  
qemu-system-x86_64 -m 256 -hda ToroHello.img -smp 2
