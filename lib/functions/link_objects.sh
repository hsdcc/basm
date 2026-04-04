#!/usr/bin/env bash

# static linker - combines multiple object files into a single executable with symbol resolution
link_objects() {
    local objects=("$@")  # Array of object file paths
    local output_file="${objects[-1]}"  # Last argument is the output file
    unset 'objects[-1]'  # Remove output file from the list

    if [[ ${#objects[@]} -lt 1 ]]; then
        error_msg "need at least one object file to link"
        return 1
    fi

    if [[ ${#objects[@]} -eq 1 ]]; then
        # If only one object file, verify it's a proper object file and copy it to output
        if ! is_elf_object "${objects[0]}"; then
            error_msg "file is not a proper ELF object file: ${objects[0]}"
            return 1
        fi
        cp "${objects[0]}" "$output_file"
        chmod +x "$output_file"
        return 0
    fi

    # Validate all object files
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

    # Resolve symbols - ensure all external references are satisfied
    declare -A resolved_symbols=()
    declare -a unresolved_symbols=()

    if ! resolve_symbols "objects" "resolved_symbols" "unresolved_symbols"; then
        error_msg "failed to resolve symbols"
        return 1
    fi

    # Check if all symbols are properly resolved
    if [[ ${#unresolved_symbols[@]} -gt 0 ]]; then
        error_msg "linking failed: undefined symbols: ${unresolved_symbols[*]}"
        return 1
    fi

    # Combine sections from all object files
    local combined_text=""
    local combined_data=""

    if ! combine_sections "objects" "combined_text" "combined_data"; then
        error_msg "failed to combine sections"
        return 1
    fi

    # Calculate sizes
    local text_size=$((${#combined_text} / 2))
    local data_size=$((${#combined_data} / 2))

    # Layout for executable: ELF header (0x40) + padding to 0x200 + .text + .data
    local file_text_off=0x200
    local file_data_off=$((file_text_off + text_size))
    local text_vaddr=0x400000+file_text_off
    local entry_vaddr=$text_vaddr

    # Find _start symbol offset within combined text to set entry point
    # _start should be at offset 0 in the first object file's .text section
    # For simplicity, entry point is the start of the .text section

    # Build ELF header for executable
    local header_hex
    header_hex=$(build_elf_header "$entry_vaddr" "$file_text_off" "$text_vaddr" "$data_size" "$file_data_off")

    # Write the final executable
    write_final_executable "$header_hex" "$combined_text" "$combined_data" \
        "$file_text_off" "$text_size" "$data_size" "$file_data_off" "$output_file"

    return 0
}