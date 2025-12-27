; expect: 123
section .text
global _start
_start:
    push rbp
    mov rbp, rsp
    mov rax, 60
    mov rdi, 123
    leave
    syscall