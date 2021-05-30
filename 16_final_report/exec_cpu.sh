# openmp simd cacheBlocking
export OMP_NUM_THREADS=7
module load intel-mpi
#module load cuda/11.2.146 openmpi
module load gcc
mpicxx final_cpu.cpp -O3 -fopenmp -march=native
mpirun -np 4 ./a.out

rm a.out