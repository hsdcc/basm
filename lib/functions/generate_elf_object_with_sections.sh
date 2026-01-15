#!/usr/bin/env bash

# Generate proper ELF object file with sections
generate_elf_object_with_sections() {
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
    local total_sections=4  # NULL, .text, .data, .shstrtab
    
    # ELF Header (64 bytes for ELF64)
    local elf_header=""
    # Magic + class + data + version + osabi + abi_version
    elf_header+="7f454c46020101000000000000000000"
    # Type: ET_REL (relocatable) = 0x0001
    elf_header+="0100"
    # Machine: EM_X86_64 = 0x003e
    elf_header+="3e00"
    # Version: EV_CURRENT = 0x00000001
    elf_header+="01000000"
    # Entry point (0 for relocatable)
    elf_header+="0000000000000000"
    # Program header offset (0 for relocatable)
    elf_header+="0000000000000000"
    # Section header offset - calculated below
    local header_size=64
    local file_content_size=$text_size+$data_size  # approximate calculation
    local sec_header_offset=$((header_size + text_size + data_size))
    local sec_header_offset_hex=$(printf "%016x" $sec_header_offset)
    # Convert to little endian (swap byte order)
    elf_header+="${sec_header_offset_hex:14:2}${sec_header_offset_hex:12:2}${sec_header_offset_hex:10:2}${sec_header_offset_hex:8:2}${sec_header_offset_hex:6:2}${sec_header_offset_hex:4:2}${sec_header_offset_hex:2:2}${sec_header_offset_hex:0:2}"
    # Flags
    elf_header+="0000"
    # ELF header size
    elf_header+="4000"
    # Program header entry size (0 for relocatable)
    elf_header+="0000"
    # Number of program headers (0 for relocatable)
    elf_header+="0000"
    # Section header entry size (64 bytes for ELF64)
    elf_header+="4000"
    # Number of section headers
    local num_sections_hex=$(printf "%04x" $total_sections)
    elf_header+="${num_sections_hex:2:2}${num_sections_hex:0:2}"
    # Section name string table index (3 for shstrtab)
    elf_header+="0300"
    
    # Calculate positions for sections and content
    local text_section_off=$header_size
    local data_section_off=$((text_section_off + text_size))
    local sec_header_table_off=$sec_header_offset
    
    # Now construct section headers table
    # Each section header is 64 bytes in ELF64
    local section_headers=""
    
    # Section 0: NULL section
    section_headers+="00000000000000000000000000000000000000000000000000000000000000000000000000000000"
    
    # Section 1: .text section  
    # sh_name (offset in string table - we'll say offset 1 for ".text")
    section_headers+="01000000"
    # sh_type (SHT_PROGBITS = 0x00000001)
    section_headers+="01000000"
    # sh_flags (SHF_ALLOC | SHF_EXECINSTR = 0x0000000000000006)
    section_headers+="0600000000000000"
    # sh_addr (virtual address - 0 for relocatable)
    section_headers+="0000000000000000"
    # sh_offset (file offset of section data)
    local text_off_hex=$(printf "%016x" $text_section_off)
    section_headers+="${text_off_hex:14:2}${text_off_hex:12:2}${text_off_hex:10:2}${text_off_hex:8:2}${text_off_hex:6:2}${text_off_hex:4:2}${text_off_hex:2:2}${text_off_hex:0:2}"
    # sh_size (size of section in bytes)
    local text_sz_hex=$(printf "%016x" $text_size)
    section_headers+="${text_sz_hex:14:2}${text_sz_hex:12:2}${text_sz_hex:10:2}${text_sz_hex:8:2}${text_sz_hex:6:2}${text_sz_hex:4:2}${text_sz_hex:2:2}${text_sz_hex:0:2}"
    # sh_link, sh_info
    section_headers+="0000000000000000"
    # sh_addralign (alignment - 16 bytes = 0x0000000000000010)
    section_headers+="1000000000000000"
    # sh_entsize
    section_headers+="0000000000000000"
    
    # Section 2: .data section
    # sh_name (offset 7 for ".data")
    section_headers+="06000000"
    # sh_type (SHT_PROGBITS = 0x00000001)
    section_headers+="01000000"
    # sh_flags (SHF_ALLOC | SHF_WRITE = 0x0000000000000003)
    section_headers+="0300000000000000"
    # sh_addr (virtual address - 0 for relocatable)
    section_headers+="0000000000000000"
    # sh_offset (file offset of section data)
    local data_off_hex=$(printf "%016x" $data_section_off)
    section_headers+="${data_off_hex:14:2}${data_off_hex:12:2}${data_off_hex:10:2}${data_off_hex:8:2}${data_off_hex:6:2}${data_off_hex:4:2}${data_off_hex:2:2}${data_off_hex:0:2}"
    # sh_size (size of section in bytes)
    local data_sz_hex=$(printf "%016x" $data_size)
    section_headers+="${data_sz_hex:14:2}${data_sz_hex:12:2}${data_sz_hex:10:2}${data_sz_hex:8:2}${data_sz_hex:6:2}${data_sz_hex:4:2}${data_sz_hex:2:2}${data_sz_hex:0:2}"
    # sh_link, sh_info
    section_headers+="0000000000000000"
    # sh_addralign (alignment - 8 bytes = 0x0000000000000008)
    section_headers+="0800000000000000"
    # sh_entsize
    section_headers+="0000000000000000"
    
    # Section 3: .shstrtab section (section header string table)
    # sh_name (offset 0x0d for ".shstrtab")
    section_headers+="0c000000"
    # sh_type (SHT_STRTAB = 0x00000003)
    section_headers+="03000000"
    # sh_flags (0x0000000000000000)
    section_headers+="0000000000000000"
    # sh_addr
    section_headers+="0000000000000000"
    # sh_offset (starts after all content and section headers)
    local strtab_off_hex=$(printf "%016x" $sec_header_table_off)
    section_headers+="${strtab_off_hex:14:2}${strtab_off_hex:12:2}${strtab_off_hex:10:2}${strtab_off_hex:8:2}${strtab_off_hex:6:2}${strtab_off_hex:4:2}${strtab_off_hex:2:2}${strtab_off_hex:0:2}"
    # sh_size (size of string table)
    # Length of "\0.text\0.data\0.shstrtab\0" = 1+5+1+5+1+9+1 = 26 (0x1A)
    local strtab_sz_hex=$(printf "%016x" 26)
    section_headers+="${strtab_sz_hex:14:2}${strtab_sz_hex:12:2}${strtab_sz_hex:10:2}${strtab_sz_hex:8:2}${strtab_sz_hex:6:2}${strtab_sz_hex:4:2}${strtab_sz_hex:2:2}${strtab_sz_hex:0:2}"
    # sh_link, sh_info
    section_headers+="0000000000000000"
    # sh_addralign (1 byte alignment)
    section_headers+="0100000000000000"
    # sh_entsize
    section_headers+="0000000000000000"
    
    # Section header string table content
    local shstrtab="\0.text\0.data\0.shstrtab\0"
    
    # Create the file
    local tmpf
    tmpf="$(mktemp)" || { error_msg "failed to create temporary file"; return 1; }
    
    # Write ELF header
    hex_to_bin "$elf_header" >"$tmpf"
    
    # Write .text section content
    hex_to_bin "$text_hex" >>"$tmpf"
    
    # Write .data section content
    hex_to_bin "$data_bytes" >>"$tmpf"
    
    # Write section headers table
    hex_to_bin "$section_headers" >>"$tmpf"
    
    # Write section header string table
    printf "%s" "$shstrtab" >>"$tmpf"
    
    chmod 644 "$tmpf"  # Make sure it's not executable by default
    mv -f "$tmpf" "$outfile"
    return 0
}