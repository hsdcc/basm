#include "simple_header.h"

int main() {
#ifdef MY_CONSTANT
    int a = 5;
    int b = test_function(a);
    return 0;
#else
    int a = 10;
    return 0;
#endif
}