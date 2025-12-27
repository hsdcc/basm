; expect: 3
section .text
global _start

_start:
  mov rax, 3
  mov rcx, rax
  xor rax, rax
.loop_start:
  add rax, rcx
  dec rcx
  loope .loop_start
  mov rdi, rax
  mov rax, 60
  syscall
