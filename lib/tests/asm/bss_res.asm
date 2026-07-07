section .bss
buf1: resb 8
buf2: resq 2
buf3: resd 4
section .text
global _start
_start:
	; Test resb 8: zero-initialized, can write/read a qword
	lea rsi, [buf1]
	mov rax, [rsi]
	test rax, rax
	jne fail
	mov rax, 42
	mov [rsi], rax
	mov rax, [rsi]
	cmp rax, 42
	jne fail

	; Test resq 2: 16 bytes, zero-initialized
	lea rsi, [buf2]
	mov rax, [rsi]
	test rax, rax
	jne fail
	mov rax, [rsi+8]
	test rax, rax
	jne fail
	mov rax, 0x42
	mov [rsi], rax
	mov rax, [rsi]
	cmp rax, 0x42
	jne fail

	; Test resd 4: 16 bytes, zero-initialized
	lea rsi, [buf3]
	mov eax, [rsi]
	test eax, eax
	jne fail
	mov eax, [rsi+4]
	test eax, eax
	jne fail
	mov eax, [rsi+8]
	test eax, eax
	jne fail
	mov eax, [rsi+12]
	test eax, eax
	jne fail
	mov eax, 0xcafebabe
	mov [rsi], eax
	mov eax, [rsi]
	cmp eax, 0xcafebabe
	jne fail

	; All passed
	mov rax, 60
	xor rdi, rdi
	syscall
fail:
	mov rax, 60
	mov rdi, 1
	syscall
; expect: 0
