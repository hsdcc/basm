section .text
global _start
_start:
    mov rax, 1
    mov rcx, 3
    shl rax, cl
    mov rdi, rax
    mov rax, 60
    syscall
; expect: 8