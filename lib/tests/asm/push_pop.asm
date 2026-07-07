section .data
val: dq 0
section .text
global _start
_start:
    push 42
    pop rax
    cmp rax, 42
    jne fail
    push 1000
    pop rax
    cmp rax, 1000
    jne fail
    lea rbx, [val]
    push 99
    pop [rbx]
    mov rax, [rbx]
    cmp rax, 99
    jne fail
    push [rbx]
    pop rax
    cmp rax, 99
    jne fail
    xor rdi, rdi
    jmp ok
fail:
    mov rdi, 1
ok:
    mov rax, 60
    syscall
; expect: 0
