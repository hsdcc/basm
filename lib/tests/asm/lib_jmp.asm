
section .text
global _start

_start:
    jmp after
    mov rdi, 1
    mov rax, 60
    syscall

after:
    mov rdi, 42
    mov rax, 60
    syscall
