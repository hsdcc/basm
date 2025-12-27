; expect: 6
section .text
global _start

factorial:
    cmp rdi, 1
    jle .base
    push rdi
    dec rdi
    call factorial
    pop rdi
    imul rax, rdi
    ret

.base:
    mov rax, 1
    ret

_start:
    mov rdi, 3
    call factorial
    mov rdi, rax
    mov rax, 60
    syscall