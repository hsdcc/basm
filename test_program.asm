section .text
global _start

_start:
    mov rax, 1      ; sys_write
    mov rdi, 1      ; stdout
    mov rsi, msg    ; message
    mov rdx, 13     ; length
    syscall         ; call kernel
    
    mov rax, 60     ; sys_exit
    mov rdi, 0      ; status
    syscall         ; call kernel

section .data
msg db "Hello, World!", 10  ; message with newline