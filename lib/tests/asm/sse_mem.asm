; test SSE memory operations
section .data
a: dq 0x4004000000000000  ; 2.5 in double
b: dq 0x3ff8000000000000  ; 1.5 in double
ival: dq 42
result: dq 0

section .text
global _start
_start:
    lea rbx, [a]
    lea rcx, [b]
    lea rdx, [result]
    lea rsi, [ival]

    ; movsd from mem to xmm
    movsd xmm0, [rbx]
    ; movsd from xmm to mem
    movsd [rdx], xmm0

    ; movss from mem to xmm
    movss xmm1, [rbx]
    ; movss from xmm to mem
    movss [rdx], xmm1

    ; addsd with mem src
    movsd xmm0, [rbx]
    addsd xmm0, [rcx]
    movsd [rdx], xmm0

    ; subsd with mem src
    movsd xmm0, [rbx]
    subsd xmm0, [rcx]
    movsd [rdx], xmm0

    ; mulsd with mem src
    movsd xmm0, [rbx]
    mulsd xmm0, [rcx]
    movsd [rdx], xmm0

    ; divsd with mem src
    movsd xmm0, [rbx]
    divsd xmm0, [rcx]
    movsd [rdx], xmm0

    ; addss with mem src
    movss xmm0, [rbx]
    addss xmm0, [rcx]
    movss [rdx], xmm0

    ; subss with mem src
    movss xmm0, [rbx]
    subss xmm0, [rcx]
    movss [rdx], xmm0

    ; mulss with mem src
    movss xmm0, [rbx]
    mulss xmm0, [rcx]
    movss [rdx], xmm0

    ; divss with mem src
    movss xmm0, [rbx]
    divss xmm0, [rcx]
    movss [rdx], xmm0

    ; comiss / ucomiss with mem src
    movss xmm0, [rbx]
    comiss xmm0, [rcx]
    ucomiss xmm0, [rcx]

    ; comisd / ucomisd with mem src
    movsd xmm0, [rbx]
    comisd xmm0, [rcx]
    ucomisd xmm0, [rcx]

    ; cvtsi2sd with reg src
    mov rax, 42
    cvtsi2sd xmm0, rax

    ; cvtsi2ss with reg src
    cvtsi2ss xmm1, rax

    ; cvtsi2sd with mem src
    cvtsi2sd xmm0, [rsi]

    ; cvtsi2ss with mem src
    cvtsi2ss xmm1, [rsi]

    ; cvtss2si with reg src
    movss xmm0, [rbx]
    cvtss2si rax, xmm0

    ; cvtsd2si with reg src
    movsd xmm0, [rbx]
    cvtsd2si rax, xmm0

    ; cvtss2si with mem src
    cvtss2si rax, [rbx]

    ; cvtsd2si with mem src
    cvtsd2si rax, [rbx]

    xor rdi, rdi
    mov rax, 60
    syscall
; expect: 0
; expect: 0
