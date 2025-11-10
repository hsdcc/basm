; expect: 0
section .text
    global _start
_start:
    mov rax, 42
    xor rax, rax
    mov rdi, rax
    mov rax, 60
    syscall
