#
# Makefile to compile the bootloader and the tools.
# 
# Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
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
	
prt0.o : prt0.s
	as prt0.s -o prt0.o

.PHONY : clean

clean : 
	rm boot.o
	rm build
	rm buildimg.ppu
	rm prt0.o







