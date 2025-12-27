#!/usr/bin/env bash
set -u

source "$(dirname "$0")/../basm.lib.sh"

assert_exit_code() {
	local test_name="$1"
	local asm_file="$2"
	local expected_exit_code="$3"

	echo "	testing $test_name"

	local executable
	executable="$(mktemp)"

	local asm_code
	asm_code=$(< "$asm_file")

	if ! basm_assemble "$asm_code" "$executable"; then
		echo "	[FAIL] $test_name: asm failed."
		rm -f "$executable"
		return 1
	fi

	set +e
	"$executable"
	local actual_exit_code=$?
	set -e

	if (( actual_exit_code != expected_exit_code )); then
		echo "	[FAIL] $test_name: Exited with status code $actual_exit_code, expected $expected_exit_code."
		rm -f "$executable"
		return 1
	fi

	echo "	[PASS] $test_name"
	rm -f "$executable"
	return 0
}

assert_output() {
	local test_name="$1"
	local asm_file="$2"
	local expected_output="$3"

	echo "	testing $test_name"

	local executable
	executable="$(mktemp)"

	local asm_code
	asm_code=$(< "$asm_file")

	if ! basm_assemble "$asm_code" "$executable"; then
		echo "	[FAIL] $test_name: asm failed."
		rm -f "$executable"
		return 1
	fi

	local output
	output=$("$executable")

	if [[ "$output" != "$expected_output" ]]; then
		echo "	[FAIL] $test_name: unexpected output: '$output'"
		rm -f "$executable"
		return 1
	fi

	echo "	[PASS] $test_name"
	rm -f "$executable"
	return 0
}

# Function to extract expected value from asm file comment
get_expected_from_asm() {
	local asm_file="$1"
	local expected=$(head -n 5 "$asm_file" | grep -E '; expect:' | head -n 1 | sed 's/.*; expect:[[:space:]]*//' | sed 's/[[:space:]]*$//')
	echo "$expected"
}

# Function to get expected output for known files
get_expected_output_for_file() {
	local asm_filename="$1"
	case "$asm_filename" in
		"hello.asm")
			echo "hello world"
			;;
		"lib_hello.asm")
			echo "hello from lib"
			;;
		"lib_lea.asm")
			echo "a"
			;;
		*)
			echo ""	 # Unknown, no expected output
			;;
	esac
}

# Function to get expected exit code for known files
get_expected_exit_code_for_file() {
	local asm_filename="$1"
	case "$asm_filename" in
		"lib_add.asm")
			echo "15"
			;;
		"lib_sub.asm")
			echo "5"
			;;
		"lib_xor.asm")
			echo "0"
			;;
		"lib_je_taken.asm")
			echo "2"
			;;
		"lib_je_not_taken.asm")
			echo "1"
			;;
		"lib_jmp.asm")
			echo "42"
			;;
		"lib_inc_dec.asm")
			echo "11"
			;;
		"lib_and_or.asm")
			echo "3"
			;;
		"lib_call.asm")
			echo "42"
			;;
		"lib_mul.asm")
			echo "42"
			;;
		"lib_div.asm")
			echo "6"
			;;
		"lib_test.asm")
			echo "1"
			;;
		"lib_push_pop_all.asm")
			echo "1"
			;;
		"lib_imul.asm")
			echo "214"
			;;
		"lib_idiv.asm")
			echo "250"
			;;
		"lib_shift.asm")
			echo "4"
			;;
		"lib_neg.asm")
			echo "214"
			;;
		"lib_exit_42.asm")
			echo "42"
			;;
		*)
			echo ""	 # Unknown, no expected exit code
			;;
	esac
}

failed_tests=0
test_asm_dir="$(dirname "$0")"/asm

# Process all asm files in the test directory
for asm_file in "$test_asm_dir"/*.asm; do
	if [ ! -f "$asm_file" ]; then
		continue	# Skip if no .asm files exist
	fi
	
	asm_filename=$(basename "$asm_file")
	test_name="dynamic_${asm_filename%.*}"
	
	# Check if file has expected exit code in comment (new format)
	expected_value=$(get_expected_from_asm "$asm_file")
	
	if [[ -n "$expected_value" ]]; then
		# This file has an expected exit code in comment
		assert_exit_code "$test_name" "$asm_file" "$expected_value" || failed_tests=$((failed_tests + 1))
	else
		# Check if it's a known exit code file (original format)
		expected_exit_code=$(get_expected_exit_code_for_file "$asm_filename")
		if [ -n "$expected_exit_code" ]; then
			# Known file with expected exit code
			assert_exit_code "$test_name" "$asm_file" "$expected_exit_code" || failed_tests=$((failed_tests + 1))
		else
			# Check if it's a known output file
			expected_output=$(get_expected_output_for_file "$asm_filename")
			if [ -n "$expected_output" ]; then
				# Known file with expected output
				assert_output "$test_name" "$asm_file" "$expected_output" || failed_tests=$((failed_tests + 1))
			else
				# Unknown file, just run it to make sure it assembles and runs without crashing
				echo "	testing $test_name (basic run test)"
				executable="$(mktemp)"
				asm_code=$(< "$asm_file")
				
				if ! basm_assemble "$asm_code" "$executable"; then
					echo "	[FAIL] $test_name: asm failed."
					rm -f "$executable"
					failed_tests=$((failed_tests + 1))
					continue
				fi
				
				set +e
				"$executable" > /dev/null 2>&1
				exit_code=$?
				set -e
				
				if (( exit_code == 0 )); then
					echo "	[PASS] $test_name"
				else
					echo "	[FAIL] $test_name: exited with status $exit_code"
					failed_tests=$((failed_tests + 1))
				fi
				
				rm -f "$executable"
			fi
		fi
	fi
done

if (( failed_tests > 0 )); then
	echo
	echo "$failed_tests test(s) failed."
	exit 1
else
	echo
	echo "all tests passed. good job."
	exit 0
fi