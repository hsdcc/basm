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

<details>
<summary>philosophy</summary>

the core assembler uses pure bash - no external tools like sed, awk, grep, cat, etc. you may only use bash built-ins for processing: regex matching with bash built-ins, number processing with bash arithmetic, hex conversion with printf.

the only exceptions are core system operations like rm, mv, chmod, and the tests which can use external tools.
