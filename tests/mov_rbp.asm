; expect: 123
section .text
    global _start
_start:
    mov rbp, 123
    mov rax, rbp
    mov rdi, rax
    mov rax, 60
    syscall
