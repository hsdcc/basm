section .text
global _start
_start:
    mov rax, 60
    mov rdi, 10
    xor rdi, rdi
    syscall
