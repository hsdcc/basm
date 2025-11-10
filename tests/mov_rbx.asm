; expect: 42

section .text
    global _start
_start:
    mov rbx, 42
    mov rax, rbx
    mov rdi, rax
    mov rax, 60
    syscall
