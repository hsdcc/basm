section .text
global _start
_start:
    mov rax, -7
    mov rbx, 6
    imul rax, rbx
    mov rdi, rax
    mov rax, 60
    syscall
