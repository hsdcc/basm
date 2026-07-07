section .text
global _start
_start:
    sub rsp, 32
    mov dword [rsp], 0
    mov byte [rsp+4], 1
    inc qword [rsp+8]
    add dword [rsp], 2
    mov rdi, [rsp]
    add rsp, 32
    mov rax, 60
    syscall
; expect: 2