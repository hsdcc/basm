; expect: 1
section .text
global _start

_start:
    mov rax, -1
    test rax, rax     ; Check sign
    js .sign          ; jump if sign, should jump
    mov rdi, 0
    jmp .done

.sign:
    mov rdi, 1

.done:
    mov rax, 60
    syscall
