; expect: 42

section .text
    global _start

_start:
    mov rax, 10
    cmp rax, 10
    je .equal
    mov rax, 1
    jmp .end
.equal:
    mov rax, 42
.end:
    mov rdi, rax
    mov rax, 60
    syscall
