; expect: 1
section .text
global _start

_start:
    mov rax, 10
    mov rbx, 5
    cmp rax, rbx
    ja .greater       ; unsigned greater, should jump
    mov rdi, 0
    jmp .done

.greater:
    mov rdi, 1

.done:
    mov rax, 60
    syscall
