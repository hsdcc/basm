section .bss
buf: dq 64
section .text
global _start
_start:
    lea rsi, [buf]
    mov rax, [rsi]
    test rax, rax
    jne fail
    mov rax, 42
    mov [rsi], rax
    mov rax, [rsi]
    cmp rax, 42
    jne fail
    mov rax, 60
    xor rdi, rdi
    syscall
fail:
    mov rax, 60
    mov rdi, 1
    syscall
; expect: 0
