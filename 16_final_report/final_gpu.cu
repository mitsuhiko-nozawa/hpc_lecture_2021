#include <mpi.h>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <chrono>
using namespace std;

const int M = 1024;


__global__ void matmul(float *A, float *B, float *C, int N, int size, int offset) {
  int i = blockIdx.y;
  int j = threadIdx.x + blockDim.x * blockIdx.x;
  if (j < N/size){
    int block_dim = min(N/size, blockDim.x);
    extern __shared__ float A_s[];
    for (int ks=0; ks<N; ks+=block_dim) {
      __syncthreads();
      A_s[threadIdx.x] = A[N*i+ks+threadIdx.x];
      __syncthreads();
      for (int k=ks; k<ks+block_dim; k++) {
        C[N*i+j+offset] += A_s[k-ks] * B[N/size*k+j];
      }
    }
  }
}
  

int main(int argc, char** argv) {
  int size, rank;
  MPI_Init(&argc, &argv);
  MPI_Comm_size(MPI_COMM_WORLD, &size);
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  if(rank==0)printf("mpisize : %d\n", size);

  int N = 1024;
  float *A, *B, *C, *subA, *subB, *subC;

  //cudaMallocManaged(&A, N*N*sizeof(float));
  //cudaMallocManaged(&B, N*N*sizeof(float));
  //cudaMallocManaged(&C, N*N*sizeof(float));
  A = (float*)malloc((N*N)*sizeof(float));
  B = (float*)malloc((N*N)*sizeof(float));
  C = (float*)malloc((N*N)*sizeof(float));
  cudaMallocManaged(&subA, (N*N/size)*sizeof(float));
  cudaMallocManaged(&subB, (N*N/size)*sizeof(float));
  cudaMallocManaged(&subC, (N*N/size)*sizeof(float));

    
  vector<float> recv(N*N/size);
  for (int i=0; i<N; i++) {
    for (int j=0; j<N; j++) {
      A[N*i+j] = drand48();
      B[N*i+j] = drand48();
      C[N*i+j] = 0;
    }
  }
  
  for(int i = 0; i < N/size; i++){
    for(int j = 0; j < N/size; j++){
      subC[N*i+j] = 0;
    }
  }
  int offset = N/size*rank;
  for (int i=0; i<N/size; i++)
    for (int j=0; j<N; j++)
      subA[N*i+j] = A[N*(i+offset)+j];
  for (int i=0; i<N; i++)
    for (int j=0; j<N/size; j++)
      subB[N/size*i+j] = B[N*i+j+offset];
  int recv_from = (rank + 1) % size;
  int send_to = (rank - 1 + size) % size;

  double comp_time = 0, comm_time = 0;
  for(int irank=0; irank<size; irank++) {
    auto tic = chrono::steady_clock::now();
    offset = N/size*((rank+irank) % size);

    dim3 grid((N/size+M-1)/M, N/size);
    matmul<<<grid,M,M*sizeof(float)>>>(subA, subB, subC, N, size, offset);
    cudaDeviceSynchronize();

    auto toc = chrono::steady_clock::now();
    comp_time += chrono::duration<double>(toc - tic).count();
    MPI_Request request[2];
    MPI_Isend(&subB[0], N*N/size, MPI_FLOAT, send_to, 0, MPI_COMM_WORLD, &request[0]);
    MPI_Irecv(&recv[0], N*N/size, MPI_FLOAT, recv_from, 0, MPI_COMM_WORLD, &request[1]);
    MPI_Waitall(2, request, MPI_STATUS_IGNORE);
    for (int i=0; i<N*N/size; i++)
      subB[i] = recv[i];
    tic = chrono::steady_clock::now();
    comm_time += chrono::duration<double>(tic - toc).count();
  }
  MPI_Allgather(&subC[0], N*N/size, MPI_FLOAT, &C[0], N*N/size, MPI_FLOAT, MPI_COMM_WORLD);
  for (int i=0; i<N; i++)
    for (int j=0; j<N; j++)
      for (int k=0; k<N; k++)
        C[N*i+j] -= A[N*i+k] * B[N*k+j];
  double err = 0;
  for (int i=0; i<N; i++)
    for (int j=0; j<N; j++)
      err += fabs(C[N*i+j]);
  if(rank==0) {
    double time = comp_time+comm_time;
    printf("N    : %d\n",N);
    printf("comp : %lf s\n", comp_time);
    printf("comm : %lf s\n", comm_time);
    printf("total: %lf s (%lf GFlops)\n",time,2.*N*N*N/time/1e9);
    printf("error: %lf\n",err/N/N);
  }
  
  MPI_Finalize();
  cudaFree(A);
  cudaFree(B);
  cudaFree(C);
  cudaFree(subA);
  cudaFree(subB);
  cudaFree(subC);
}
