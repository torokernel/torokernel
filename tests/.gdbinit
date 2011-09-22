#  setting Toro binary
  file ToroHello
# connection to qemu via TCP/IP
target remote localhost:1234
# enable the exception breakpoints just if you need it
# setting a breakpoint in the executable begin
# b _mainCRTStartup
# setting a breakpoint in the kernel  initialization
  b KERNELSTART
# setting a breakpoint in the application user begin
# b PASCALMAIN
# continuing
c
