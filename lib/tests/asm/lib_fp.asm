section .data
one: dq 0x3ff0000000000000 ; 1.0

section .text
global _start

_start:
lea rsi, [one]
movsd xmm0, [rsi]
addsd xmm0, xmm0 ; 2.0
cvtsd2si rax, xmm0 ; 2
mov rdi, rax
mov rax, 60
syscall
; expect: 2