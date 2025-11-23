#ifndef TEST_CUSTOM_HEADER_H
#define TEST_CUSTOM_HEADER_H

#define CUSTOM_CONSTANT 42
#define CUSTOM_FUNCTION(x) (x * 2)

int add_numbers(int a, int b) {
    return a + b;
}

void print_custom_message() {
    puts("This is from custom header!");
}

#endif // TEST_CUSTOM_HEADER_H