section .text
    global _start

_start:
    mov rax, 42
    push rax
    mov rbx, [rsp]
    mov rdi, rbx
    mov rax, 60
    syscall
