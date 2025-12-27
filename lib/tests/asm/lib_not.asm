; expect: 245
section .text
global _start
_start:
    mov rax, 10
    not rax
    mov rdi, rax
    mov rax, 60
    syscall