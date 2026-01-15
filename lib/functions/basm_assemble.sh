#!/usr/bin/env bash

basm_assemble() {
    local code_str="${1:-""]}"
    local outfile="${2:-a.out}"
    local mode="${3:-exe}"  # exe or obj

    # Set global assembly mode
    set_assembly_mode "$mode"

    # For object files, we need different address handling
    if [[ "$mode" == "obj" ]]; then
        # In object mode, use 0 as base addresses (relocatable)
        base_vaddr=0
        file_text_off=0
        text_vaddr=0
        data_vaddr=0
        entry_vaddr=0
    else
        # In executable mode, use traditional addresses
        base_vaddr=0x400000
        file_text_off=0x200 # increased to avoid header overflow
        text_vaddr=$((base_vaddr + file_text_off))
        entry_vaddr=$text_vaddr
    fi

    # perform first pass: parse instructions, calculate sizes, collect labels
    local lines
    if ! first_pass lines "$code_str"; then
        return 1
    fi

    # Calculate sizes after first pass
    code_size=$text_bytes_len
    data_size=$((${#data_bytes} / 2))
    file_data_off=$((file_text_off + code_size))

    if [[ "$mode" != "obj" ]]; then
        # Only calculate real addresses for executables
        data_vaddr=$((base_vaddr + file_text_off + code_size))
        if [[ -n "${labels[_start]:-}" ]]; then
            entry_vaddr=$((text_vaddr + labels[_start]))
        fi
    fi

    # perform second pass: generate machine code hex for each instruction
    if ! second_pass text_ins; then
        return 1
    fi

    if [[ "$mode" == "obj" ]]; then
        # Generate object file with proper sections
        generate_elf_object_with_symbols "$text_hex" "$data_bytes" "labels" "equs" "$outfile"
    else
        # build elf header for executable
        local header_hex
        header_hex=$(build_elf_header $entry_vaddr $file_text_off $text_vaddr $data_size $file_data_off)

        # calculate expected total size: header + padding + text + data
        local text_size
        text_size=$((${#text_hex} / 2))
        data_size=$((${#data_bytes} / 2))
        
        write_final_executable "$header_hex" "$text_hex" "$data_bytes" "$file_text_off" "$text_size" "$data_size" "$file_data_off" "$outfile"
    fi
    
    return 0
}