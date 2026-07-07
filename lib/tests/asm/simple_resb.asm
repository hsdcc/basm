section .bss
buf: resb 8
section .text
global _start
_start:
    mov rax, 60
    xor rdi, rdi
    syscall
