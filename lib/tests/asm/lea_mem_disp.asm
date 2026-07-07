section .text
global _start
_start:
    sub rsp, 32
    mov qword [rsp], 99
    lea rax, [rsp]
    mov rdi, [rax]
    add rsp, 32
    mov rax, 60
    syscall
; expect: 99