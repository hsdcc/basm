; readelf_hex <file> <skip> <count>
; rbx=fd r12=skip r13=count r14=path

section .rodata
hex_chars: db "0123456789abcdef"

section .text
global _start
_start:
	pop rcx
	cmp rcx, 4
	jne error

	pop rcx
	pop r14
	pop rdi
	call parse_uint64
	mov r12, rax

	pop rdi
	call parse_uint64
	mov r13, rax

	test r13, r13
	je success

	mov rax, 2
	mov rdi, r14
	xor esi, esi
	xor edx, edx
	syscall
	test rax, rax
	js error
	mov rbx, rax

	mov rax, 8
	mov rdi, rbx
	mov rsi, r12
	xor edx, edx
	syscall
	test rax, rax
	js error

	sub rsp, 16
.loop:
	xor eax, eax
	mov rdi, rbx
	mov rsi, rsp
	mov edx, 1
	syscall
	test rax, rax
	jl error
	je done

	movzx rcx, byte [rsp]
	lea rsi, [hex_chars]

	mov rax, rcx
	shr rax, 4
	and rax, 0xf
	mov al, [rsi + rax]
	mov [rsp], al

	mov rax, rcx
	and rax, 0xf
	mov al, [rsi + rax]
	mov [rsp+1], al

	mov eax, 1
	mov edi, 1
	mov rsi, rsp
	mov edx, 2
	syscall

	dec r13
	jne .loop

done:
	add rsp, 16
	jmp success

error:
	mov edi, 1
	mov eax, 60
	syscall

success:
	xor edi, edi
	mov eax, 60
	syscall

; rdi=input -> rax=value, err->error, clobbers rdi rcx
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
	jo error
	add rax, rcx
	inc rdi
	jmp .pu_loop
.pu_done:
	ret
