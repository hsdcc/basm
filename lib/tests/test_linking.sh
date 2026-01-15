#!/usr/bin/env bash

# Comprehensive test suite for linking functionality

source "$(dirname "$0")/../basm.lib.sh"

test_basic_linking() {
    echo "	testing basic linking functionality"
    
    # Create a simple object file
    local asm1="section .text
_start:
    mov rax, 1
    mov rdi, 1
    mov rsi, msg
    mov rdx, 5
    syscall
    ret

section .data
msg: db \"hello\", 0"
    
    local obj1
    obj1="$(mktemp).o"
    local exe1
    exe1="$(mktemp)"
    
    if ! basm_assemble "$asm1" "$obj1" "obj"; then
        echo "	[FAIL] basic_linking: failed to create first object file"
        rm -f "$obj1" "$exe1"
        return 1
    fi
    
    # Test linking single object to executable
    if ! link_objects "$obj1" "$exe1"; then
        echo "	[FAIL] basic_linking: failed to link single object file"
        rm -f "$obj1" "$exe1"
        return 1
    fi
    
    if [[ ! -f "$exe1" ]]; then
        echo "	[FAIL] basic_linking: executable not created"
        rm -f "$obj1" "$exe1"
        return 1
    fi
    
    echo "	[PASS] basic_linking"
    rm -f "$obj1" "$exe1"
    return 0
}

test_multiple_object_linking() {
    echo "	testing multiple object file linking"
    
    # Create first object file
    local asm1="section .text
_start:
    mov rax, 1
    call function1
    ret

function1:
    mov rax, 42
    ret"
    
    # Create second object file with referenced function
    local asm2="section .text
function2:
    mov rbx, 10
    ret"
    
    local obj1 obj2 exe
    obj1="$(mktemp).o"
    obj2="$(mktemp).o"
    exe="$(mktemp)"
    
    if ! basm_assemble "$asm1" "$obj1" "obj"; then
        echo "	[FAIL] multiple_object_linking: failed to create first object file"
        rm -f "$obj1" "$obj2" "$exe"
        return 1
    fi
    
    if ! basm_assemble "$asm2" "$obj2" "obj"; then
        echo "	[FAIL] multiple_object_linking: failed to create second object file"
        rm -f "$obj1" "$obj2" "$exe"
        return 1
    fi
    
    # Test linking multiple objects
    if ! link_objects "$obj1" "$obj2" "$exe"; then
        echo "	[FAIL] multiple_object_linking: failed to link multiple object files"
        rm -f "$obj1" "$obj2" "$exe"
        return 1
    fi
    
    if [[ ! -f "$exe" ]]; then
        echo "	[FAIL] multiple_object_linking: executable not created"
        rm -f "$obj1" "$obj2" "$exe"
        return 1
    fi
    
    echo "	[PASS] multiple_object_linking"
    rm -f "$obj1" "$obj2" "$exe"
    return 0
}

test_invalid_object_file() {
    echo "	testing invalid object file handling"
    
    # Create a fake file that isn't an object file
    local fake_file
    fake_file="$(mktemp)"
    echo "not_an_object_file" > "$fake_file"
    
    local exe
    exe="$(mktemp)"
    
    # Test linking with invalid object file
    if link_objects "$fake_file" "$exe"; then
        echo "	[FAIL] invalid_object_file: should have failed with invalid object file"
        rm -f "$fake_file" "$exe"
        return 1
    fi
    
    echo "	[PASS] invalid_object_file"
    rm -f "$fake_file" "$exe"
    return 0
}

# Run tests
test_basic_linking || exit 1
test_multiple_object_linking || exit 1
test_invalid_object_file || exit 1

echo "All linking tests passed!"