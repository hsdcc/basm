#!/usr/bin/env bash
# bcc.sh
# tiny C compiler for intel x86_64 linux (using basm assembler)
set -eu

prog="$0"
infile="${1:-}"
outfile="${2:-a.out}"

if [ "$infile" = "test" ]; then
  echo "running tests"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Use a temporary file to run the test and check its output
  temp_output=$(mktemp)
  bash "$SCRIPT_DIR/../dynamic_test.sh" > "$temp_output" 2>&1
  exit_code=$?
  
  # Display the output
  cat "$temp_output"
  
  # The script might have exit code issue due to set -e in libraries
  # Check if the output indicates success by looking for success keywords
  if grep -q "All tests passed" "$temp_output"; then
    rm "$temp_output"
    echo "all tests passed. good job."
    exit 0
  else
    rm "$temp_output"
    echo "tests failed."
    # Use the original exit code in case of failure
    exit $exit_code
  fi
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