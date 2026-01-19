#!/usr/bin/env bash

# parse symbol table from elf object file
# usage: parse_symbol_table <file_path> <symtab_offset> <symtab_size> <symtab_array_ref>
parse_symbol_table() {
    local file_path="$1"
    local symtab_offset="$2"
    local symtab_size="$3"
    local symtab_ref="$4"
    local -n symtab_n="$4"
    
    local fd
    exec 7< "$file_path"
    
    # skip to symbol table
    for ((i=0; i<symtab_offset; i++)); do
        read -n1 -u 7 dummy_byte
    done
    
    # each symbol table entry is 24 bytes in elf64
    symtab_n=()
    local entry_count=$((symtab_size / 24))
    
    for ((entry_idx=0; entry_idx<entry_count; entry_idx++)); do
        # read the symbol table entry (24 bytes)
        local sym_entry=()
        for ((j=0; j<24; j++)); do
            read -n1 -u 7 sym_byte
            sym_entry+=("$sym_byte")
        done
        
        # extract fields:
        # st_name: offset 0-3 (4 bytes) - index into string table
        local st_name=0
        for ((i=0; i<4; i++)); do
            local byte_val
            byte_val=$(printf "%d" "'${sym_entry[$i]}")
            local shift=$((i * 8))
            st_name=$((st_name + (byte_val * (2 ** shift))))
        done
        
        # st_info: offset 4 (1 byte) - type and binding info
        local st_info
        st_info=$(printf "%d" "'${sym_entry[4]}")
        
        # st_shndx: offset 14-15 (2 bytes) - section index
        local st_shndx_low_byte st_shndx_high_byte
        st_shndx_low_byte="${sym_entry[14]}"
        st_shndx_high_byte="${sym_entry[15]}"
        
        local st_shndx_low_val st_shndx_high_val
        st_shndx_low_val=$(printf "%d" "'$st_shndx_low_byte")
        st_shndx_high_val=$(printf "%d" "'$st_shndx_high_byte")
        
        local st_shndx
        st_shndx=$((st_shndx_low_val + (st_shndx_high_val * 256)))
        
        # st_value: offset 8-15 (8 bytes) - symbol value/address
        local st_value=0
        for ((i=8; i<16; i++)); do
            local byte_val
            byte_val=$(printf "%d" "'${sym_entry[$i]}")
            local shift=$(((i - 8) * 8))
            st_value=$((st_value + (byte_val * (2 ** shift))))
        done
        
        # store symbol info
        symtab_n+=("$st_name,$st_info,$st_shndx,$st_value")
    done
    
    exec 7<&-
    
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
    
    local fd
    exec 8< "$file_path"
    
    # skip to string table
    for ((i=0; i<strtab_offset; i++)); do
        read -n1 -u 8 dummy_byte
    done
    
    # read the entire string table
    local raw_string=""
    for ((i=0; i<strtab_size; i++)); do
        read -n1 -u 8 char
        raw_string+="$char"
    done
    
    # split by null terminators
    strings_n=()
    IFS=$'\0' read -ra temp_strings <<< "$raw_string"
    
    # copy to named array
    for str in "${temp_strings[@]}"; do
        if [[ -n "$str" ]]; then
            strings_n+=("$str")
        fi
    done
    
    exec 8<&-
    
    return 0
}

# get symbol names and information from elf file
# usage: get_elf_symbols <file_path> <symbols_assoc_array_ref> <definitions_assoc_array_ref>
get_elf_symbols() {
    local file_path="$1"
    local symbols_ref="$2"
    local definitions_ref="$4"  # will store symbols defined in this file
    local -n symbols_n="$2"
    local -n definitions_n="$4"
    
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
    
    # look for .symtab and .strtab sections
    for ((i=0; i<num_sections; i++)); do
        IFS=',' read -r sec_name sec_type sec_offset sec_size <<< "${sections[$i]}"
        
        # get section name from section header string table
        # this would require reading the string table at shstrtab_offset
        # for simplification, we'll identify sections by their type
        if [[ $sec_type -eq 2 ]]; then  # sht_symtab
            symtable_offset=$sec_offset
            symtable_size=$sec_size
        elif [[ $sec_type -eq 3 ]]; then  # sht_strtab
            # for now, assume the string table associated with the symbol table
            # (typically the one linked in the symtab's sh_link field)
            # for simplicity, we'll assume the last strtab is the right one
            strtable_offset=$sec_offset
            strtable_size=$sec_size
        fi
    done
    
    if [[ $symtable_offset -eq 0 ]] || [[ $strtable_size -eq 0 ]]; then
        # could not find symbol table or string table
        return 1
    fi
    
    # read symbol table
    local symtab_entries
    parse_symbol_table "$file_path" "$symtable_offset" "$symtable_size" "symtab_entries" || return 1
    
    # read string table
    local string_table
    read_string_table "$file_path" "$strtable_offset" "$strtable_size" "string_table" || return 1
    
    # process symbols
    for sym_entry in "${symtab_entries[@]}"; do
        IFS=',' read -r st_name st_info st_shndx st_value <<< "$sym_entry"
        
        # skip null symbol (index 0)
        if [[ $st_name -eq 0 ]]; then
            continue
        fi
        
        # get symbol name from string table
        if [[ $st_name -lt ${#string_table[@]} ]]; then
            local sym_name="${string_table[$st_name]}"
            
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
        fi
    done
    
    return 0
}