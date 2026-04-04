#!/usr/bin/env bash

# parse symbol table from elf object file
# usage: parse_symbol_table <file_path> <symtab_offset> <symtab_size> <symtab_array_ref>
parse_symbol_table() {
    local file_path="$1"
    local symtab_offset="$2"
    local symtab_size="$3"
    local symtab_ref="$4"
    local -n symtab_n="$4"

    # read entire symbol table as hex
    local symtab_hex=""
    read_file_hex "$file_path" "$symtab_offset" "$symtab_size" "symtab_hex"

    symtab_n=()
    local entry_count=$((symtab_size / 24))

    for ((entry_idx = 0; entry_idx < entry_count; entry_idx++)); do
        local offset=$((entry_idx * 48))  # 24 bytes = 48 hex chars

        # st_name: offset 0-3 (4 bytes) - little endian
        local st_name_hex="${symtab_hex:$offset:8}"
        local st_name=""
        for ((i = 6; i >= 0; i -= 2)); do
            st_name+="${st_name_hex:$i:2}"
        done
        local st_name_val=$((16#$st_name))

        # st_info: offset 4-5 (1 byte)
        local st_info_hex="${symtab_hex:$((offset + 8)):2}"
        local st_info=$((16#$st_info_hex))

        # st_other: offset 6-7 (1 byte)
        local st_other_hex="${symtab_hex:$((offset + 10)):2}"
        local st_other=$((16#$st_other_hex))

        # st_shndx: offset 6-7 (2 bytes) - little endian
        local st_shndx_hex="${symtab_hex:$((offset + 12)):4}"
        local st_shndx=""
        for ((i = 2; i >= 0; i -= 2)); do
            st_shndx+="${st_shndx_hex:$i:2}"
        done
        local st_shndx_val=$((16#$st_shndx))

        # st_value: offset 8-15 (8 bytes) - little endian
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

# read string table from elf object file
# usage: read_string_table <file_path> <strtab_offset> <strtab_size> <strings_array_ref>
read_string_table() {
    local file_path="$1"
    local strtab_offset="$2"
    local strtab_size="$3"
    local strings_ref="$4"
    local -n strings_n="$4"

    # read entire string table as hex
    local strtab_hex=""
    read_file_hex "$file_path" "$strtab_offset" "$strtab_size" "strtab_hex"

    # split by null terminators
    strings_n=()
    local current_str=""
    for ((i = 0; i < ${#strtab_hex}; i += 2)); do
        local byte_hex="${strtab_hex:$i:2}"
        if [[ "$byte_hex" == "00" ]]; then
            if [[ -n "$current_str" ]]; then
                strings_n+=("$current_str")
                current_str=""
            fi
        else
            local byte_val=$((16#$byte_hex))
            if ((byte_val >= 32 && byte_val < 127)); then
                current_str+=$(printf "\\$(printf '%03o' "$byte_val")")
            fi
        fi
    done

    return 0
}

# get symbol names and information from elf file
# usage: get_elf_symbols <file_path> <symbols_assoc_array_ref> <definitions_assoc_array_ref>
get_elf_symbols() {
    local file_path="$1"
    local symbols_ref="$2"
    local definitions_ref="$3"  # will store symbols defined in this file
    local -n symbols_n="$2"
    local -n definitions_n="$3"
    
    # initialize associative arrays
    symbols_n=()
    definitions_n=()
    
    # first get elf header info
    local header_prefix="current"
    if ! parse_elf_header "$file_path" "$header_prefix"; then
        return 1
    fi
    
    local shoff num_sections shstrndx
    shoff="${current_shoff}"
    num_sections="${current_num_sections}"
    shstrndx="${current_shstrndx}"
    
    # get section headers
    local sections
    parse_section_headers "$file_path" "$shoff" "$num_sections" "sections" || return 1
    
    # find symbol table (.symtab) and string table (.strtab)
    # first get section header string table to find section names
    local shstrtab_sec_info="${sections[$shstrndx]}"
    IFS=',' read -r shstrtab_name shstrtab_type shstrtab_offset shstrtab_size <<< "$shstrtab_sec_info"
    
    local strtable_offset=0 strtable_size=0
    local symtable_offset=0 symtable_size=0
    local symtab_strtab_link=0  # sh_link field of symtab

    # look for .symtab section
    for ((i=0; i<num_sections; i++)); do
        IFS=',' read -r sec_name sec_type sec_offset sec_size <<< "${sections[$i]}"

        if [[ $sec_type -eq 2 ]]; then  # SHT_SYMTAB
            symtable_offset=$sec_offset
            symtable_size=$sec_size
            # read sh_link field (offset 40 in section header entry)
            # sh_link is at section_header_offset + 40, 4 bytes little endian
            local shdr_start=$((shoff + i * 64))
            read_u32le "$file_path" "$((shdr_start + 40))" "symtab_strtab_link"
            break
        fi
    done

    # find the string table section that symtab links to
    for ((i=0; i<num_sections; i++)); do
        if [[ $i -eq $symtab_strtab_link ]]; then
            IFS=',' read -r sec_name sec_type sec_offset sec_size <<< "${sections[$i]}"
            strtable_offset=$sec_offset
            strtable_size=$sec_size
            break
        fi
    done
    
    if [[ $symtable_offset -eq 0 ]] || [[ $strtable_size -eq 0 ]]; then
        # could not find symbol table or string table
        return 1
    fi
    
    # read symbol table
    local symtab_entries
    parse_symbol_table "$file_path" "$symtable_offset" "$symtable_size" "symtab_entries" || return 1
    
    # read string table as raw hex (for offset-based lookup)
    local strtab_hex=""
    read_file_hex "$file_path" "$strtable_offset" "$strtable_size" "strtab_hex"

    # process symbols
    for sym_entry in "${symtab_entries[@]}"; do
        IFS=',' read -r st_name st_info st_shndx st_value <<< "$sym_entry"

        # skip null symbol (index 0)
        if [[ $st_name -eq 0 ]]; then
            continue
        fi

        # get symbol name by reading string at byte offset in string table
        local sym_name=""
        local pos=$((st_name * 2))  # convert byte offset to hex offset
        while ((pos + 1 < ${#strtab_hex})); do
            local byte_hex="${strtab_hex:$pos:2}"
            if [[ "$byte_hex" == "00" ]]; then
                break
            fi
            local byte_val=$((16#$byte_hex))
            if ((byte_val >= 32 && byte_val < 127)); then
                sym_name+=$(printf "\\$(printf '%03o' "$byte_val")")
            fi
            pos=$((pos + 2))
        done

        if [[ -n "$sym_name" ]]; then
            # check if symbol is defined (not undefined/external)
            # in elf, section index 0 is undefined, >0 means defined in that section
            if [[ $st_shndx -gt 0 ]]; then
                definitions_n["$sym_name"]="$st_value"
                symbols_n["$sym_name"]="defined:$st_value"
            else
                # symbol is undefined (external reference)
                symbols_n["$sym_name"]="undefined"
            fi
        fi
    done
    
    return 0
}