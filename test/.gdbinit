# setting Toro binary
file Toro
# connection to qemu via TCP/IP
target remote localhost:1234
# setting breakpoints in the exceptions
b EXCEPTDIVBYZERO
b EXCEPTOVERFLOW
b EXCEPTBOUND
b EXCEPTILLEGALINS
b EXCEPTDEVNOTAVA
b EXCEPTDF
b EXCEPTSTACKFAULT
b EXCEPTGENERALP
b EXCEPTPAGEFAULT
b EXCEPTFPUE
# enable the exception breakpoints just if you need it
# setting a breakpoint in the executable begin
# b _mainCRTStartup
# setting a breakpoint in the kernel  initialization
# b KERNELSTART
# setting a breakpoint in the application user begin
# b PASCALMAIN
# continuing
# c
