#define root 0
#define MPI_SUM 0
extern int Mpi_Scatter(void *, int, void *, int *, int);
extern int Mpi_Reduce(void *, void *, int, int, int);
extern int GetRank(void);
extern int GetCores(void);
extern int printf(char *, int);
