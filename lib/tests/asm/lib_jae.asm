; expect: 1
section .text
global _start

_start:
    mov rax, 10
    mov rbx, 10
    cmp rax, rbx
    jae .above_eq    ; unsigned above or equal, should jump
    mov rdi, 0
    jmp .done

.above_eq:
    mov rdi, 1

.done:
    mov rax, 60
    syscall
