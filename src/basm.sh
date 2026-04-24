#!/usr/bin/env bash
set -u
prog="$0"
infile="${1:-}"
outfile="${2:-a.out}"
mode="${3:-exe}"
if [[ "$infile" == "test" ]]; then
	echo "running tests"
	bash src/test.sh
	exit $?
fi
if [[ -z "$infile" ]]; then
	echo "usage: $prog input.asm [output] [mode]" >&2
	echo "  input.asm - path to the assembly source file" >&2
	echo "  output    - optional executable output name (defaults to a.out)" >&2
	echo "  mode      - optional mode: exe or obj (defaults to exe)" >&2
	exit 1
fi
if [[ ! -f "$infile" ]]; then
	echo "error: input file '$infile' does not exist" >&2
	exit 1
fi
source "$(dirname "$0")/../lib/basm.lib.sh"
code=$(< "$infile")
basm_assemble "$code" "$outfile" "$mode"
echo "wrote $outfile"