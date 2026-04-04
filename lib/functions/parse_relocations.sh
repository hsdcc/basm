#!/usr/bin/env bash

parse_relocations() {
    local file_path="$1"
    local output_ref="$2"
    local -n _pr_output="$2"
    _pr_output=()
    local header_prefix="pr"
    if ! parse_elf_header "$file_path" "$header_prefix"; then
        return 1
    fi
    local shoff num_sections shstrndx
    shoff="${pr_shoff}"
    num_sections="${pr_num_sections}"
    shstrndx="${pr_shstrndx}"
    local sections
    parse_section_headers "$file_path" "$shoff" "$num_sections" "sections" || return 1
    local shstrtab_offset=0
    local shstrtab_size=0
    for ((i = 0; i < num_sections; i++)); do
        IFS=',' read -r sec_name sec_type sec_off sec_size <<< "${sections[$i]}"
        if [[ $i -eq $shstrndx ]]; then
            shstrtab_offset=$sec_off
            shstrtab_size=$sec_size
            break
        fi
    done
    local shstrtab_hex=""
    read_file_hex "$file_path" "$shstrtab_offset" "$shstrtab_size" "shstrtab_hex"
    _pr_get_string() {
        local hex_str="$1"
        local str_offset="$2"
        local result=""
        local pos=$str_offset
        while ((pos + 1 < ${#hex_str})); do
            local byte_hex="${hex_str:$pos:2}"
            [[ "$byte_hex" == "00" ]] && break
            local byte_val=$((16#$byte_hex))
            ((byte_val >= 32 && byte_val < 127)) && result+=$(printf "\\$(printf '%03o' "$byte_val")")
            pos=$((pos + 2))
        done
        _pr_str_result="$result"
    }
    local symtab_off=0 symtab_size=0
    local strtab_off=0 strtab_size=0
    local rela_off=0 rela_size=0
    local symtab_idx=0
    for ((i = 0; i < num_sections; i++)); do
        IFS=',' read -r sec_name sec_type sec_off sec_size <<< "${sections[$i]}"
        if [[ $sec_type -eq 2 ]]; then
            symtab_off=$sec_off
            symtab_size=$sec_size
            symtab_idx=$i
        elif [[ $sec_type -eq 3 && $sec_off -ne 0 ]]; then
            local actual_name=""
            _pr_get_string "$shstrtab_hex" "$((sec_name * 2))"
            actual_name="$_pr_str_result"
            if [[ "$actual_name" == ".strtab" ]]; then
                strtab_off=$sec_off
                strtab_size=$sec_size
            fi
        elif [[ $sec_type -eq 4 ]]; then
            rela_off=$sec_off
            rela_size=$sec_size
        fi
    done
    [[ $rela_size -eq 0 ]] && return 0
    local strtab_hex=""
    read_file_hex "$file_path" "$strtab_off" "$strtab_size" "strtab_hex"
    local symtab_hex=""
    read_file_hex "$file_path" "$symtab_off" "$symtab_size" "symtab_hex"
    local rela_hex=""
    read_file_hex "$file_path" "$rela_off" "$rela_size" "rela_hex"
    local entry_count=$((rela_size / 24))
    for ((ei = 0; ei < entry_count; ei++)); do
        local offset=$((ei * 48))
        local r_off_hex="${rela_hex:$offset:16}"
        local r_off=""
        for ((i = 14; i >= 0; i -= 2)); do
            r_off+="${r_off_hex:$i:2}"
        done
        local r_offset_val=$((16#$r_off))
        local r_info_hex="${rela_hex:$((offset + 16)):16}"
        local r_info=""
        for ((i = 14; i >= 0; i -= 2)); do
            r_info+="${r_info_hex:$i:2}"
        done
        local r_info_val=$((16#$r_info))
        local sym_index=$((r_info_val >> 32))
        local r_type=$((r_info_val & 0xFFFFFFFF))
        local r_addend_hex="${rela_hex:$((offset + 32)):16}"
        local r_addend=""
        for ((i = 14; i >= 0; i -= 2)); do
            r_addend+="${r_addend_hex:$i:2}"
        done
        local r_addend_val=$((16#$r_addend))
        local sym_offset=$((sym_index * 48))
        local st_name_hex="${symtab_hex:$sym_offset:8}"
        local st_name=""
        for ((i = 6; i >= 0; i -= 2)); do
            st_name+="${st_name_hex:$i:2}"
        done
        local st_name_val=$((16#$st_name))
        local sym_name=""
        local pos=$((st_name_val * 2))
        while ((pos + 1 < ${#strtab_hex})); do
            local byte_hex="${strtab_hex:$pos:2}"
            [[ "$byte_hex" == "00" ]] && break
            local byte_val=$((16#$byte_hex))
            ((byte_val >= 32 && byte_val < 127)) && sym_name+=$(printf "\\$(printf '%03o' "$byte_val")")
            pos=$((pos + 2))
        done
        _pr_output+=("$r_offset_val:$sym_name:$r_type:$r_addend_val")
    done
    return 0
}
