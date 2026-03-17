# basm - x86_64 assembler in bash

x86_64 assembler and linker written in bash

## usage

```bash
./src/basm.sh [input] [output]
```

output defaults to a.out

### examples

```bash
./src/basm.sh lib/tests/asm/hello.asm
./src/basm.sh lib/tests/asm/hello.asm myprogram
```

## testing

```bash
./src/basm.sh test
```

<details>
<summary>philosophy</summary>

core assembler uses pure bash - no external tools like sed, awk, grep, cat, etc. only bash built-ins: regex matching, arithmetic, printf for hex conversion.

exceptions: rm, mv, chmod, and tests which can use external tools.
</details>
