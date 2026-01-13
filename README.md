# basm - x86_64 assembler in bash

an x86_64 assembler and linker written completely in bash

## usage

```bash
./src/basm.sh [input] [output]
```

by default, output is a.out

### examples

```bash
# assemble and link hello.asm to executable
./src/basm.sh lib/tests/asm/hello.asm

# assemble with custom output name
./src/basm.sh lib/tests/asm/hello.asm myprogram
```

## supported instructions

The assembler supports the following x86_64 instructions:

### Data movement
- `mov reg, reg` - move register to register
- `mov reg, imm64` - move 64-bit immediate to register
- `mov reg, imm32` - move 32-bit immediate to register
- `mov reg, [mem]` - move from memory to register
- `mov [mem], reg` - move from register to memory
- `movzx reg, reg` - zero-extend move
- `movsx reg, reg` - sign-extend move
- `movsxd reg, reg` - sign-extend 32-bit to 64-bit
- `lea reg, [mem]` - load effective address

### Arithmetic
- `add reg, reg` - add register to register
- `add reg, imm32` - add 32-bit immediate to register
- `sub reg, reg` - subtract register from register
- `sub reg, imm32` - subtract 32-bit immediate from register
- `imul reg, reg` - integer multiply register by register
- `mul reg` - unsigned multiply
- `div reg` - unsigned divide
- `idiv reg` - signed divide
- `inc reg` - increment register
- `dec reg` - decrement register
- `neg reg` - negate register
- `not reg` - bitwise NOT register

### Logic
- `and reg, reg` - bitwise AND register with register
- `and reg, imm32` - bitwise AND register with 32-bit immediate
- `or reg, reg` - bitwise OR register with register
- `or reg, imm32` - bitwise OR register with 32-bit immediate
- `xor reg, reg` - bitwise XOR register with register (use `xor reg, reg` for clearing)
- `test reg, reg` - test register against register
- `test reg, imm32` - test register against immediate

### Shift/Rotate
- `shl reg, imm8` - shift left
- `shr reg, imm8` - shift right (logical)
- `sar reg, imm8` - shift right (arithmetic)

### Control flow
- `jmp label` - unconditional jump
- `je label` - jump if equal (zero)
- `jne label` - jump if not equal (non-zero)
- `jg label` - jump if greater (signed)
- `jl label` - jump if less (signed)
- `jge label` - jump if greater or equal (signed)
- `jle label` - jump if less or equal (signed)
- `ja label` - jump if above (unsigned)
- `jb label` - jump if below (unsigned)
- `jae label` - jump if above or equal (unsigned)
- `jbe label` - jump if below or equal (unsigned)
- `jo label` - jump if overflow
- `jno label` - jump if no overflow
- `js label` - jump if sign
- `jns label` - jump if no sign
- `cmp reg, reg` - compare register with register
- `cmp reg, imm32` - compare register with immediate
- `call label` - call subroutine
- `ret` - return from subroutine
- `loop label` - loop while rcx != 0
- `loope label` - loop while rcx != 0 and zf = 1
- `loopne label` - loop while rcx != 0 and zf = 0

### Conditional move
- `cmove reg, reg` - conditional move if equal
- `cmovne reg, reg` - conditional move if not equal
- `cmova reg, reg` - conditional move if above (unsigned)
- `cmovae reg, reg` - conditional move if above or equal
- `cmovb reg, reg` - conditional move if below
- `cmovbe reg, reg` - conditional move if below or equal
- `cmovg reg, reg` - conditional move if greater (signed)
- `cmovge reg, reg` - conditional move if greater or equal
- `cmovl reg, reg` - conditional move if less
- `cmovle reg, reg` - conditional move if less or equal
- `cmovo reg, reg` - conditional move if overflow
- `cmovno reg, reg` - conditional move if no overflow
- `cmovs reg, reg` - conditional move if sign
- `cmovns reg, reg` - conditional move if no sign
- `cmovp reg, reg` - conditional move if parity
- `cmovnp reg, reg` - conditional move if no parity

### Set instructions
- `sete reg` - set if equal
- `setne reg` - set if not equal
- `seta reg` - set if above
- `setae reg` - set if above or equal
- `setb reg` - set if below
- `setbe reg` - set if below or equal
- `setg reg` - set if greater
- `setge reg` - set if greater or equal
- `setl reg` - set if less
- `setle reg` - set if less or equal
- `seto reg` - set if overflow
- `setno reg` - set if no overflow
- `sets reg` - set if sign
- `setns reg` - set if no sign

### Stack operations
- `push reg` - push register to stack
- `pop reg` - pop from stack to register

### Floating-point
- `movss xmm, xmm` - move single precision
- `movsd xmm, xmm` - move double precision
- `movsd xmm, [mem]` - move double precision from memory
- `addss xmm, xmm` - add single precision
- `addsd xmm, xmm` - add double precision
- `subss xmm, xmm` - subtract single precision
- `subsd xmm, xmm` - subtract double precision
- `mulss xmm, xmm` - multiply single precision
- `mulsd xmm, xmm` - multiply double precision
- `divss xmm, xmm` - divide single precision
- `divsd xmm, xmm` - divide double precision
- `cvtsd2si reg, xmm` - convert double to signed integer

### System
- `syscall` - system call
- `nop` - no operation
- `cdqe` - convert doubleword to quadword
- `cqo` - convert quadword to octword (sign extend rax to rdx:rax)
- `leave` - leave procedure (equivalent to mov rsp, rbp; pop rbp)
- `ret` - return

## data directives
- `db "string"` - define byte string
- `dq number` - define quadword (64-bit value)
- `equ $-label` - define equ with offset calculation

## testing

run the built-in tests:

```bash
./src/basm.sh test
```

<details>
<summary>philosophy</summary>

the core assembler uses pure bash - no external tools like sed, awk, grep, cat, etc. you may only use bash built-ins for processing: regex matching with bash built-ins, number processing with bash arithmetic, hex conversion with printf.

the only exceptions are core system operations like rm, mv, chmod, and the tests which can use external tools.
