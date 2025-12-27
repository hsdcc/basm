section .text
    global _start

_start:
    mov rax, 100
    mov rbx, 200
    push rbx
    push rax
    mov rdi, [rsp]      ; Direct exit with [rsp]
    mov rax, 60
    syscall
