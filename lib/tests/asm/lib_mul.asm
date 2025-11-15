section .text
global _start
_start:
    mov rax, 6
    mov rbx, 7
    mul rbx
    mov rdi, rax
    mov rax, 60
    syscall
