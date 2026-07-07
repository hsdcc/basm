section .rodata
msg: db "hello", 0
section .text
global _start
_start:
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg]
    mov rdx, 5
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
; expect: 0
