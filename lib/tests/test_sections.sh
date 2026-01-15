#!/usr/bin/env bash

# Test that the assembler supports multiple sections
# This test focuses on the basic functionality of section recognition

source "$(dirname "$0")/../basm.lib.sh"

# Test basic section support
test_multiple_sections() {
    local asm_code
    asm_code="section .text
_start:
    mov rax, 1
    mov rbx, msg
    ret

section .data
msg: dq 0x12345678

section .rodata
msg2: dq 0xabcdef99

section .bss
buffer: dq 10"

    local executable
    executable="$(mktemp)"
    
    if basm_assemble "$asm_code" "$executable"; then
        if [[ -f "$executable" ]]; then
            echo "	[PASS] multi-section support"
            rm -f "$executable"
            return 0
        else
            echo "	[FAIL] multi-section: executable not created"
            rm -f "$executable"
            return 1
        fi
    else
        echo "	[FAIL] multi-section: assembly failed"
        rm -f "$executable"
        return 1
    fi
}

# Test object file generation with multiple sections
test_multi_section_obj_generation() {
    local asm_code
    asm_code="section .text
_start:
    mov rax, 1
    mov rbx, msg
    ret

section .data
msg: dq 0x12345678

section .rodata
msg2: dq 0xabcdef99"

    local obj_file
    obj_file="$(mktemp).o"
    
    if basm_assemble "$asm_code" "$obj_file" "obj"; then
        if [[ -f "$obj_file" ]]; then
            # Check that it's an ELF file
            local file_type
            file_type=$(file "$obj_file" 2>/dev/null | grep -c "ELF.*relocatable" || echo "0")
            if [[ "$file_type" -gt 0 ]]; then
                echo "	[PASS] multi-section object generation"
                rm -f "$obj_file"
                return 0
            else
                echo "	[FAIL] multi-section object: not a proper ELF relocatable object file"
                rm -f "$obj_file"
                return 1
            fi
        else
            echo "	[FAIL] multi-section object: object file not created"
            rm -f "$obj_file"
            return 1
        fi
    else
        echo "	[FAIL] multi-section object: object generation failed"
        rm -f "$obj_file"
        return 1
    fi
}

echo "	testing multi-section support"
test_multiple_sections || exit 1

echo "	testing multi-section object file generation"
test_multi_section_obj_generation || exit 1

echo "	All section tests passed!"