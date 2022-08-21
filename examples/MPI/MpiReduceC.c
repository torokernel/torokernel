#include <stddef.h>
#include "ToroMpi.h"
#define VECTOR_LEN 64

void mainC(){
    int rank, world_size, i;
    int r[VECTOR_LEN];
    int s[VECTOR_LEN];
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);
    for (i=0; i < VECTOR_LEN; i++){
        r[i] = rank;
    }
    Mpi_Barrier(MPI_COMM_WORLD);
    printf("hello from core", rank);
    // reduce an array of size VECTOR_LEN
    // by using the MPI_SUM operation
    Mpi_Reduce(r, s, VECTOR_LEN, MPI_SUM, root);
    if (rank == root){
     for (i=0;  i < VECTOR_LEN; i++){
       // Sum = ((N - 1) * N) / 2
       if (s[i] != (((world_size-1) * world_size) / 2)){
           printf("failed!, core:", rank);
           break;
       }
     }
     if (i == VECTOR_LEN){
        printf("success! value:", s[i-1]);
     }
    }
}
