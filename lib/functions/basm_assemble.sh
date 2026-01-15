#!/usr/bin/env bash

basm_assemble() {
    local code_str="${1:-""]}"
    local outfile="${2:-a.out}"

    # perform first pass: parse instructions, calculate sizes, collect labels
    local lines
    if ! first_pass lines "$code_str"; then
        return 1
    fi

    base_vaddr=0x400000
    file_text_off=0x200 # increased to avoid header overflow
    code_size=$text_bytes_len
    data_size=$((${#data_bytes} / 2))
    file_data_off=$((file_text_off + code_size))
    text_vaddr=$((base_vaddr + file_text_off))
    data_vaddr=$((base_vaddr + file_data_off))
    entry_vaddr=$text_vaddr
    if [[ -n "${labels[_start]:-}" ]]; then
        entry_vaddr=$((text_vaddr + labels[_start]))
    fi

    # perform second pass: generate machine code hex for each instruction
    if ! second_pass text_ins; then
        return 1
    fi

    # build elf header
    local header_hex
    header_hex=$(build_elf_header $entry_vaddr $file_text_off $text_vaddr $data_size $file_data_off)

    # calculate expected total size: header + padding + text + data
    local text_size data_size
    text_size=$((${#text_hex} / 2))
    data_size=$((${#data_bytes} / 2))
    
    write_final_executable "$header_hex" "$text_hex" "$data_bytes" "$file_text_off" "$text_size" "$data_size" "$file_data_off" "$outfile"
    
    return 0
}