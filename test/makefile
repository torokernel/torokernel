#
# Makefile to compile the test files using RTL Toro.
# 
# Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
# All Rights Reserved
#
#

UNITS = -Fu../rtl/ -Fu../rtl/drivers/

# bootloader for x86_64 arch 
BOOT = ../boot/x86_64.s

all : boot.o build prt0.o toro.img

boot.o : $(BOOT)
	yasm $(BOOT) -o boot.o

build : build.pas
	fpc build.pas
	
prt0.o : prt0.s
	as prt0.s -o prt0.o

toro.img : Toro.pas 
	fpc $(UNITS) Toro.pas
	./build 2 Toro boot.o toro.img

.PHONY : clean

clean : 
	rm *.img
	rm *.o
	rm *.bin
	rm ../rtl/*.o
	rm ../rtl/*.ppu
	rm ../rtl/drivers/*.o
	rm ../rtl/drivers/*.ppu







