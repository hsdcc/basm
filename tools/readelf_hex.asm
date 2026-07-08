; readelf_hex — read binary file region, output continuous hex
; Usage: readelf_hex <file> <skip> <count>
;
; Reads bytes one at a time via sys_read, converts each byte to
; two hex characters via lookup table (hex_chars in .rodata),
; writes hex pair to stdout via sys_write.  Exits 0 on success,
; 1 on any error (wrong args, file not found, read error, overflow).
;
; Register usage:
;   rbx = file descriptor
;   r12 = skip offset     (for lseek)
;   r13 = count remaining
;   r14 = file path       (argv[1], callee-saved across parse_uint64)

section .rodata
hex_chars: db "0123456789abcdef"

section .text
global _start
_start:
	; Parse command-line arguments
	pop rcx
	cmp rcx, 4
	jne error

	pop rcx			; discard argv[0] (program name)
	pop r14			; argv[1] = file path
	pop rdi			; argv[2] = skip string
	call parse_uint64
	mov r12, rax		; r12 = skip

	pop rdi			; argv[3] = count string
	call parse_uint64
	mov r13, rax		; r13 = count

	test r13, r13
	je success		; count == 0 => output nothing

	; sys_open(path, O_RDONLY)
	mov rax, 2
	mov rdi, r14
	xor esi, esi
	xor edx, edx
	syscall
	test rax, rax
	js error
	mov rbx, rax		; rbx = fd

	; sys_lseek(fd, skip, SEEK_SET)
	mov rax, 8
	mov rdi, rbx
	mov rsi, r12
	xor edx, edx
	syscall
	test rax, rax
	js error

	; 16 bytes scratch space on stack (more than enough)
	sub rsp, 16

.loop:
	; sys_read(fd, scratch, 1)
	xor eax, eax
	mov rdi, rbx
	mov rsi, rsp
	mov edx, 1
	syscall
	test rax, rax
	jl error		; read error (negative) => exit 1
	je done			; EOF (0) => exit 0

	; Convert byte to two hex chars
	movzx rcx, byte [rsp]
	lea rsi, [hex_chars]

	; High nibble: (byte >> 4) & 0xf -> lookup -> first hex char
	mov rax, rcx
	shr rax, 4
	and rax, 0xf
	mov al, [rsi + rax]
	mov [rsp], al

	; Low nibble: byte & 0xf -> lookup -> second hex char
	mov rax, rcx
	and rax, 0xf
	mov al, [rsi + rax]
	mov [rsp+1], al

	; sys_write(stdout, scratch, 2)
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

; Parse null-terminated decimal string to uint64
; Input:  rdi = pointer to decimal string
; Output: rax = value
; Errors: non-digit or overflow => jump to error (exit 1)
; Clobbers: rdi (advanced past consumed digits), rcx
parse_uint64:
	xor eax, eax		; result = 0
.pu_loop:
	movzx rcx, byte [rdi]
	test rcx, rcx		; null terminator -> done
	je .pu_done
	sub rcx, 0x30		; ASCII '0' = 0x30
	cmp rcx, 9
	ja error		; not a digit (or wraps unsigned >9)
	imul rax, rax, 10
	jo error		; overflow: value >= 2^64
	add rax, rcx
	inc rdi
	jmp .pu_loop
.pu_done:
	ret
