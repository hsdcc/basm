#!/usr/bin/env bash
# Test script for bcc compiler

echo "Testing bcc compiler..."

# Source the compiler library to use its functions directly
source ./bcc/lib/bcc.lib.sh

# Read the simple_hello.c file
input_file="./bcc/tests/simple_hello.c"
if [ ! -f "$input_file" ]; then
    echo "Error: $input_file does not exist"
    exit 1
fi

echo "Input C code:"
echo "============="
cat "$input_file"
echo ""

# Generate assembly from C code
echo "Generated Assembly:"
echo "=================="
generated_asm=$(bcc_compile_c_to_asm "$(cat $input_file)")
echo "$generated_asm"
echo ""

# Write the assembly to a temporary file
temp_asm=$(mktemp --suffix=.asm)
echo -n "$generated_asm" > "$temp_asm"

echo "Generated assembly file: $temp_asm"
echo ""

# Assemble using basm
output_binary=$(mktemp)
echo "Compiling assembly to binary..."
basm_assemble_from_file "$temp_asm" "$output_binary"

echo "Output binary: $output_binary"
echo ""

# Make it executable and run it
chmod +x "$output_binary"
echo "Running the program:"
echo "==================="
timeout 2s "$output_binary" 2>/dev/null || echo "(program completed or timed out)"

echo ""
echo "Test completed!"

# Cleanup
rm "$temp_asm" "$output_binary"