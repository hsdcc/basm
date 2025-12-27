; expect: 1
section .text
global _start

_start:
    mov rax, 10
    add rax, 5        ; This will NOT cause overflow
    jno .no_overflow  ; jump if not overflow, should jump
    mov rdi, 0
    jmp .done

.no_overflow:
    mov rdi, 1

.done:
    mov rax, 60
    syscall
