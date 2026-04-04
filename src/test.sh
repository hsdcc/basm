#!/usr/bin/env bash
set -u

source "$(dirname "$0")/../lib/basm.lib.sh"

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

assert_object_generation() {
	local test_name="$1"
	local asm_code="$2"

	echo "	testing $test_name"

	local obj_file
	obj_file="$(mktemp).o"

	if ! basm_assemble "$asm_code" "$obj_file" "obj"; then
		echo "	[FAIL] $test_name: object generation failed."
		rm -f "$obj_file" 
		return 1
	fi

	# Check that it's a proper ELF object file
	if ! [[ -f "$obj_file" ]]; then
		echo "	[FAIL] $test_name: object file not created."
		rm -f "$obj_file"
		return 1
	fi

	# Check that it's an ELF file
	local file_type
	file_type=$(file "$obj_file" 2>/dev/null | grep -c "ELF.*relocatable" || echo "0")
	if [[ "$file_type" -eq 0 ]]; then
		echo "	[FAIL] $test_name: not a proper ELF relocatable object file."
		rm -f "$obj_file"
		return 1
	fi

	echo "	[PASS] $test_name"
	rm -f "$obj_file"
	return 0
}

# function to extract expected value from asm file comment
get_expected_from_asm() {
	local asm_file="$1"
	local expected=$(grep -E '; expect:' "$asm_file" | head -n 1 | sed 's/.*; expect:[[:space:]]*//' | sed 's/[[:space:]]*$//')
	echo "$expected"
}

# function to get expected output for known files
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

# function to get expected exit code for known files
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
test_asm_dir="$(dirname "$0")/../lib/tests/asm"

# process all asm files in the test directory
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

# test object file generation
assert_object_generation "object_generation_basic" "section .text
_start:
    mov rax, 1
    ret" || failed_tests=$((failed_tests + 1))

# test linking functionality
echo "	testing linking_basic"
asm1="section .text
_start:
    mov rax, 1
    mov rdi, 1
    mov rsi, msg
    mov rdx, 5
    syscall
    ret

section .data
msg: db \"hello\", 0"

obj1="$(mktemp).o"
exe1="$(mktemp)"

if ! basm_assemble "$asm1" "$obj1" "obj"; then
    echo "	[FAIL] linking_basic: failed to create object file"
    failed_tests=$((failed_tests + 1))
else
    if ! link_objects "$obj1" "$exe1"; then
        echo "	[FAIL] linking_basic: failed to link objects"
        failed_tests=$((failed_tests + 1))
    else
        if [[ ! -f "$exe1" ]]; then
            echo "	[FAIL] linking_basic: executable not created"
            failed_tests=$((failed_tests + 1))
        else
            echo "	[PASS] linking_basic"
        fi
    fi
fi

rm -f "$obj1" "$exe1"

# test linking multiple object files - sections are combined properly
# note: these tests use objects without cross-references to data sections,
# since full relocation support is not yet implemented
echo "	testing linking_multi_object"

# First object: contains _start and exits with code 42
asm_multi_1="section .text
    global _start
_start:
    mov rax, 60
    mov rdi, 42
    syscall"

# Second object: contains separate code (not called, but should be in the binary)
asm_multi_2="section .text
    global helper
helper:
    mov rax, 99
    ret"

obj_m1="$(mktemp).o"
obj_m2="$(mktemp).o"
exe_multi="$(mktemp)"

if ! basm_assemble "$asm_multi_1" "$obj_m1" "obj"; then
    echo "	[FAIL] linking_multi_object: failed to create first object file"
    failed_tests=$((failed_tests + 1))
elif ! basm_assemble "$asm_multi_2" "$obj_m2" "obj"; then
    echo "	[FAIL] linking_multi_object: failed to create second object file"
    failed_tests=$((failed_tests + 1))
elif ! link_objects "$obj_m1" "$obj_m2" "$exe_multi"; then
    echo "	[FAIL] linking_multi_object: failed to link objects"
    failed_tests=$((failed_tests + 1))
else
    if [[ ! -f "$exe_multi" ]]; then
        echo "	[FAIL] linking_multi_object: executable not created"
        failed_tests=$((failed_tests + 1))
    else
        set +e
        "$exe_multi"
        actual_exit=$?
        set -e
        if (( actual_exit != 42 )); then
            echo "	[FAIL] linking_multi_object: expected exit code 42, got $actual_exit"
            failed_tests=$((failed_tests + 1))
        else
            # Verify that the combined executable contains code from both objects
            # by checking the file size is reasonable (text from both objects combined)
            exe_size=$(wc -c < "$exe_multi")
            if (( exe_size >= 512 )); then
                echo "	[PASS] linking_multi_object (exe size: $exe_size bytes)"
            else
                echo "	[FAIL] linking_multi_object: executable too small ($exe_size bytes)"
                failed_tests=$((failed_tests + 1))
            fi
        fi
    fi
fi

rm -f "$obj_m1" "$obj_m2" "$exe_multi"

# test linking three object files
echo "	testing linking_three_objects"

asm_3a="section .text
    global _start
_start:
    mov rax, 60
    mov rdi, 7
    syscall"

asm_3b="section .text
    global func_b
func_b:
    mov rax, 1
    ret"

asm_3c="section .text
    global func_c
func_c:
    mov rax, 2
    ret"

obj_3a="$(mktemp).o"
obj_3b="$(mktemp).o"
obj_3c="$(mktemp).o"
exe_3="$(mktemp)"

if ! basm_assemble "$asm_3a" "$obj_3a" "obj" || \
   ! basm_assemble "$asm_3b" "$obj_3b" "obj" || \
   ! basm_assemble "$asm_3c" "$obj_3c" "obj"; then
    echo "	[FAIL] linking_three_objects: failed to create object files"
    failed_tests=$((failed_tests + 1))
elif ! link_objects "$obj_3a" "$obj_3b" "$obj_3c" "$exe_3"; then
    echo "	[FAIL] linking_three_objects: failed to link objects"
    failed_tests=$((failed_tests + 1))
else
    set +e
    "$exe_3"
    exit_code=$?
    set -e
    if (( exit_code != 7 )); then
        echo "	[FAIL] linking_three_objects: expected exit code 7, got $exit_code"
        failed_tests=$((failed_tests + 1))
    else
        echo "	[PASS] linking_three_objects"
    fi
fi

rm -f "$obj_3a" "$obj_3b" "$obj_3c" "$exe_3"

# test linking with objects containing data sections (data is combined but not relocated)
echo "	testing linking_with_data_sections"

asm_data_1="section .text
    global _start
_start:
    mov rax, 60
    mov rdi, 100
    syscall

section .data
msg1: db \"abc\", 0"

asm_data_2="section .text
    global unused_func
unused_func:
    ret

section .data
msg2: db \"xyz\", 0"

obj_d1="$(mktemp).o"
obj_d2="$(mktemp).o"
exe_data="$(mktemp)"

if ! basm_assemble "$asm_data_1" "$obj_d1" "obj" || \
   ! basm_assemble "$asm_data_2" "$obj_d2" "obj"; then
    echo "	[FAIL] linking_with_data_sections: failed to create object files"
    failed_tests=$((failed_tests + 1))
elif ! link_objects "$obj_d1" "$obj_d2" "$exe_data"; then
    echo "	[FAIL] linking_with_data_sections: failed to link objects"
    failed_tests=$((failed_tests + 1))
else
    set +e
    "$exe_data"
    actual_exit=$?
    set -e
    if (( actual_exit != 100 )); then
        echo "	[FAIL] linking_with_data_sections: expected exit code 100, got $actual_exit"
        failed_tests=$((failed_tests + 1))
    else
        # Verify data sections were combined
        data_size=$(wc -c < "$exe_data")
        if (( data_size > 512 )); then
            echo "	[PASS] linking_with_data_sections (exe size: $data_size bytes)"
        else
            echo "	[FAIL] linking_with_data_sections: executable too small ($data_size bytes)"
            failed_tests=$((failed_tests + 1))
        fi
    fi
fi

rm -f "$obj_d1" "$obj_d2" "$exe_data"

if (( failed_tests > 0 )); then
	echo
	echo "$failed_tests test(s) failed."
	exit 1
else
	echo
	echo "all tests passed. good job."
	exit 0
fi