# basm

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

## for people trying to contribute

[CONTEXT.MD](CONTEXT.MD)
