#!/usr/bin/env bash
# basm.sh
# tiny assembler+linker for intel x86_64 linux
set -u

prog="$0"
infile="${1:-}"
outfile="${2:-a.out}"

if [[ "$infile" == "test" ]]; then
	echo "running tests"
	if bash lib/tests/dynamic_test_basm_lib.sh; then
		echo "all tests passed. good job."
		exit 0
	else
		echo "tests failed."
		exit 1
	fi
fi

if [[ -z "$infile" ]]; then
	echo "usage: $prog input.asm [output]" >&2
	echo "  input.asm - path to the assembly source file" >&2
	echo "  output    - optional executable output name (defaults to a.out)" >&2
	exit 1
fi

if [[ ! -f "$infile" ]]; then
	echo "error: input file '$infile' does not exist" >&2
	exit 1
fi

source "$(dirname "$0")/../lib/basm.lib.sh"

code=$(< "$infile")
basm_assemble "$code" "$outfile"

echo "wrote $outfile"