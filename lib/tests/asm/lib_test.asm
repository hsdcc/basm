section .text
global _start
_start:
    mov rax, 1
    test rax, 1
    jne .not_zero
    mov rdi, 2
    jmp .end
.not_zero:
    mov rdi, 1
.end:
    mov rax, 60
    syscall
