section .text
    global _start

_start:
    mov rax, 123
    mov [rsp-8], rax
    mov rdi, [rsp-8]
    mov rax, 60
    syscall
