#!/usr/bin/env bash

# parse elf header and extract key information
# usage: parse_elf_header <file_path> <output_var_prefix>
parse_elf_header() {
    local file_path="$1"
    local prefix="$2"

    # first check if this is actually an elf file
    if ! is_elf_object "$file_path"; then
        return 1
    fi

    # read e_shoff (bytes 40-47, 8 bytes little endian)
    local shoff
    read_u64le "$file_path" 40 "shoff"

    # read e_shnum (bytes 60-61, 2 bytes little endian)
    local num_sections
    read_u16le "$file_path" 60 "num_sections"

    # read e_shstrndx (bytes 62-63, 2 bytes little endian)
    local shstrndx
    read_u16le "$file_path" 62 "shstrndx"

    # set output variables with the given prefix
    eval "${prefix}_shoff=$shoff"
    eval "${prefix}_num_sections=$num_sections"
    eval "${prefix}_shstrndx=$shstrndx"

    return 0
}

# parse section headers from elf file
# usage: parse_section_headers <file_path> <shoff> <num_sections> <sections_array_ref>
parse_section_headers() {
    local file_path="$1"
    local shoff="$2"
    local num_sections="$3"
    local sections_ref="$4"
    local -n sections_n="$4"

    sections_n=()
    for ((sec_idx = 0; sec_idx < num_sections; sec_idx++)); do
        local offset=$((shoff + sec_idx * 64))

        # sh_name: offset 0-3 (4 bytes) - little endian
        local sh_name_val
        read_u32le "$file_path" "$offset" "sh_name_val"

        # sh_type: offset 4-7 (4 bytes) - little endian
        local sh_type_val
        read_u32le "$file_path" "$((offset + 4))" "sh_type_val"

        # sh_offset: offset 24-31 (8 bytes) - little endian
        local sh_off_val
        read_u64le "$file_path" "$((offset + 24))" "sh_off_val"

        # sh_size: offset 32-39 (8 bytes) - little endian
        local sh_size_val
        read_u64le "$file_path" "$((offset + 32))" "sh_size_val"

        sections_n+=("$sh_name_val,$sh_type_val,$sh_off_val,$sh_size_val")
    done

    return 0
}