; expect: 1
section .text
global _start

_start:
    mov rax, 10
    test rax, rax     ; Check sign
    jns .no_sign      ; jump if not sign, should jump
    mov rdi, 0
    jmp .done

.no_sign:
    mov rdi, 1

.done:
    mov rax, 60
    syscall
