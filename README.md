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

## testing

run the built-in tests:

```bash
./src/basm.sh test
```

## developer documentation

<details>
<summary>philosophy</summary>

the core assembler uses pure bash - no external tools like sed, awk, grep, cat, etc. you may only use bash built-ins for processing: regex matching with bash built-ins, number processing with bash arithmetic, hex conversion with printf.

the only exceptions are core system operations like rm, mv, chmod, and the tests which can use external tools.

</details>

<details>
<summary>what's missing and what we need to work on</summary>

the current basm assembler supports basic x86_64 instructions sufficient for simple assembly programs and the existing test suite, but lacks the comprehensive instruction set needed for C compilation.

### missing instructions by category

**arithmetic (integer)**

- [ ] `imul r64, r64, imm32` - three operand form: `rdx ← rax * src`
- [ ] `imul r64, imm8/imm32` - sign-extended multiply to register
- [ ] `mulx` - unsigned multiply without affecting flags
- [ ] `adcx`, `adox` - extended precision addition with carry
- [ ] `shld`, `shrd` - double-precision shifts
- [ ] `bzhi`, `pdep`, `pext` - bit manipulation instructions
- [ ] `rorx`, `shlx`, `shrx` - new shift instructions

**floating point (sse/avx)**

- [ ] `addss`, `addsd` - add scalar single/double precision
- [ ] `subss`, `subsd` - subtract scalar single/double precision
- [ ] `mulss`, `mulsd` - multiply scalar single/double precision
- [ ] `divss`, `divsd` - divide scalar single/double precision
- [ ] `movss`, `movsd` - move scalar values
- [ ] `comiss`, `comisd` - compare scalar values
- [ ] `cvtsi2ss`, `cvtsi2sd` - convert integer to float/double
- [ ] `cvtss2sd`, `cvtsd2ss` - convert between float/double
- [ ] `cvttsd2si`, `cvttss2si` - truncate and convert to integer
- [ ] `vaddps`, `vaddpd`, `vsubps`, `vsubpd` - avx vector operations
- [ ] `vmulps`, `vmulpd`, `vdivps`, `vdivpd` - avx vector operations

**memory and addressing**

- [x] `movzx` - move with zero extension (byte/word to dword/qword)
- [x] `movsx` - move with sign extension
- [x] `movsxd` - move sign-extended dword to qword
- [ ] `lea r64, [base + index*scale + displacement]` - complex addressing modes
- [ ] `movsb`, `movsw`, `movsd`, `movsq` - string operations
- [ ] `stosb`, `stosw`, `stosd`, `stosq` - store string operations
- [ ] `cmpsb`, `cmpsw`, `cmpsd`, `cmpsq` - compare string operations
- [ ] `lodsb`, `lodsw`, `lodsd`, `lodsq` - load string operations

**control flow**

- [ ] `jecxz` - jump if ecx is zero
- [ ] `jrcxz` - jump if rcx is zero
- [ ] `cmovcc` - conditional moves (cmove, cmovne, cmova, cmovae, etc.)
- [ ] `setcc` - set byte on condition (sete, setne, seta, setae, etc.)
- [ ] `loop`, `loope`, `loopne` - loop instructions
- [ ] `syscall`, `sysret` - system call instructions
- [ ] `int`, `iret` - software interrupt instructions

**processor control**

- [ ] `cpuid` - cpu identification
- [ ] `rdtsc`, `rdtscp` - read time-stamp counter
- [ ] `rdmsr`, `wrmsr` - read/write model specific register
- [ ] `clflush` - cache line flush
- [ ] `mfence`, `lfence`, `sfence` - memory fences
- [ ] `pause` - spin loop hint

**system instructions**

- [ ] `lgdt`, `sgdt` - load/store global descriptor table
- [ ] `lidt`, `sidt` - load/store interrupt descriptor table
- [ ] `lldt`, `sldt` - load/store local descriptor table
- [ ] `ltr`, `str` - load/store task register
- [ ] `mov cr0, r64` - control register access
- [ ] `mov dr0, r64` - debug register access

**bit manipulation**

- [ ] `andn`, `bextr`, `blsi`, `blsmk`, `blsr` - bmi1 instructions
- [ ] `bzhi`, `mulx`, `pdep`, `pext`, `rorx`, `sarx`, `shlx`, `shrx` - bmi2 instructions
- [ ] `popcnt` - population count
- [ ] `lzcnt` - leading zero count
- [ ] `tzcnt` - trailing zero count
- [ ] `bts`, `btr`, `btc` - bit test and set/reset/complement
- [ ] `bt`, `bts`, `btr`, `btc` - with immediate addressing

### advanced addressing modes

**currently supported:**

- [x] register to register: `mov rax, rbx`
- [x] register to immediate: `mov rax, 42`
- [x] register to memory label: `mov rax, msg` (loads address)

**missing advanced addressing:**

- [ ] base + displacement: `mov rax, [rbx + 8]`
- [ ] base + index: `mov rax, [rbx + rcx]`
- [ ] base + index*scale: `mov rax, [rbx + rcx*4]`
- [ ] base + index*scale + displacement: `mov rax, [rbx + rcx*4 + 16]`
- [ ] rip-relative: `mov rax, [rip + offset]`

### system call interface

**missing:**

- [ ] linux system call interface implementation
- [ ] support for calling standard library functions
- [ ] position-independent code generation
- [ ] dynamic linking support

### data types and structures

**missing:**

- [ ] proper floating-point data type support
- [ ] array addressing modes
- [ ] structure member access
- [ ] union support
- [ ] enum support
- [ ] pointer arithmetic operations

### calling conventions

**system v abi (linux x86_64) support missing:**

- [ ] register parameter passing (rdi, rsi, rdx, rcx, r8, r9, xmm0-7)
- [ ] stack parameter passing (for >6 parameters)
- [ ] caller/callee saved registers
- [ ] stack alignment (16-byte boundary)
- [ ] red zone (128 bytes below rsp)
- [ ] return value handling
- [ ] function prologue/epilogue generation

### advanced compiler features

**missing:**

- [ ] optimized instruction selection
- [ ] dead code elimination
- [ ] register allocation
- [ ] loop optimization
- [ ] function inlining
- [ ] tail call optimization
- [ ] stack frame management
- [ ] exception handling (try/catch)
- [ ] debug information generation

### binary format features

**currently supported:**

- [x] basic elf header generation
- [x] text and data sections
- [x] simple relocation

**missing:**

- [ ] symbol table generation
- [ ] debug symbol support
- [ ] dynamic linking information
- [ ] section alignment
- [ ] string table support
- [ ] program headers for loaded sections
- [ ] dynamic section for shared library support
- [ ] position independent executable (pie) support

### error handling and diagnostics

**missing:**

- [ ] comprehensive instruction validation
- [ ] type checking
- [ ] range checking (for immediate values)
- [ ] undefined label detection
- [ ] assembly-time constant evaluation
- [ ] detailed error messages with line numbers
- [ ] warning system

### performance optimization

**missing:**

- [ ] instruction scheduling
- [ ] dead store elimination
- [ ] constant folding
- [ ] common subexpression elimination
- [ ] branch prediction optimization
- [ ] pipeline stall avoidance

</details>
