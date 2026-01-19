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
    
    # open file for reading
    local fd
    exec 5< "$file_path"
    
    # skip to e_shoff (section header table offset) - byte 32-39
    for ((i=0; i<32; i++)); do
        read -n1 -u 5 dummy_byte
    done
    
    # read e_shoff (8 bytes) - little endian
    local shoff_bytes=()
    for ((i=0; i<8; i++)); do
        read -n1 -u 5 byte
        shoff_bytes+=("$byte")
    done
    
    # convert 8-byte little endian to decimal
    local shoff=0
    for ((i=0; i<8; i++)); do
        local byte_val
        byte_val=$(printf "%d" "'${shoff_bytes[$i]}")
        local shift=$((i * 8))
        shoff=$((shoff + (byte_val * (2 ** shift))))
    done
    
    # read e_shnum (number of section headers) - 2 bytes at offset 58-59
    # seek to position 58
    exec 5<&-
    exec 5< "$file_path"
    for ((i=0; i<58; i++)); do
        read -n1 -u 5 dummy_byte
    done
    
    # read shnum (2 bytes) - little endian
    local shnum_low_byte shnum_high_byte
    read -n1 -u 5 shnum_low_byte
    read -n1 -u 5 shnum_high_byte
    
    local shnum_low_val shnum_high_val
    shnum_low_val=$(printf "%d" "'$shnum_low_byte")
    shnum_high_val=$(printf "%d" "'$shnum_high_byte")
    
    local num_sections
    num_sections=$((shnum_low_val + (shnum_high_val * 256)))
    
    # read e_shstrndx (section header string table index) - 2 bytes at offset 60-61
    local shstrndx_low_byte shstrndx_high_byte
    read -n1 -u 5 shstrndx_low_byte
    read -n1 -u 5 shstrndx_high_byte
    
    local shstrndx_low_val shstrndx_high_val
    shstrndx_low_val=$(printf "%d" "'$shstrndx_low_byte")
    shstrndx_high_val=$(printf "%d" "'$shstrndx_high_byte")
    
    local shstrndx
    shstrndx=$((shstrndx_low_val + (shstrndx_high_val * 256)))
    
    # close file descriptor
    exec 5<&-
    
    # set output variables with the given prefix
    local shoff_var="${prefix}_shoff"
    local shnum_var="${prefix}_num_sections"
    local shstrndx_var="${prefix}_shstrndx"
    
    eval "$shoff_var=$shoff"
    eval "$shnum_var=$num_sections"
    eval "$shstrndx_var=$shstrndx"
    
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
    
    local fd
    exec 6< "$file_path"
    
    # skip to section header table
    for ((i=0; i<shoff; i++)); do
        read -n1 -u 6 dummy_byte
    done
    
    # each section header is 64 bytes in elf64
    sections_n=()
    for ((sec_idx=0; sec_idx<num_sections; sec_idx++)); do
        # read the section header (64 bytes)
        local shdr=()
        for ((j=0; j<64; j++)); do
            read -n1 -u 6 sec_byte
            shdr+=("$sec_byte")
        done
        
        # extract fields:
        # sh_name: offset 0-3 (4 bytes) - index into section header string table
        local sh_name=0
        for ((i=0; i<4; i++)); do
            local byte_val
            byte_val=$(printf "%d" "'${shdr[$i]}")
            local shift=$((i * 8))
            sh_name=$((sh_name + (byte_val * (2 ** shift))))
        done
        
        # sh_type: offset 4-7 (4 bytes)
        local sh_type=0
        for ((i=4; i<8; i++)); do
            local byte_val
            byte_val=$(printf "%d" "'${shdr[$i]}")
            local shift=$(((i - 4) * 8))
            sh_type=$((sh_type + (byte_val * (2 ** shift))))
        done
        
        # sh_offset: offset 24-31 (8 bytes)
        local sh_offset=0
        for ((i=24; i<32; i++)); do
            local byte_val
            byte_val=$(printf "%d" "'${shdr[$i]}")
            local shift=$(((i - 24) * 8))
            sh_offset=$((sh_offset + (byte_val * (2 ** shift))))
        done
        
        # sh_size: offset 32-39 (8 bytes)
        local sh_size=0
        for ((i=32; i<40; i++)); do
            local byte_val
            byte_val=$(printf "%d" "'${shdr[$i]}")
            local shift=$(((i - 32) * 8))
            sh_size=$((sh_size + (byte_val * (2 ** shift))))
        done
        
        # store section info
        sections_n+=("$sh_name,$sh_type,$sh_offset,$sh_size")
    done
    
    exec 6<&-
    
    return 0
}