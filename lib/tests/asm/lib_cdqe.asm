; expect: 255
section .text
global _start
_start:
    mov rax, 0xffffffff
    cdqe
    mov rdi, rax
    mov rax, 60
    syscall