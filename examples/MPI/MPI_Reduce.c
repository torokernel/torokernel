#include <stddef.h>
#include "ToroMpi.h"
#define VECTOR_LEN 64

void mainC(){
    int rank, world_size, i, vectorlen;
    int sum, avg_time, max_time, min_time;
    uint64_t start, end;
    int r[VECTOR_LEN];
    int s[VECTOR_LEN];

    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    __asm__ __volatile__  ( "" ::: "memory" ) ;
    Mpi_Barrier(MPI_COMM_WORLD);

    for (vectorlen=1; vectorlen < 128; vectorlen*=2){
        sum = 0;
        for (i=0; i< 100; i++){
            start = Mpi_Wtime();
            Mpi_Reduce(r, s, vectorlen, MPI_SUM, root);
            end = Mpi_Wtime();
            sum += (int)(end - start);
            __asm__ __volatile__( "" ::: "memory" ) ;
            Mpi_Barrier(MPI_COMM_WORLD);
        }
        sum /= 100;
        Mpi_Reduce(&sum, &min_time, 1, MPI_MIN, root);
        Mpi_Reduce(&sum, &max_time, 1, MPI_MAX, root);
        Mpi_Reduce(&sum, &avg_time, 1, MPI_SUM, root);
        if (rank == root){
            printf("\nMPI_REDUCE(%d): min_time: %d cycles, max_time: %d cycles, avg_time: %d cycles\n", vectorlen, min_time,
                    max_time, avg_time / world_size);
        }
    }
}
