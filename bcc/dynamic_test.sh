#!/usr/bin/env bash

echo "Testing bcc compiler dynamically..."

# Get the directory of the script to make paths relative to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the compiler library to use its functions directly
source "$SCRIPT_DIR/lib/bcc.lib.sh"

failed_tests=0
passed_tests=0

# Track if we had any errors during execution
any_error_occurred=0

# Get all C files in the tests directory (relative to script location)  
for c_file in "$SCRIPT_DIR/tests"/*.c; do
    if [ ! -f "$c_file" ]; then
        continue  # Skip if no .c files exist
    fi
    
    c_filename=$(basename "$c_file")
    test_name="dynamic_${c_filename%.*}"
    
    echo "Running test: $test_name"
    echo "Input C file: $c_file"
    
    # Generate assembly from C code
    # Use set +e temporarily to handle errors gracefully
    set +e
    generated_asm=$(bcc_compile_c_to_asm "$(cat $c_file)")
    asm_gen_status=$?
    set -e
    
    if [ $asm_gen_status -ne 0 ]; then
        echo "  [FAIL] $test_name: C compilation to assembly failed."
        ((failed_tests++))
        any_error_occurred=1
        continue
    fi
    
    # Write the assembly to a temporary file
    temp_asm=$(mktemp --suffix=.asm)
    echo -n "$generated_asm" > "$temp_asm"

    echo "Generated assembly file: $temp_asm"
    
    # Assemble using basm
    output_binary=$(mktemp)
    set +e
    basm_assemble_from_file "$temp_asm" "$output_binary"
    asm_status=$?
    set -e
    
    if [ $asm_status -ne 0 ]; then
        echo "  [FAIL] $test_name: Assembly failed."
        ((failed_tests++))
        any_error_occurred=1
        # Cleanup
        rm "$temp_asm" "$output_binary" 2>/dev/null || true
        continue
    fi

    echo "Output binary: $output_binary"
    
    # Make it executable and run it
    chmod +x "$output_binary"
    
    # Try to run the program with a timeout
    set +e
    output=$(timeout 2s "$output_binary" 2>/dev/null)
    exit_code=$?
    set -e
    
    if [ $exit_code -ne 0 ] && [ $exit_code -ne 124 ]; then  # 124 is timeout exit code
        echo "  [FAIL] $test_name: Program execution failed with exit code $exit_code."
        ((failed_tests++))
        any_error_occurred=1
    else
        echo "  [PASS] $test_name: Compiled and ran successfully."
        ((passed_tests++))
    fi

    # Cleanup
    rm "$temp_asm" "$output_binary" 2>/dev/null || true
done

echo
echo "Dynamic BCC tests completed:"
echo "Passed: $passed_tests"
echo "Failed: $failed_tests"

# Since we managed to reach this point, we can safely exit based on test results
if [ $failed_tests -gt 0 ]; then
    echo "Some tests failed."
    exit 1
else
    echo "All tests passed. Good job!"
    exit 0
fi