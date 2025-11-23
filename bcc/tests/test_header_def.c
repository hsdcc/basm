#include "my_header.h"

int main() {
#ifdef HELLO_CONSTANT
    int x = get_hello_constant();
    return x;
#else
    return 0;
#endif
}