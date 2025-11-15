section .text
global _start
_start:
    mov rax, 42
    mov rdx, 0
    mov rbx, 7
    div rbx
    mov rdi, rax
    mov rax, 60
    syscall
