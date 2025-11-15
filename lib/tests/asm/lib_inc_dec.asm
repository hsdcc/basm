section .text
global _start
_start:
    mov rax, 10
    inc rax
    inc rax
    dec rax
    mov rdi, rax
    mov rax, 60
    syscall
