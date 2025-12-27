; expect: 1
section .text
global _start

_start:
    mov rax, 0x7fffffffffffffff
    add rax, 1        ; This will cause overflow
    jo .overflow       ; jump on overflow, should jump
    mov rdi, 0
    jmp .done

.overflow:
    mov rdi, 1

.done:
    mov rax, 60
    syscall
