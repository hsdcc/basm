#!/usr/bin/env bash

# reverse hex string
reverse_endian() {
    local hex="$1"
    local len=${#hex}
    local reversed=""
    ((len % 2 != 0)) && { hex="0$hex"; len=$((len + 1)); }
    for ((i = len - 2; i >= 0; i -= 2)); do
        reversed+="${hex:$i:2}"
    done
    echo "$reversed"
}

generate_elf_object_with_symbols() {
    local text_hex="$1"
    local data_bytes="$2"
    local labels_ref="$3"
    local equs_ref="$4"
    local outfile="$5"
    local data_labels_ref="$6"
    local relocations_ref="$7"
    local externals_ref="$8"
    local -n labels_n="$3"
    local -n equs_n="$4"
    local -n data_labels_n="$6"
    local -n relocations_n="$7"
    local -n externals_n="$8"
    local text_size=$((${#text_hex} / 2))
    local data_size=$((${#data_bytes} / 2))
    local total_sections=7
    local header_size=64
    local text_section_off=$header_size
    local data_section_off=$((text_section_off + text_size))
    local rela_hex=""
    if [[ ${#relocations_n[@]} -gt 0 ]]; then
        generate_relocation_section "relocations_n" "labels_n" "data_labels_n" "rela_hex"
    fi
    local rela_size=$((${#rela_hex} / 2))
    local total_sections=6
    [[ $rela_size -gt 0 ]] && total_sections=7
    local symstrtab_hex="00"
    local current_str_offset=1
    for label_name in "${!labels_n[@]}"; do
        for ((ci = 0; ci < ${#label_name}; ci++)); do
            local ch="${label_name:$ci:1}"
            symstrtab_hex+=$(printf "%02x" "'$ch")
        done
        symstrtab_hex+="00"
        current_str_offset=$((current_str_offset + ${#label_name} + 1))
    done
    for label_name in "${!data_labels_n[@]}"; do
        for ((ci = 0; ci < ${#label_name}; ci++)); do
            local ch="${label_name:$ci:1}"
            symstrtab_hex+=$(printf "%02x" "'$ch")
        done
        symstrtab_hex+="00"
        current_str_offset=$((current_str_offset + ${#label_name} + 1))
    done
    for ext_name in "${!externals_n[@]}"; do
        for ((ci = 0; ci < ${#ext_name}; ci++)); do
            local ch="${ext_name:$ci:1}"
            symstrtab_hex+=$(printf "%02x" "'$ch")
        done
        symstrtab_hex+="00"
        current_str_offset=$((current_str_offset + ${#ext_name} + 1))
    done
    local symstrtab_size=$((${#symstrtab_hex} / 2))
    local num_symbols=1
    for label_name in "${!labels_n[@]}"; do
        num_symbols=$((num_symbols + 1))
    done
    for label_name in "${!data_labels_n[@]}"; do
        num_symbols=$((num_symbols + 1))
    done
    for ext_name in "${!externals_n[@]}"; do
        num_symbols=$((num_symbols + 1))
    done
    local symtab_size=$((num_symbols * 24))
    local shstrtab_hex="002e74657874002e64617461002e7368737472746162002e73796d746162002e73747274616200"
    local shstrtab_size=$((${#shstrtab_hex} / 2))
    local strtab_off=$((data_section_off + data_size))
    local symtab_off=$((strtab_off + symstrtab_size))
    local rela_off=$((symtab_off + symtab_size))
    local sec_header_table_off=$((rela_off + rela_size))
    local elf_header=""
    elf_header+="7f454c46"
    elf_header+="02"
    elf_header+="01"
    elf_header+="01"
    elf_header+="00"
    elf_header+="00"
    elf_header+="00000000000000"
    elf_header+="0100"
    elf_header+="3e00"
    elf_header+="01000000"
    elf_header+="0000000000000000"
    elf_header+="0000000000000000"
    local shoff_hex=$(printf "%016x" $sec_header_table_off)
    elf_header+=$(reverse_endian "$shoff_hex")
    elf_header+="00000000"
    elf_header+="4000"
    elf_header+="0000"
    elf_header+="0000"
    elf_header+="4000"
    local shnum_hex=$(printf "%04x" $total_sections)
    elf_header+=$(reverse_endian "$shnum_hex")
    local shstrndx_hex=$(printf "%04x" 3)
    elf_header+=$(reverse_endian "$shstrndx_hex")
    local symtab_content=""
    for ((i = 0; i < 24; i++)); do
        symtab_content+="00"
    done
    local sym_idx=1
    for label_name in "${!labels_n[@]}"; do
        local label_off=${labels_n[$label_name]}
        local str_offset=1
        local temp_str=$'\0'
        local found=0
        for temp_label in "${!labels_n[@]}"; do
            [[ "$temp_label" == "$label_name" ]] && { found=1; break; }
            temp_str+="$temp_label"
            temp_str+=$'\0'
            str_offset=$((str_offset + ${#temp_label} + 1))
        done
        for temp_label in "${!data_labels_n[@]}"; do
            temp_str+="$temp_label"
            temp_str+=$'\0'
            str_offset=$((str_offset + ${#temp_label} + 1))
        done
        local st_name_hex=$(printf "%08x" $str_offset)
        symtab_content+=$(reverse_endian "$st_name_hex")
        symtab_content+="10"
        symtab_content+="00"
        local shndx_hex=$(printf "%04x" 1)
        symtab_content+=$(reverse_endian "$shndx_hex")
        local value_hex=$(printf "%016x" $label_off)
        symtab_content+=$(reverse_endian "$value_hex")
        symtab_content+="0000000000000000"
        sym_idx=$((sym_idx + 1))
    done
    for label_name in "${!data_labels_n[@]}"; do
        local label_off=${data_labels_n[$label_name]}
        local str_offset=1
        local temp_str=$'\0'
        local found=0
        for temp_label in "${!labels_n[@]}"; do
            temp_str+="$temp_label"
            temp_str+=$'\0'
            str_offset=$((str_offset + ${#temp_label} + 1))
        done
        for temp_label in "${!data_labels_n[@]}"; do
            [[ "$temp_label" == "$label_name" ]] && { found=1; break; }
            temp_str+="$temp_label"
            temp_str+=$'\0'
            str_offset=$((str_offset + ${#temp_label} + 1))
        done
        local st_name_hex=$(printf "%08x" $str_offset)
        symtab_content+=$(reverse_endian "$st_name_hex")
        symtab_content+="10"
        symtab_content+="00"
        local shndx_hex=$(printf "%04x" 2)
        symtab_content+=$(reverse_endian "$shndx_hex")
        local value_hex=$(printf "%016x" $label_off)
        symtab_content+=$(reverse_endian "$value_hex")
        symtab_content+="0000000000000000"
        sym_idx=$((sym_idx + 1))
    done
    for ext_name in "${!externals_n[@]}"; do
        local str_offset=1
        for temp_label in "${!labels_n[@]}"; do
            str_offset=$((str_offset + ${#temp_label} + 1))
        done
        for temp_label in "${!data_labels_n[@]}"; do
            str_offset=$((str_offset + ${#temp_label} + 1))
        done
        for temp_label in "${!externals_n[@]}"; do
            [[ "$temp_label" == "$ext_name" ]] && break
            str_offset=$((str_offset + ${#temp_label} + 1))
        done
        local st_name_hex=$(printf "%08x" $str_offset)
        symtab_content+=$(reverse_endian "$st_name_hex")
        symtab_content+="10"
        symtab_content+="00"
        local shndx_hex=$(printf "%04x" 0)
        symtab_content+=$(reverse_endian "$shndx_hex")
        symtab_content+="0000000000000000"
        symtab_content+="0000000000000000"
        sym_idx=$((sym_idx + 1))
    done
    local section_headers=""
    for ((i = 0; i < 64; i++)); do
        section_headers+="00"
    done
    local sh_name_hex=$(printf "%08x" 1)
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="01000000"
    local sh_flags_hex=$(printf "%016x" $((0x6)))
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"
    local sh_offset_hex=$(printf "%016x" $text_section_off)
    section_headers+=$(reverse_endian "$sh_offset_hex")
    local sh_size_hex=$(printf "%016x" $text_size)
    section_headers+=$(reverse_endian "$sh_size_hex")
    section_headers+="00000000"
    section_headers+="00000000"
    local sh_addralign_hex=$(printf "%016x" 16)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    section_headers+="0000000000000000"
    sh_name_hex=$(printf "%08x" 7)
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="01000000"
    sh_flags_hex=$(printf "%016x" $((0x3)))
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"
    sh_offset_hex=$(printf "%016x" $data_section_off)
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" $data_size)
    section_headers+=$(reverse_endian "$sh_size_hex")
    section_headers+="00000000"
    section_headers+="00000000"
    sh_addralign_hex=$(printf "%016x" 8)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    section_headers+="0000000000000000"
    sh_name_hex=$(printf "%08x" 13)
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="03000000"
    sh_flags_hex=$(printf "%016x" 0)
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"
    local shstrtab_actual_off=$((sec_header_table_off + (total_sections * 64)))
    sh_offset_hex=$(printf "%016x" $shstrtab_actual_off)
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" $shstrtab_size)
    section_headers+=$(reverse_endian "$sh_size_hex")
    section_headers+="00000000"
    section_headers+="00000000"
    sh_addralign_hex=$(printf "%016x" 1)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    section_headers+="0000000000000000"
    sh_name_hex=$(printf "%08x" 23)
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="02000000"
    sh_flags_hex=$(printf "%016x" 0)
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"
    sh_offset_hex=$(printf "%016x" $symtab_off)
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" $symtab_size)
    section_headers+=$(reverse_endian "$sh_size_hex")
    local link_idx_hex=$(printf "%08x" 5)
    section_headers+=$(reverse_endian "$link_idx_hex")
    section_headers+="00000000"
    sh_addralign_hex=$(printf "%016x" 8)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    local entsize_hex=$(printf "%016x" 24)
    section_headers+=$(reverse_endian "$entsize_hex")
    sh_name_hex=$(printf "%08x" 31)
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="03000000"
    sh_flags_hex=$(printf "%016x" 0)
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"
    sh_offset_hex=$(printf "%016x" $strtab_off)
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" $symstrtab_size)
    section_headers+=$(reverse_endian "$sh_size_hex")
    section_headers+="00000000"
    section_headers+="00000000"
    sh_addralign_hex=$(printf "%016x" 1)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    section_headers+="0000000000000000"
    if [[ $rela_size -gt 0 ]]; then
        sh_name_hex=$(printf "%08x" 39)
        section_headers+=$(reverse_endian "$sh_name_hex")
        section_headers+="04000000"
        sh_flags_hex=$(printf "%016x" 0)
        section_headers+=$(reverse_endian "$sh_flags_hex")
        section_headers+="0000000000000000"
        sh_offset_hex=$(printf "%016x" $rela_off)
        section_headers+=$(reverse_endian "$sh_offset_hex")
        sh_size_hex=$(printf "%016x" $rela_size)
        section_headers+=$(reverse_endian "$sh_size_hex")
        local rela_link_hex=$(printf "%08x" 4)
        section_headers+=$(reverse_endian "$rela_link_hex")
        local rela_info_hex=$(printf "%08x" 1)
        section_headers+=$(reverse_endian "$rela_info_hex")
        sh_addralign_hex=$(printf "%016x" 8)
        section_headers+=$(reverse_endian "$sh_addralign_hex")
        local rela_entsize_hex=$(printf "%016x" 24)
        section_headers+=$(reverse_endian "$rela_entsize_hex")
    fi
    local tmpf
    tmpf="$(mktemp)" || { error_msg "failed to create temporary file"; return 1; }
    hex_to_bin "$elf_header" >"$tmpf"
    hex_to_bin "$text_hex" >>"$tmpf"
    hex_to_bin "$data_bytes" >>"$tmpf"
    hex_to_bin "$symstrtab_hex" >>"$tmpf"
    hex_to_bin "$symtab_content" >>"$tmpf"
    [[ $rela_size -gt 0 ]] && hex_to_bin "$rela_hex" >>"$tmpf"
    hex_to_bin "$section_headers" >>"$tmpf"
    hex_to_bin "$shstrtab_hex" >>"$tmpf"
    chmod 644 "$tmpf"
    mv -f "$tmpf" "$outfile"
    return 0
}
