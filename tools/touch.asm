; touch <path> — create file atomically (O_CREAT|O_EXCL), exit 0 on success, 1 if exists/error
section .text
global _start
_start:
	pop rcx
	cmp rcx, 2
	jne error
	pop rcx
	pop rdi
	mov rax, 2
	mov rsi, 0xc2		; O_CREAT|O_EXCL|O_WRONLY
	mov rdx, 0x1b6
	syscall
	test rax, rax
	js error
	mov rdi, rax
	mov rax, 3
	syscall
	xor edi, edi
	mov eax, 60
	syscall
error:
	mov edi, 1
	mov eax, 60
	syscall
