; expect: 1
section .text
global _start

_start:
    mov rax, 5
    mov rbx, 10
    cmp rax, rbx
    jb .below        ; unsigned below, should jump
    mov rdi, 0
    jmp .done

.below:
    mov rdi, 1

.done:
    mov rax, 60
    syscall
