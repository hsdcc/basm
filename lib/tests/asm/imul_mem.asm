section .data
val: dq 20
section .text
global _start
_start:
    mov rax, 10
    lea rbx, [val]
    imul rax, [rbx]
    cmp rax, 200
    jne fail
    xor rdi, rdi
    jmp ok
fail:
    mov rdi, 1
ok:
    mov rax, 60
    syscall
; expect: 0
