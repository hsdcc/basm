; expect: 1
section .text
global _start

_start:
    mov rax, 5
    mov rbx, 10
    cmp rax, rbx
    jbe .below_eq    ; unsigned below or equal, should jump
    mov rdi, 0
    jmp .done

.below_eq:
    mov rdi, 1

.done:
    mov rax, 60
    syscall
