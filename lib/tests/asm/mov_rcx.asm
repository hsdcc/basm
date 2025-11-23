; expect: 42

section .text
    global _start
_start:
    mov rcx, 42
    mov rax, rcx
    mov rdi, rax
    mov rax, 60
    syscall
