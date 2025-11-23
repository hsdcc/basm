
section .text
    global _start

_start:
    nop

    mov rax, 60
    xor rdi, rdi
    syscall
