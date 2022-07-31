#define root 0
#define MPI_SUM 0
#define MPI_COMM_WORLD 0
extern int Mpi_Scatter(void *, int, void *, int *, int);
extern int Mpi_Reduce(void *, void *, int, int, int);
extern void MPI_Comm_size(int, int *);
extern void MPI_Comm_rank(int, int *);
extern int printf(char *, int);
