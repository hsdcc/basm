; expect: 13

section .text
    global _start

_start:
    mov rax, 10
    add rax, 5
    sub rax, 2
    mov rdi, rax
    mov rax, 60
    syscall
