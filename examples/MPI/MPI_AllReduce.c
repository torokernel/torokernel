// MPI_AllReduce.c
//
// Copyright (c) 2003-2023 Matias Vara <matiasevara@torokernel.io>
// All Rights Reserved
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#include <stddef.h>
#include "ToroMpi.h"
#define VECTOR_LEN 128

void mainC(){
    int rank, world_size, i, j, vectorlen;
    uint32_t sum, avg_time, max_time, min_time;
    uint64_t start, end;
    int r[VECTOR_LEN];
    int s[VECTOR_LEN];

    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    for (i=0; i < VECTOR_LEN; i++){
        r[i] = rank;
    }
    __asm__ __volatile__( "" ::: "memory" );
    Mpi_Barrier(MPI_COMM_WORLD);
    int val = ((world_size-1) * (world_size)) / 2;

    for (vectorlen=1; vectorlen < VECTOR_LEN; vectorlen*=2){
        sum = 0;
        __asm__ __volatile__( "" ::: "memory" ) ;
        Mpi_Barrier(MPI_COMM_WORLD);
        for (i=0; i< 100; i++){
            for (j=0; j< vectorlen; j++){
                s[j] = 0;
            }
            start = Mpi_Wtime();
            Mpi_AllReduce(r, s, vectorlen, MPI_SUM, root);
            end = Mpi_Wtime();
            // verify result
            for (j=0; j < vectorlen; j++){
                if (!(s[j] == val)){
                    break;
                }
            }
            if (j != vectorlen)
                printf("error! %d %d %d %d\n", j, vectorlen, rank, s[j]);
            sum += (int)(end - start);
            __asm__ __volatile__( "" ::: "memory" );
            Mpi_Barrier(MPI_COMM_WORLD);
        }
        sum /= 100;
        Mpi_Reduce(&sum, &min_time, 1, MPI_MIN, root);
        Mpi_Reduce(&sum, &max_time, 1, MPI_MAX, root);
        Mpi_Reduce(&sum, &avg_time, 1, MPI_SUM, root);
        if (rank == root){
            printf("MPI_ALLREDUCE(%d): min_time: %d cycles, max_time: %d cycles, avg_time: %d cycles\n", vectorlen * sizeof(int), min_time,
                    max_time, avg_time / world_size);
        }
    }
}
