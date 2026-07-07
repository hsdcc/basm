; test mul/div/idiv with memory operand
section .data
mval: dq 7

section .text
global _start
_start:
    lea rbx, [mval]

    ; mul qword [mem]  -> rax = 6 * 7 = 42
    mov rax, 6
    mul [rbx]
    cmp rax, 42
    jne fail

    ; div qword [mem]  -> rax = 42 / 7 = 6
    mov rax, 42
    mov rdx, 0
    div [rbx]
    cmp rax, 6
    jne fail

    mov rdi, 0
    jmp ok
fail:
    mov rdi, 1
ok:
    mov rax, 60
    syscall
; expect: 0
