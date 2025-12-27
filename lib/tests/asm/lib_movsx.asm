; expect: 255
section .text
global _start

_start:
  mov rax, -1         ; Load -1 (0xff in AL as signed)
  movsx rcx, al       ; Sign-extend AL to RCX - should be -1 = 255 as exit code
  mov rax, 60
  mov rdi, rcx        ; Exit with RCX value
  syscall
