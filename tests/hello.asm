section .data
    msg db "hello world", 10    ; string + newline
    len equ $ - msg             ; length of string

section .text
    global _start

_start:
    mov rax, 1                  ; syscall: write
    mov rdi, 1                  ; file descriptor: stdout
    mov rsi, msg                ; pointer to message
    mov rdx, len                ; message length
    syscall                     ; invoke syscall

    mov rax, 60                 ; syscall: exit
    xor rdi, rdi                ; exit code 0
    syscall

