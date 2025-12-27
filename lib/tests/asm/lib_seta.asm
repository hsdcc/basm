; expect: 1
section .text
global _start

_start:
  mov rax, 10
  cmp rax, 5
  seta al
  movzx rax, al
  mov rdi, rax
  mov rax, 60
  syscall
