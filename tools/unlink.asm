; unlink <path> — remove file, exit 0 on success, 1 on error
section .text
global _start
_start:
	pop rcx
	cmp rcx, 2
	jne error
	pop rcx
	pop rdi
	mov rax, 87
	syscall
	test rax, rax
	js error
	xor edi, edi
	mov eax, 60
	syscall
error:
	mov edi, 1
	mov eax, 60
	syscall
