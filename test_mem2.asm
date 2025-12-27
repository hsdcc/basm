section .text
    global _start

_start:
    mov rax, 100
    mov rbx, 200
    push rbx
    push rax
    mov rcx, [rsp]
    mov rdx, [rsp+8]
    mov rdi, rcx
    mov rax, 60
    syscall
