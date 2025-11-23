#include "test_custom_header.h"

int main() {
#ifdef CUSTOM_CONSTANT
    int result = add_numbers(5, 10);
    printf("Result of add_numbers(5, 10): %d\n", result);
    printf("CUSTOM_CONSTANT: %d\n", CUSTOM_CONSTANT);
    print_custom_message();
#else
    printf("CUSTOM_CONSTANT not defined\n");
#endif

    int calc = CUSTOM_FUNCTION(5);
    printf("CUSTOM_FUNCTION(5): %d\n", calc);
    
    return 0;
}