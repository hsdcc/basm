; expect: 0
section .text
global _start

_start:
  mov rax, 5
  cmp rax, 5
  setne al
  movzx rax, al
  mov rdi, rax
  mov rax, 60
  syscall
