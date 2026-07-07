section .text
global _start
_start:
    sub rsp, 120

    ; Initialize array at [rsp]: 10, 20, 30, 40, 50
    mov qword [rsp], 10
    mov qword [rsp+8], 20
    mov qword [rsp+16], 30
    mov qword [rsp+24], 40
    mov qword [rsp+32], 50

    ; Test 1: [base + index*scale] — access array[idx] with 8-byte elements
    lea rsi, [rsp]
    mov rcx, 2         ; index = 2
    mov rax, [rsi + rcx*8]  ; should load 30
    cmp rax, 30
    jne fail

    ; Test 2: [base + index*scale - disp]
    lea rsi, [rsp+32]  ; point to last element (50)
    mov rcx, 1         ; index = 1
    mov rax, [rsi + rcx*8 - 16]  ; rsp+32+8-16 = rsp+24 = 40
    cmp rax, 40
    jne fail

    ; Test 3: [base + index] (no scale, no disp)
    lea rsi, [rsp+32]
    mov rax, 0
    mov rcx, 0
    mov rax, [rsi + rcx]  ; should load 50
    cmp rax, 50
    jne fail

    ; Test 4: LEA with SIB: lea rax, [rsi + rcx*8]
    lea rsi, [rsp]
    mov rcx, 3
    lea rax, [rsi + rcx*8]  ; rax = rsp + 24
    mov rax, [rax]           ; load value at rsp+24 = 40
    cmp rax, 40
    jne fail

    ; All passed
    xor rdi, rdi
    jmp ok
fail:
    mov rdi, 1
ok:
    add rsp, 120
    mov rax, 60
    syscall
; expect: 0
