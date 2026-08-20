#include <stdio.h>

__global__ void hello() {}

int main() {
    hello<<<1,1>>>();
    cudaDeviceSynchronize();
    printf("OK\n");
    return 0;
}
