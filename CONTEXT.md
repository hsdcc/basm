# basm context

basm is an x86_64 assembler and linker written completely in bash. it parses assembly code and outputs executable binaries.

## architecture

the system has these main components:

- `basm.sh` - main entry point that takes input .asm and output file
- `basm.lib.sh` - core assembly logic with all the parsing and encoding
- `.def` files - instruction definitions that map assembly ops to machine code

## instruction parsing

the assembler works in passes:

1. parse input for labels, data definitions, and instructions
2. calculate memory layout and addresses
3. encode instructions to machine code using definitions
4. build elf binary with headers, text, and data sections

## pure bash requirement

the core assembler uses pure bash - no external tools like sed, awk, grep, cat. regex matching with bash built-ins. number processing with bash arithmetic. hex conversion with printf.

the only exceptions are core system operations like rm, mv, chmod, and the tests which can use external tools.

## instruction definitions

instructions are defined in .def files with format:
`instruction,operands,opcode,size,encoding_type`

the system loads these definitions into associative arrays and uses them to encode instructions based on patterns.

## sections

supports .data and .text sections. data section for static values. text section for code. global directive for entry points.

## register mapping

rax=0, rcx=1, rdx=2, rbx=3, rsp=4, rbp=5, rsi=6, rdi=7
used to build modrm bytes for x86_64 encoding.

## elf output

creates proper elf64 binaries with program headers. base address at 0x400000. text section at 0x200 offset.