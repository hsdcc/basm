#!/usr/bin/env bash

# Helper function to reverse byte order in hex string
reverse_endian() {
    local hex="$1"
    local len=${#hex}
    local reversed=""
    
    # Ensure the hex string has even length
    if ((len % 2 != 0)); then
        hex="0$hex"
        len=$((len + 1))
    fi
    
    # Process in 2-character chunks (bytes)
    for ((i = len - 2; i >= 0; i -= 2)); do
        reversed="${reversed}${hex:$i:2}"
    done
    
    echo "$reversed"
}

# Generate proper ELF object file with sections and symbol table
generate_elf_object_with_symbols() {
    local text_hex="$1"
    local data_bytes="$2"
    local labels_ref="$3"
    local equs_ref="$4"
    local outfile="$5"
    
    # local refs for easier access
    local -n labels_n="$3"
    local -n equs_n="$4"
    
    # Calculate sizes
    local text_size=$((${#text_hex} / 2))
    local data_size=$((${#data_bytes} / 2))
    
    # Count actual sections: NULL, .text, .data, .shstrtab, .symtab, .strtab
    local total_sections=6
    
    # Calculate positions
    local header_size=64  # ELF header size
    local text_section_off=$header_size
    local data_section_off=$((text_section_off + text_size))
    
    # Create symbol string table content
    local symstrtab_content=$'\0'
    local current_str_offset=1
    
    # Add all labels to string table
    for label_name in "${!labels_n[@]}"; do
        symstrtab_content+="$label_name"
        symstrtab_content+=$'\0'
        current_str_offset=$((current_str_offset + ${#label_name} + 1))
    done
    
    local symstrtab_size=${#symstrtab_content}
    
    # Each symbol table entry is 24 bytes in ELF64
    # Number of symbol entries = 1 (null entry) + all labels
    local num_symbols=1
    for label_name in "${!labels_n[@]}"; do
        num_symbols=$((num_symbols + 1))
    done
    local symtab_size=$((num_symbols * 24))
    
    # Calculate section header table offset (after all content)
    local strtab_off=$((data_section_off + data_size))
    local symtab_off=$((strtab_off + symstrtab_size))
    local sec_header_table_off=$((symtab_off + symtab_size))
    
    # ELF Header (64 bytes for ELF64)
    local elf_header=""
    # EI_MAG0 to EI_MAG3: 0x7F 'E' 'L' 'F'
    elf_header+="7f454c46"
    # EI_CLASS: ELFCLASS64 (0x02)
    elf_header+="02"
    # EI_DATA: ELFDATA2LSB (0x01)
    elf_header+="01"
    # EI_VERSION: EV_CURRENT (0x01)
    elf_header+="01"
    # EI_OSABI: 0x00 (System V)
    elf_header+="00"
    # EI_ABIVERSION: 0x00
    elf_header+="00"
    # EI_PAD: 7 bytes of padding
    elf_header+="00000000000000"
    # e_type: ET_REL (relocatable) = 0x0001
    elf_header+="0100"
    # e_machine: EM_X86_64 = 0x003e
    elf_header+="3e00"
    # e_version: EV_CURRENT = 0x00000001
    elf_header+="01000000"
    # e_entry: 0x0000000000000000 (entry point - 0 for relocatable)
    elf_header+="0000000000000000"
    # e_phoff: 0x0000000000000000 (program header offset - 0 for relocatable)
    elf_header+="0000000000000000"
    # e_shoff: section header offset
    local shoff_hex=$(printf "%016x" $sec_header_table_off)
    # Convert to little endian (byte-reversed)
    elf_header+=$(reverse_endian "$shoff_hex")
    # e_flags: 0x00000000 (processor-specific flags)
    elf_header+="00000000"
    # e_ehsize: 0x0040 (ELF header size - 64 bytes)
    elf_header+="4000"
    # e_phentsize: 0x0000 (program header entry size - 0 for relocatable)
    elf_header+="0000"
    # e_phnum: 0x0000 (number of program header entries - 0 for relocatable)
    elf_header+="0000"
    # e_shentsize: 0x0040 (section header entry size - 64 bytes in ELF64)
    elf_header+="4000"
    # e_shnum: number of section headers (6 sections)
    local shnum_hex=$(printf "%04x" $total_sections)
    elf_header+=$(reverse_endian "$shnum_hex")
    # e_shstrndx: section header string table index (3)
    local shstrndx_hex=$(printf "%04x" 3)
    elf_header+=$(reverse_endian "$shstrndx_hex")
    
    # Create symbol table entries
    local symtab_content=""
    
    # Index 0: Null symbol entry (all zeros)
    for ((i = 0; i < 24; i++)); do
        symtab_content+="00"
    done
    
    # Add all labeled symbols
    local sym_idx=1
    for label_name in "${!labels_n[@]}"; do
        local label_off=${labels_n[$label_name]}
        
        # st_name (offset in string table)
        local str_offset=1  # Start at 1 since we begin with \0 in the string table
        local temp_str=$'\0'
        local found=0
        for temp_label in "${!labels_n[@]}"; do
            if [[ "$temp_label" == "$label_name" ]]; then
                found=1
                break
            fi
            temp_str+="$temp_label"
            temp_str+=$'\0'
            str_offset=$((str_offset + ${#temp_label} + 1))
        done
        
        local st_name_hex=$(printf "%08x" $str_offset)
        symtab_content+=$(reverse_endian "$st_name_hex")
        
        # st_info (STB_GLOBAL << 4) | STT_NOTYPE = 0x10
        symtab_content+="10"
        # st_other (visibility - 0)
        symtab_content+="00"
        # st_shndx (section index - assuming text section for now which is 1)
        local shndx_hex=$(printf "%04x" 1)
        symtab_content+=$(reverse_endian "$shndx_hex")
        # st_value (address/local offset)
        local value_hex=$(printf "%016x" $label_off)
        symtab_content+=$(reverse_endian "$value_hex")
        # st_size (zero for our purposes)
        symtab_content+="0000000000000000"
        
        sym_idx=$((sym_idx + 1))
    done
    
    # Create section headers
    local section_headers=""
    
    # Section 0: NULL section (all zeros)
    for ((i = 0; i < 64; i++)); do
        section_headers+="00"
    done
    
    # Section 1: .text section
    local sh_name_hex=$(printf "%08x" 1)  # Points to ".text" in string table
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="01000000"  # SHT_PROGBITS
    local sh_flags_hex=$(printf "%016x" $((0x6)))  # SHF_ALLOC | SHF_EXECINSTR
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"  # sh_addr
    local sh_offset_hex=$(printf "%016x" $text_section_off)
    section_headers+=$(reverse_endian "$sh_offset_hex")
    local sh_size_hex=$(printf "%016x" $text_size)
    section_headers+=$(reverse_endian "$sh_size_hex")
    section_headers+="00000000"  # sh_link
    section_headers+="00000000"  # sh_info
    local sh_addralign_hex=$(printf "%016x" 16)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    section_headers+="0000000000000000"  # sh_entsize
    
    # Section 2: .data section
    sh_name_hex=$(printf "%08x" 7)  # Points to ".data" in string table
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="01000000"  # SHT_PROGBITS
    sh_flags_hex=$(printf "%016x" $((0x3)))  # SHF_ALLOC | SHF_WRITE
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"  # sh_addr
    sh_offset_hex=$(printf "%016x" $data_section_off)
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" $data_size)
    section_headers+=$(reverse_endian "$sh_size_hex")
    section_headers+="00000000"  # sh_link
    section_headers+="00000000"  # sh_info
    sh_addralign_hex=$(printf "%016x" 8)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    section_headers+="0000000000000000"  # sh_entsize
    
    # Section 3: .shstrtab (section header string table) - "\0.text\0.data\0.shstrtab\0.symtab\0.strtab\0"
    sh_name_hex=$(printf "%08x" 13)  # Points to ".shstrtab"
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="03000000"  # SHT_STRTAB
    sh_flags_hex=$(printf "%016x" 0)
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"  # sh_addr
    sh_offset_hex=$(printf "%016x" $strtab_off)  # Points to the section string table after data
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" 34)  # Size of section header string table "\0.text\0.data\0.shstrtab\0.symtab\0.strtab\0" = ~34 chars
    section_headers+=$(reverse_endian "$sh_size_hex")
    section_headers+="00000000"  # sh_link
    section_headers+="00000000"  # sh_info
    sh_addralign_hex=$(printf "%016x" 1)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    section_headers+="0000000000000000"  # sh_entsize
    
    # Section 4: .symtab (symbol table)
    sh_name_hex=$(printf "%08x" 23)  # Points to ".symtab" in string table  
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="02000000"  # SHT_SYMTAB
    sh_flags_hex=$(printf "%016x" 0)
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"  # sh_addr
    sh_offset_hex=$(printf "%016x" $symtab_off)  # Points to the symbol table
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" $symtab_size)  # Size of symbol table
    section_headers+=$(reverse_endian "$sh_size_hex")
    local link_idx_hex=$(printf "%04x" 5)  # Links to string table (section 5)
    section_headers+=$(reverse_endian "$link_idx_hex")  # sh_link
    section_headers+="00000000"  # sh_info - index of first non-local symbol
    sh_addralign_hex=$(printf "%016x" 8)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    local entsize_hex=$(printf "%016x" 24)  # Entry size is 24 for ELF64
    section_headers+=$(reverse_endian "$entsize_hex")  # sh_entsize
    
    # Section 5: .strtab (symbol string table)
    sh_name_hex=$(printf "%08x" 31)  # Points to ".strtab" in string table
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="03000000"  # SHT_STRTAB
    sh_flags_hex=$(printf "%016x" 0)
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"  # sh_addr
    sh_offset_hex=$(printf "%016x" $strtab_off)  # Points to the string table
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" $symstrtab_size)  # Size of string table
    section_headers+=$(reverse_endian "$sh_size_hex")
    section_headers+="00000000"  # sh_link
    section_headers+="00000000"  # sh_info
    sh_addralign_hex=$(printf "%016x" 1)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    section_headers+="0000000000000000"  # sh_entsize
    
    # Section header string table content  
    # "\0.text\0.data\0.shstrtab\0.symtab\0.strtab\0"
    local shstrtab_hex="002e74657874002e64617461002e7368737472746162002e73796d746162002e73747274616200"
    
    # Create the file
    local tmpf
    tmpf="$(mktemp)" || { error_msg "failed to create temporary file"; return 1; }
    
    # Write ELF header
    hex_to_bin "$elf_header" >"$tmpf"
    
    # Write .text section content
    hex_to_bin "$text_hex" >>"$tmpf"
    
    # Write .data section content
    hex_to_bin "$data_bytes" >>"$tmpf"
    
    # Write symbol string table
    printf "%s" "$symstrtab_content" >>"$tmpf"
    
    # Write symbol table
    hex_to_bin "$symtab_content" >>"$tmpf"
    
    # Write section headers table
    hex_to_bin "$section_headers" >>"$tmpf"
    
    # Write section header string table
    hex_to_bin "$shstrtab_hex" >>"$tmpf"
    
    chmod 644 "$tmpf" 
    mv -f "$tmpf" "$outfile"
    return 0
}