#
# Makefile that compiles the bootloader and build.pas
# 
# Copyright (c) 2003-2016 Matias Vara <matiasevara@gmail.com>
# All Rights Reserved
#
#

# x86_64 Bootloader
BOOT = ../boot/x86_64.s

all : boot.o build prt0.o

boot.o : $(BOOT)
	yasm $(BOOT) -o boot.o

build : build.pas
	fpc build.pas
	rm build.o
	rm buildimg.ppu
	rm buildimg.o
	
prt0.o : prt0.s
	as prt0.s -o prt0.o

.PHONY : clean

clean : 
	rm boot.o
	rm build
	rm prt0.o







