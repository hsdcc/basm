section .text
global _start
_start:
  mov rax, 0
  cmp rax, 0
  cmove rbx, rcx
  mov rax, 60
  xor rdi, rdi
  syscall