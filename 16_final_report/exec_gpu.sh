module load gcc
module load cuda/11.2.146 openmpi
nvcc -std=c++11 final_gpu.cu -arch=sm_60 -O3 -Xcompiler "-O3 -fopenmp" -lmpi
mpirun -np 4 ./a.out

rm a.out