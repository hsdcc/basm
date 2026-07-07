section .text
global _start
_start:
    mov rax, 6
    imul rax, 7
    mov rdi, rax
    mov rax, 60
    syscall
; expect: 42