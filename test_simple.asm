section .text
    global _start

_start:
    mov rax, 42
    push rax
    mov rdi, [rsp]
    mov rax, 60
    syscall
