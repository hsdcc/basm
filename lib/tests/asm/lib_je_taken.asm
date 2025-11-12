section .text
global _start
_start:
    mov rax, 1
    cmp rax, 1
    je .equal
    mov rdi, 1
    jmp .end
.equal:
    mov rdi, 2
.end:
    mov rax, 60
    syscall
