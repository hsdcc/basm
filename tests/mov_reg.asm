; expect: 42

section .text
    global _start

_start:
    mov rax, 42
    mov rdi, rax
    mov rax, 60
    syscall
