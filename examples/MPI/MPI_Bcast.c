#include <stddef.h>
#include "ToroMpi.h"

void mainC(){
    int rank, world_size, i, msgsize;
    int sum, avg_time, max_time, min_time;
    char data[1024];
    uint64_t start, end;
    
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);
    
    // TODO: replace Mpi_Barrier() with a macro that includes a memory barrier
    __asm__ __volatile__  ( "" ::: "memory" ) ;
    Mpi_Barrier(MPI_COMM_WORLD);
    
    for (msgsize=2; msgsize < 2048; msgsize*=2){
        sum = 0;
        for (i=0; i< 100; i++){
            start = Mpi_Wtime();
            Mpi_Bcast(data, msgsize, root);
            end = Mpi_Wtime();
            
            __asm__ __volatile__  ( "" ::: "memory" ) ;
            Mpi_Barrier(MPI_COMM_WORLD);
            
            sum += (int)(end - start);
        }
        sum /= 100;
        Mpi_Reduce(&sum, &min_time, 1, MPI_MIN, root);
        Mpi_Reduce(&sum, &max_time, 1, MPI_MAX, root);
        Mpi_Reduce(&sum, &avg_time, 1, MPI_SUM, root);
        if (rank == root){
            printf("\nMPI_BCAST(%d): min_time: %d cycles, max_time: %d cycles, avg_time: %d cycles\n", msgsize, min_time,
                    max_time, avg_time / world_size);
        }
    }
}
