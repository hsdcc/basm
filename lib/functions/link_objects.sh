#!/usr/bin/env bash

# link object files into executable
link_objects() {
    local objects=("$@")
    local output_file="${objects[-1]}"
    unset 'objects[-1]'
    if [[ ${#objects[@]} -lt 1 ]]; then
        error_msg "need at least one object file to link"
        return 1
    fi
    if [[ ${#objects[@]} -eq 1 ]]; then
        if ! is_elf_object "${objects[0]}"; then
            error_msg "file is not a proper ELF object file: ${objects[0]}"
            return 1
        fi
        cp "${objects[0]}" "$output_file"
        chmod +x "$output_file"
        return 0
    fi
    for obj_file in "${objects[@]}"; do
        if [[ ! -f "$obj_file" ]]; then
            error_msg "object file does not exist: $obj_file"
            return 1
        fi
        if ! is_elf_object "$obj_file"; then
            error_msg "file is not a proper ELF object file: $obj_file"
            return 1
        fi
    done
    declare -A resolved_symbols=()
    declare -a unresolved_symbols=()
    if ! resolve_symbols "objects" "resolved_symbols" "unresolved_symbols"; then
        error_msg "failed to resolve symbols"
        return 1
    fi
    if [[ ${#unresolved_symbols[@]} -gt 0 ]]; then
        error_msg "linking failed: undefined symbols: ${unresolved_symbols[*]}"
        return 1
    fi
    local combined_text=""
    local combined_data=""
    if ! combine_sections "objects" "combined_text" "combined_data"; then
        error_msg "failed to combine sections"
        return 1
    fi
    local text_size=$((${#combined_text} / 2))
    local data_size=$((${#combined_data} / 2))
    local file_text_off=0x200
    local file_data_off=$((file_text_off + text_size))
    local text_vaddr=0x400000+file_text_off
    local entry_vaddr=$text_vaddr
    local header_hex
    header_hex=$(build_elf_header "$entry_vaddr" "$file_text_off" "$text_vaddr" "$data_size" "$file_data_off")
    write_final_executable "$header_hex" "$combined_text" "$combined_data" \
        "$file_text_off" "$text_size" "$data_size" "$file_data_off" "$output_file"
    return 0
}
