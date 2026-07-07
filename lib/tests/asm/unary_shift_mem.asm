; test inc/dec/neg/not/shl/shr/sar with memory operand
section .data
val: dq 10

section .text
global _start
_start:
    lea rbx, [val]

    ; inc [rbx] -> val = 11
    inc [rbx]
    mov rax, [rbx]
    cmp rax, 11
    jne fail

    ; dec [rbx] -> val = 10
    dec [rbx]
    mov rax, [rbx]
    cmp rax, 10
    jne fail

    ; neg [rbx] -> val = -10 = 0xfffffffffffffff6
    neg [rbx]
    mov rax, [rbx]
    ; check by adding 10: should be 0
    add rax, 10
    test rax, rax
    jne fail

    ; reset to 10
    mov rax, 10
    mov [rbx], rax

    ; not [rbx] -> val = ~10
    not [rbx]
    mov rax, [rbx]
    not rax
    cmp rax, 10
    jne fail

    ; reset to 8
    mov rax, 8
    mov [rbx], rax

    ; shl [rbx], 1 -> val = 16
    shl [rbx], 1
    mov rax, [rbx]
    cmp rax, 16
    jne fail

    ; shr [rbx], 2 -> val = 4
    shr [rbx], 2
    mov rax, [rbx]
    cmp rax, 4
    jne fail

    ; reset to -8 using neg trick
    mov rax, 8
    mov [rbx], rax
    neg [rbx]  ; val = -8

    ; sar [rbx], 1 -> val = -4
    sar [rbx], 1
    mov rax, [rbx]
    ; check by adding 4: should be 0
    add rax, 4
    test rax, rax
    jne fail

    xor rdi, rdi
    jmp ok
fail:
    mov rdi, 1
ok:
    mov rax, 60
    syscall
; expect: 0
