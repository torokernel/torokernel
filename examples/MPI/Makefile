all: MpiReduceC.o MPI_Barrier.o

%.o: %.c
	gcc -nostdlib -c $< -o $@
	
clean:
	rm -f MpiReduceC.o
	rm -f MPI_Barrier.o
