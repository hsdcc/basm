; expect: 0
section .text
global _start

_start:
    mov rax, 5
    mov rbx, 10
    cmp rax, rbx
    ja .greater       ; unsigned greater, should NOT jump
    mov rdi, 0
    jmp .done

.greater:
    mov rdi, 1

.done:
    mov rax, 60
    syscall
