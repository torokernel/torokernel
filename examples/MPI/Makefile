all: MPI_Reduce.o MPI_Barrier.o MPI_Bcast.o MPI_AllReduce.o

%.o: %.c
	gcc -g -nostdlib -c $< -o $@
	
clean:
	rm -f MPI_Reduce.o
	rm -f MPI_Barrier.o
	rm -f MPI_Bcast.o
