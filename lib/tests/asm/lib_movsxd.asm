; expect: 42
section .text
global _start

_start:
  mov rax, 42         ; Load 42 into RAX (32-bit: EAX)
  movsxd rcx, eax     ; Sign-extend EAX to RCX
  mov rax, 60
  mov rdi, rcx        ; Exit with RCX value
  syscall
