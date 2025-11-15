section .text
global _start
_start:
    mov rax, 1
    mov rcx, 2
    mov rdx, 3
    mov rbx, 4
    mov rbp, 6
    mov rsi, 7
    mov rdi, 8
    push rax
    push rcx
    push rdx
    push rbx
    push rbp
    push rsi
    push rdi
    pop rdi
    pop rsi
    pop rbp
    pop rbx
    pop rdx
    pop rcx
    pop rax
    mov rdi, rax
    mov rax, 60
    syscall
