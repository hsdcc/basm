; chmod <path> <mode_dec> — set file permissions, exit 0 on success, 1 on error
section .text
global _start
_start:
	pop rcx
	cmp rcx, 3
	jne error
	pop rcx
	pop r14
	pop rdi
	call parse_uint64
	mov rsi, rax
	mov rdi, r14
	mov rax, 90
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
parse_uint64:
	xor eax, eax
.pu_loop:
	movzx rcx, byte [rdi]
	test rcx, rcx
	je .pu_done
	sub rcx, 0x30
	cmp rcx, 9
	ja error
	imul rax, rax, 10
	add rax, rcx
	inc rdi
	jmp .pu_loop
.pu_done:
	ret
