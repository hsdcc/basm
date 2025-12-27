; expect: 255
section .text
global _start

_start:
  mov rax, 255        ; Load 255 into RAX (0xff in AL)
  movzx rcx, al       ; Zero-extend AL to RCX - should be 255
  mov rax, 60
  mov rdi, rcx        ; Exit with RCX value
  syscall
