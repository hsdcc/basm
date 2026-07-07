; test push/pop with immediate and memory
section .data
val: dq 0

section .text
global _start
_start:
    lea rbx, [val]

    ; push imm8 (value within -128..127)
    push 42
    pop rax
    cmp rax, 42
    jne fail

    ; push imm32 (value outside -128..127)
    push 1000
    pop rax
    cmp rax, 1000
    jne fail

    ; push qword [mem] then pop to verify
    mov rax, 42
    mov [rbx], rax
    push qword [rbx]
    pop rax
    cmp rax, 42
    jne fail

    ; pop qword [mem]
    push 99
    pop qword [rbx]
    mov rax, [rbx]
    cmp rax, 99
    jne fail

    ; push qword [mem] with existing value
    push qword [rbx]
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
