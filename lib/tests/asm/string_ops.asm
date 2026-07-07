; test string operations
section .data
src: dq 0x4142434445464748
buf: dq 0
section .text
global _start
_start:
    lea rbx, [buf]
    lea rsi, [src]

    ; test stosb: store 'X' (0x58) to [buf]
    lea rdi, [buf]
    mov rax, 0x58
    cld
    stosb
    mov rax, [rbx]
    and rax, 0xff
    cmp rax, 0x58
    jne fail

    ; test stosq: store 0x0000beef to [buf]
    lea rdi, [buf]
    mov rax, 0x0000beef
    stosq
    mov rax, [rbx]
    cmp rax, 0x0000beef
    jne fail

    ; test lodsb: load byte from src
    lea rsi, [src]
    cld
    lodsb
    movzx rax, al
    cmp rax, 0x48
    jne fail

    ; test movsb: copy src[0] to buf
    lea rsi, [src]
    lea rdi, [buf]
    movsb
    mov rax, [rbx]
    and rax, 0xff
    cmp rax, 0x48
    jne fail

    ; test std then cld: direction flag
    std
    cld

    xor rdi, rdi
    jmp ok
fail:
    mov rdi, 1
ok:
    mov rax, 60
    syscall
; expect: 0
