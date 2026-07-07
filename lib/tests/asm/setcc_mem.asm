section .text
global _start
_start:
    xor rax, rax
    test rax, rax
    sete al
    movzx rdi, al
    mov rax, 60
    syscall
; expect: 1
