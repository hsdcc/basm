section .text
global _start
_start:
    sub rsp, 32
    mov qword [rsp], 42
    mov qword [rsp+8], 10
    mov rax, [rsp]
    add rax, [rsp+8]
    mov rdi, rax
    add rsp, 32
    mov rax, 60
    syscall
; expect: 52