# basm context

when working on basm code, you must follow these requirements:

## pure bash philosophy

the core assembler uses pure bash - no external tools like sed, awk, grep, cat, etc. you may only use bash built-ins for processing: regex matching with bash built-ins, number processing with bash arithmetic, hex conversion with printf.

the only exceptions are core system operations like rm, mv, chmod, and the tests which can use external tools.

## instruction definitions

instructions are defined in .def files with format:
`instruction,operands,opcode,size,encoding_type`

the system loads these definitions into associative arrays and uses them to encode instructions based on patterns.

## core components

- `basm.sh` - main entry point that takes input .asm and output file
- `basm.lib.sh` - core assembly logic with all the parsing and encoding
- `.def` files - instruction definitions that map assembly ops to machine code
