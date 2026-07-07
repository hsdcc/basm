section .text
global _start
_start:
    mov eax, 42
    mov ebx, 10
    add eax, ebx
    mov edi, eax
    mov eax, 60
    syscall
; expect: 52