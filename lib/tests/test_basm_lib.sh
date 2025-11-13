#!/usr/bin/env bash
set -eu

source "$(dirname "$0")/../basm.lib.sh"

assert_exit_code() {
  local test_name="$1"
  local asm_file="$2"
  local expected_exit_code="$3"

  echo "  testing $test_name"

  local executable
  executable="$(mktemp)"

  local asm_code
  asm_code=$(< "$asm_file")

  if ! basm_assemble "$asm_code" "$executable"; then
    echo "  [FAIL] $test_name: asm failed."
    rm -f "$executable"
    return 1
  fi

  set +e
  "$executable"
  local actual_exit_code=$?
  set -e

  if [ "$actual_exit_code" -ne "$expected_exit_code" ]; then
    echo "  [FAIL] $test_name: Exited with status code $actual_exit_code, expected $expected_exit_code."
    rm -f "$executable"
    return 1
  fi

  echo "  [PASS] $test_name"
  rm -f "$executable"
  return 0
}

assert_output() {
  local test_name="$1"
  local asm_file="$2"
  local expected_output="$3"

  echo "  testing $test_name"

  local executable
  executable="$(mktemp)"

  local asm_code
  asm_code=$(< "$asm_file")

  if ! basm_assemble "$asm_code" "$executable"; then
    echo "  [FAIL] $test_name: asm failed."
    rm -f "$executable"
    return 1
  fi

  local output
  output=$("$executable")

  if [ "$output" != "$expected_output" ]; then
    echo "  [FAIL] $test_name: unexpected output: '$output'"
    rm -f "$executable"
    return 1
  fi

  echo "  [PASS] $test_name"
  rm -f "$executable"
  return 0
}

failed_tests=0
test_asm_dir="$(dirname "$0")"/asm

assert_output "lib_hello" "$test_asm_dir/lib_hello.asm" "hello from lib" || failed_tests=$((failed_tests + 1))
assert_exit_code "lib_exit_42" "$test_asm_dir/lib_exit_42.asm" 42 || failed_tests=$((failed_tests + 1))
assert_exit_code "lib_add" "$test_asm_dir/lib_add.asm" 15 || failed_tests=$((failed_tests + 1))
assert_exit_code "lib_sub" "$test_asm_dir/lib_sub.asm" 5 || failed_tests=$((failed_tests + 1))
assert_exit_code "lib_xor" "$test_asm_dir/lib_xor.asm" 0 || failed_tests=$((failed_tests + 1))
assert_exit_code "lib_je_taken" "$test_asm_dir/lib_je_taken.asm" 2 || failed_tests=$((failed_tests + 1))
assert_exit_code "lib_je_not_taken" "$test_asm_dir/lib_je_not_taken.asm" 1 || failed_tests=$((failed_tests + 1))
assert_exit_code "lib_jmp" "$test_asm_dir/lib_jmp.asm" 42 || failed_tests=$((failed_tests + 1))



if [ "$failed_tests" -gt 0 ]; then
  echo
  echo "$failed_tests test(s) failed."
  exit 1
else
  echo
  echo "all tests passed. good job."
  exit 0
fi
