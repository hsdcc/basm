section .data
    my_var db "a", 0
section .text
global _start
_start:
    lea rsi, [my_var]
    mov rax, 1
    mov rdi, 1
    mov rdx, 1
    syscall
    mov rax, 60
    mov rdi, 0
    syscall
