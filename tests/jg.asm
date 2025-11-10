; expect: 42
section .text
    global _start
_start:
    mov rax, 10
    cmp rax, 5
    jg .ok
    mov rax, 1
.ok:
    mov rax, 42
    mov rdi, rax
    mov rax, 60
    syscall
