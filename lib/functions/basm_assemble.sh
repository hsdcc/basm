#!/usr/bin/env bash

basm_assemble() {
    local code_str="${1:-""]}"
    local outfile="${2:-a.out}"
    local mode="${3:-exe}"
    local preprocessed_code
    if command -v preprocess_macros >/dev/null 2>&1; then
        preprocessed_code=$(preprocess_macros "$code_str" 2>/dev/null)
        if [[ $? -eq 0 && -n "$preprocessed_code" ]]; then
            code_str="$preprocessed_code"
        fi
    fi
    set_assembly_mode "$mode"
    if [[ "$mode" == "obj" ]]; then
        base_vaddr=0
        file_text_off=0
        text_vaddr=0
        data_vaddr=0
        entry_vaddr=0
    else
        base_vaddr=0x400000
        file_text_off=0x200
        text_vaddr=$((base_vaddr + file_text_off))
        entry_vaddr=$text_vaddr
    fi
    local lines
    if ! first_pass lines "$code_str"; then
        return 1
    fi
    code_size=$text_bytes_len
    data_size=$((${#data_bytes} / 2))
    rodata_size=$((${#rodata_bytes} / 2))
    bss_size=$((${#bss_bytes} / 2))
    file_data_off=$((file_text_off + code_size))
    file_rodata_off=$((file_data_off + data_size))
    file_bss_off=$((file_rodata_off + rodata_size))
    if [[ "$mode" != "obj" ]]; then
        data_vaddr=$((base_vaddr + file_text_off + code_size))
        if [[ -n "${labels[_start]:-}" ]]; then
            entry_vaddr=$((text_vaddr + labels[_start]))
        fi
    fi
    if ! second_pass text_ins; then
        return 1
    fi
    if [[ "$mode" == "obj" ]]; then
        generate_elf_object_with_symbols "$text_hex" "$data_bytes" "labels" "equs" "$outfile" "data_label_off" "relocations"
    else
        local header_hex
        header_hex=$(build_elf_header $entry_vaddr $file_text_off $text_vaddr $data_size $file_data_off)
        local text_size
        text_size=$((${#text_hex} / 2))
        data_size=$((${#data_bytes} / 2))
        write_final_executable "$header_hex" "$text_hex" "$data_bytes" "$file_text_off" "$text_size" "$data_size" "$file_data_off" "$outfile"
    fi
    return 0
}
