#include <stdarg.h>
#include <inttypes.h>

#define root 0
#define MPI_SUM 0
#define MPI_MIN 1
#define MPI_MAX 2
#define MPI_COMM_WORLD 0

extern int Mpi_Scatter(void *, int, void *, int *, int);
extern int Mpi_Reduce(void *, void *, int, int, int);
extern int Mpi_AllReduce(void *, void *, int, int, int);
extern void Mpi_Barrier(int);
extern void MPI_Comm_size(int, int *);
extern void MPI_Comm_rank(int, int *);
extern void PutCtoSerial(char);
extern void PrintDecimal(int);
extern void FlushUp(void);
extern void Mpi_Bcast(void *, int, int);
extern int Mpi_Send(void *, int, int);
extern int Mpi_Recv(void *, int, int);
extern uint64_t Mpi_Wtime(void);

// This is a simple implementation of printf that is not thread safe or int safe
void printf(char * format, ...){
    char * c;
    va_list arg;
    int tmp;
    va_start(arg, format);
    for(c=format; *c != '\0'; c++){
        if ((*c != '%') && (*c != '\\')){
            PutCtoSerial(*c);
            continue;
        }
        if (*c == '\\'){
            c++;
            if (*c == '\0')
                break;
            switch (*c){
                case 'n':
                    FlushUp();
                    break;
            }
        } else{
            c++;
            if (*c == '\0')
                break;
            switch (*c){
                case 'c':
                    tmp = va_arg(arg, int);
                    PutCtoSerial((char)tmp);
                    break;
                case 'l':
                    c++;
                    tmp = va_arg(arg, unsigned long);
                    PrintDecimal(tmp);
                    break;
                case 'd':
                    tmp = va_arg(arg, int);
                    PrintDecimal(tmp);
                    break;
            }
        }
    }
    va_end(arg);
}
