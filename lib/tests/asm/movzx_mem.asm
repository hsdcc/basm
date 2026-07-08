section .text
global _start
_start:
    sub rsp, 32

    ; Set up test data
    mov byte [rsp], 0x80    ; 128 (will sign-extend to negative)
    mov byte [rsp+1], 0x42  ; 'B'
    mov word [rsp+2], 0x7fff

    ; Test movzx reg, byte [mem]
    movzx rax, byte [rsp+1]
    cmp rax, 0x42
    jne fail

    ; Test movsx reg, byte [mem]
    movsx rbx, byte [rsp]
    cmp rbx, -128
    jne fail

    ; Test movzx with [mem+disp] (simple)
    movzx rcx, byte [rsp+1]
    cmp rcx, 0x42
    jne fail

    xor rdi, rdi
    jmp ok
fail:
    mov rdi, 1
ok:
    add rsp, 32
    mov rax, 60
    syscall
; expect: 0
