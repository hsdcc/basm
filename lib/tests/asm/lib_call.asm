section .text
global _start

_my_func:
    mov rax, 42
    ret

_start:
    call _my_func
    mov rdi, rax
    mov rax, 60
    syscall
