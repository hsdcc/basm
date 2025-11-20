#!/usr/bin/env bash
# bcc.sh
# tiny C compiler for intel x86_64 linux (using basm assembler)
set -eu

prog="$0"
infile="${1:-}"
outfile="${2:-a.out}"

if [ "$infile" = "test" ]; then
  echo "running tests"
  # Add tests here later
  # if bash lib/tests/test_bcc_lib.sh; then
  #   echo "all tests passed. good job."
  #   exit 0
  # else
  #   echo "tests failed."
  #   exit 1
  # fi
  exit 0
fi

if [ -z "$infile" ]; then
  echo "usage: $prog input.c output" >&2
  exit 1
fi

# Source our C compiler library (which also sources basm.lib.sh)
source "$(dirname "$0")/../lib/bcc.lib.sh"

code=$(< "$infile")
# Parse C code and generate assembly
assembly=$(bcc_compile_c_to_asm "$code")
# Write assembly to a temporary file
temp_asm=$(mktemp --suffix=.asm)
echo -n "$assembly" > "$temp_asm"

# Assemble the generated assembly using basm's assembler
basm_assemble_from_file "$temp_asm" "$outfile"

# Clean up temp file
rm "$temp_asm"

echo "compiled $infile to $outfile"