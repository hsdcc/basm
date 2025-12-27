; expect: 5
section .text
global _start
_start:
    mov rax, -10
    cqo
    mov rbx, -2
    idiv rbx
    mov rdi, rax
    mov rax, 60
    syscall