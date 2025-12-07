; expect: 5
section .text
    global _start

_start:
    mov rcx, 5
    mov rax, 0
.my_loop:
    inc rax
    loop .my_loop

    mov rdi, rax
    mov rax, 60
    syscall
