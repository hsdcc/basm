section .text
global _start
_start:
    mov rax, -42
    mov rdx, -1
    mov rbx, 7
    idiv rbx
    mov rdi, rax
    mov rax, 60
    syscall
