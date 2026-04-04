#!/usr/bin/env bash

# parse elf header
parse_elf_header() {
    local file_path="$1"
    local prefix="$2"
    if ! is_elf_object "$file_path"; then
        return 1
    fi
    local shoff
    read_u64le "$file_path" 40 "shoff"
    local num_sections
    read_u16le "$file_path" 60 "num_sections"
    local shstrndx
    read_u16le "$file_path" 62 "shstrndx"
    eval "${prefix}_shoff=$shoff"
    eval "${prefix}_num_sections=$num_sections"
    eval "${prefix}_shstrndx=$shstrndx"
    return 0
}

parse_section_headers() {
    local file_path="$1"
    local shoff="$2"
    local num_sections="$3"
    local sections_ref="$4"
    local -n sections_n="$4"
    sections_n=()
    for ((sec_idx = 0; sec_idx < num_sections; sec_idx++)); do
        local offset=$((shoff + sec_idx * 64))
        local sh_name_val
        read_u32le "$file_path" "$offset" "sh_name_val"
        local sh_type_val
        read_u32le "$file_path" "$((offset + 4))" "sh_type_val"
        local sh_off_val
        read_u64le "$file_path" "$((offset + 24))" "sh_off_val"
        local sh_size_val
        read_u64le "$file_path" "$((offset + 32))" "sh_size_val"
        sections_n+=("$sh_name_val,$sh_type_val,$sh_off_val,$sh_size_val")
    done
    return 0
}
