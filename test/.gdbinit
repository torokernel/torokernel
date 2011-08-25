file Toro
target remote localhost:1234
# Setting breakpoints in the exceptions
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
# Setting a breakpoint in the executable begin
b _mainCRTStartup
# Setting a breakpoint in the kernel  initialization
b KERNELSTART
# Setting a breakpoint in the application user begin
b PASCALMAIN
c
