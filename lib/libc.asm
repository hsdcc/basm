; Minimal libc for basm — syscall-based, no external deps
section .text

; putchar(int c) — write single char to stdout
global putchar
putchar:
	push rdi
	mov rsi, rsp
	mov rdi, 1		; stdout
	mov rdx, 1		; 1 byte
	mov eax, 1		; write
	syscall
	pop rdi
	ret

; puts(char *str) — write string + newline to stdout
global puts
puts:
	push rbx
	push rdi
	mov rbx, rdi
	call strlen
	mov rdx, rax		; length
	lea rsi, [rbx]		; string ptr
	mov rdi, 1		; stdout
	mov eax, 1		; write
	syscall
	; write newline
	push 10
	mov rsi, rsp
	mov rdi, 1
	mov rdx, 1
	mov eax, 1
	syscall
	add rsp, 8
	pop rdi
	pop rbx
	ret

; strlen(char *s) — return string length
global strlen
strlen:
	xor eax, eax
.s_loop:
	cmp byte [rdi+rax], 0
	je .s_done
	inc rax
	jmp .s_loop
.s_done:
	ret

; memset(void *s, int c, size_t n)
global memset
memset:
	mov rcx, rdx
	mov al, sil
	mov rdi, rdi
	rep stosb
	mov rax, rdi
	ret

; memcpy(void *dest, void *src, size_t n)
global memcpy
memcpy:
	mov rcx, rdx
	rep movsb
	mov rax, rdi
	ret

; exit(int code)
global exit
exit:
	mov eax, 60
	syscall

; malloc(size_t size) — allocate via mmap
global malloc
malloc:
	mov rsi, rdi		; size
	xor rdi, rdi		; addr = NULL
	mov rdx, 3		; PROT_READ|PROT_WRITE
	mov r10, 0x22		; MAP_PRIVATE|MAP_ANONYMOUS
	xor r8, r8		; fd = -1
	or r8, -1
	xor r9, r9		; offset = 0
	mov eax, 9		; mmap
	syscall
	cmp rax, -1
	je .m_fail
	ret
.m_fail:
	xor eax, eax
	ret

; free(void *ptr) — deallocate via munmap (note: needs size)
global free
free:
	; For simplicity, do nothing (leaks, but ok for small progs)
	ret
