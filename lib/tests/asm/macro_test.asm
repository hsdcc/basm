%macro print_str 2
    mov rax, 1
    mov rdi, 1
    mov rsi, %1
    mov rdx, %2
    syscall
%endmacro

section .data
    msg db "hello world", 10
    len equ $ - msg

section .text
    global _start

_start:
    print_str msg, len

    mov rax, 60
    xor rdi, rdi
    syscall
