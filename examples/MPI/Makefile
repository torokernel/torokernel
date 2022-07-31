all: MpiReduceC.o

%.o: %.c
	gcc -nostdlib -c $< -o $@
	
clean:
	rm -f MpiReduceC.o
