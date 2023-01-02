all: MpiReduceC.o MPI_Barrier.o MPI_Bcast.o

%.o: %.c
	gcc -g -nostdlib -c $< -o $@
	
clean:
	rm -f MpiReduceC.o
	rm -f MPI_Barrier.o
	rm -f MPI_Bcast.o
