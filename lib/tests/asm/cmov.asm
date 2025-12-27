; expect: 1
section .text
global _start
_start:
  mov rax, 0
  cmp rax, 0
  mov rbx, 0
  mov rcx, 1
  cmove rbx, rcx
  mov rax, 60
  mov rdi, rbx
  syscall