rm -f ../rtl/*.ppu
rm -f ../rtl/*.o
rm -f ../rtl/drivers/*.o
rm -f ../rtl/drivers/*.ppu
as -o prt0.o prt0.s
fpc -TLinux -O2 "$1.pas" -o"$1" -Fu../rtl/ -Fu../rtl/drivers -MObjfpc
../builder/build 4 "$1" ../builder/boot.o "$1.img"

