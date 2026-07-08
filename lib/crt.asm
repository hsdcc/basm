; Minimal CRT: entry point calling main(argc, argv)
section .text
global _start
extern main

_start:
	mov rdi, [rsp]		; argc
	lea rsi, [rsp+8]	; argv
	call main
	mov edi, eax
	mov eax, 60
	syscall
