section .data
val: dq 10
section .text
global _start
_start:
    lea rbx, [val]
    add [rbx], 5
    sub [rbx], 3
    mov rax, [rbx]
    cmp rax, 12
    jne fail
    and [rbx], 0xff
    mov rax, [rbx]
    cmp rax, 12
    jne fail
    mov rax, 60
    xor rdi, rdi
    syscall
fail:
    mov rax, 60
    mov rdi, 1
    syscall
; expect: 0
