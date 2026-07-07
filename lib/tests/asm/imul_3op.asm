section .text
global _start
_start:
    mov rax, 10
    mov rbx, 20
    imul rax, rbx, 3
    cmp rax, 60
    jne fail
    xor rdi, rdi
    jmp ok
fail:
    mov rdi, 1
ok:
    mov rax, 60
    syscall
; expect: 0
