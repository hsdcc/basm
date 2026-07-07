section .text
global _start
_start:
    sub rsp, 64

    ; Use times to emit repeated nops followed by code
    times 5 nop

    ; Verify: nop is 1 byte, 5 nops = 5 bytes, test continues at correct offset
    mov rax, 42
    cmp rax, 42
    jne fail

    xor rdi, rdi
    jmp ok
fail:
    mov rdi, 1
ok:
    add rsp, 64
    mov rax, 60
    syscall
; expect: 0
