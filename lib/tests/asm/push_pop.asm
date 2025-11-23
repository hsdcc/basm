; expect: 42

section .text
    global _start

_start:
    mov rax, 42
    push rax
    pop rdi

    mov rax, 60
    syscall