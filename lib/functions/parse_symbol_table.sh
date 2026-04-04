#!/usr/bin/env bash

# parse symbol and string tables
parse_symbol_table() {
    local file_path="$1"
    local symtab_offset="$2"
    local symtab_size="$3"
    local symtab_ref="$4"
    local -n symtab_n="$4"
    local symtab_hex=""
    read_file_hex "$file_path" "$symtab_offset" "$symtab_size" "symtab_hex"
    symtab_n=()
    local entry_count=$((symtab_size / 24))
    for ((entry_idx = 0; entry_idx < entry_count; entry_idx++)); do
        local offset=$((entry_idx * 48))
        local st_name_hex="${symtab_hex:$offset:8}"
        local st_name=""
        for ((i = 6; i >= 0; i -= 2)); do
            st_name+="${st_name_hex:$i:2}"
        done
        local st_name_val=$((16#$st_name))
        local st_info_hex="${symtab_hex:$((offset + 8)):2}"
        local st_info=$((16#$st_info_hex))
        local st_other_hex="${symtab_hex:$((offset + 10)):2}"
        local st_other=$((16#$st_other_hex))
        local st_shndx_hex="${symtab_hex:$((offset + 12)):4}"
        local st_shndx=""
        for ((i = 2; i >= 0; i -= 2)); do
            st_shndx+="${st_shndx_hex:$i:2}"
        done
        local st_shndx_val=$((16#$st_shndx))
        local st_value_hex="${symtab_hex:$((offset + 16)):16}"
        local st_value=""
        for ((i = 14; i >= 0; i -= 2)); do
            st_value+="${st_value_hex:$i:2}"
        done
        local st_value_val=$((16#$st_value))
        symtab_n+=("$st_name_val,$st_info,$st_shndx_val,$st_value_val")
    done
    return 0
}

read_string_table() {
    local file_path="$1"
    local strtab_offset="$2"
    local strtab_size="$3"
    local strings_ref="$4"
    local -n strings_n="$4"
    local strtab_hex=""
    read_file_hex "$file_path" "$strtab_offset" "$strtab_size" "strtab_hex"
    strings_n=()
    local current_str=""
    for ((i = 0; i < ${#strtab_hex}; i += 2)); do
        local byte_hex="${strtab_hex:$i:2}"
        if [[ "$byte_hex" == "00" ]]; then
            [[ -n "$current_str" ]] && strings_n+=("$current_str")
            current_str=""
        else
            local byte_val=$((16#$byte_hex))
            ((byte_val >= 32 && byte_val < 127)) && current_str+=$(printf "\\$(printf '%03o' "$byte_val")")
        fi
    done
    return 0
}

get_elf_symbols() {
    local file_path="$1"
    local symbols_ref="$2"
    local definitions_ref="$3"
    local -n symbols_n="$2"
    local -n definitions_n="$3"
    symbols_n=()
    definitions_n=()
    local header_prefix="current"
    if ! parse_elf_header "$file_path" "$header_prefix"; then
        return 1
    fi
    local shoff num_sections shstrndx
    shoff="${current_shoff}"
    num_sections="${current_num_sections}"
    shstrndx="${current_shstrndx}"
    local _ges_sections
    parse_section_headers "$file_path" "$shoff" "$num_sections" "_ges_sections" || return 1
    local strtable_offset=0 strtable_size=0
    local symtable_offset=0 symtable_size=0
    local symtab_strtab_link=0
    for ((i=0; i<num_sections; i++)); do
        IFS=',' read -r sec_name sec_type sec_offset sec_size <<< "${_ges_sections[$i]}"
        if [[ $sec_type -eq 2 ]]; then
            symtable_offset=$sec_offset
            symtable_size=$sec_size
            local shdr_start=$((shoff + i * 64))
            read_u32le "$file_path" "$((shdr_start + 40))" "symtab_strtab_link"
            break
        fi
    done
    for ((i=0; i<num_sections; i++)); do
        if [[ $i -eq $symtab_strtab_link ]]; then
            IFS=',' read -r sec_name sec_type sec_offset sec_size <<< "${_ges_sections[$i]}"
            strtable_offset=$sec_offset
            strtable_size=$sec_size
            break
        fi
    done
    if [[ $symtable_offset -eq 0 ]] || [[ $strtable_size -eq 0 ]]; then
        return 1
    fi
    local symtab_entries
    parse_symbol_table "$file_path" "$symtable_offset" "$symtable_size" "symtab_entries" || return 1
    local strtab_hex=""
    read_file_hex "$file_path" "$strtable_offset" "$strtable_size" "strtab_hex"
    for sym_entry in "${symtab_entries[@]}"; do
        IFS=',' read -r st_name st_info st_shndx st_value <<< "$sym_entry"
        [[ $st_name -eq 0 ]] && continue
        local sym_name=""
        local pos=$((st_name * 2))
        while ((pos + 1 < ${#strtab_hex})); do
            local byte_hex="${strtab_hex:$pos:2}"
            [[ "$byte_hex" == "00" ]] && break
            local byte_val=$((16#$byte_hex))
            ((byte_val >= 32 && byte_val < 127)) && sym_name+=$(printf "\\$(printf '%03o' "$byte_val")")
            pos=$((pos + 2))
        done
        if [[ -n "$sym_name" ]]; then
            if [[ $st_shndx -gt 0 ]]; then
                definitions_n["$sym_name"]="$st_shndx:$st_value"
                symbols_n["$sym_name"]="defined:$st_shndx:$st_value"
            else
                symbols_n["$sym_name"]="undefined"
            fi
        fi
    done
    return 0
}
