#!/usr/bin/env bash

# Generate proper ELF object file with sections and minimal viable content
generate_minimal_elf_object() {
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
    
    # Calculate positions
    local header_size=64  # ELF header size
    local text_section_off=$header_size
    local data_section_off=$((text_section_off + text_size))
    local strtab_size=26  # "\0.text\0.data\0.shstrtab\0" = ~26 chars
    local section_header_size=64  # Each section header is 64 bytes in ELF64
    local section_headers_total=$((total_sections * section_header_size))
    local sec_header_table_off=$((data_section_off + data_size))
    
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
    elf_header+="${shoff_hex:14:2}${shoff_hex:12:2}${shoff_hex:10:2}${shoff_hex:8:2}${shoff_hex:6:2}${shoff_hex:4:2}${shoff_hex:2:2}${shoff_hex:0:2}"
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
    # e_shnum: number of section headers (4 sections)
    local shnum_hex=$(printf "%04x" $total_sections)
    elf_header+="${shnum_hex:2:2}${shnum_hex:0:2}"
    # e_shstrndx: section header string table index (3)
    local shstrndx_hex=$(printf "%04x" 3)
    elf_header+="${shstrndx_hex:2:2}${shstrndx_hex:0:2}"
    
    # Section Headers
    local section_headers=""
    
    # Section 0: NULL section (all zeros)
    for ((i = 0; i < 64; i++)); do
        section_headers+="00"
    done
    
    # Section 1: .text section - starts at offset 64 (after ELF header)
    # sh_name (offset in string table where name begins - 1 for ".text")
    local sh_name_hex=$(printf "%08x" 1)
    section_headers+="${sh_name_hex:6:2}${sh_name_hex:4:2}${sh_name_hex:2:2}${sh_name_hex:0:2}"
    # sh_type (SHT_PROGBITS = 0x00000001)
    section_headers+="01000000"
    # sh_flags (SHF_ALLOC | SHF_EXECINSTR = 0x0000000000000006)
    local sh_flags_hex=$(printf "%016x" $((0x6)))
    section_headers+="${sh_flags_hex:14:2}${sh_flags_hex:12:2}${sh_flags_hex:10:2}${sh_flags_hex:8:2}${sh_flags_hex:6:2}${sh_flags_hex:4:2}${sh_flags_hex:2:2}${sh_flags_hex:0:2}"
    # sh_addr (virtual address - 0 for relocatable)
    section_headers+="0000000000000000"
    # sh_offset (file offset)
    local sh_offset_hex=$(printf "%016x" $text_section_off)
    section_headers+="${sh_offset_hex:14:2}${sh_offset_hex:12:2}${sh_offset_hex:10:2}${sh_offset_hex:8:2}${sh_offset_hex:6:2}${sh_offset_hex:4:2}${sh_offset_hex:2:2}${sh_offset_hex:0:2}"
    # sh_size (size in bytes)
    local sh_size_hex=$(printf "%016x" $text_size)
    section_headers+="${sh_size_hex:14:2}${sh_size_hex:12:2}${sh_size_hex:10:2}${sh_size_hex:8:2}${sh_size_hex:6:2}${sh_size_hex:4:2}${sh_size_hex:2:2}${sh_size_hex:0:2}"
    # sh_link (0 for .text)
    section_headers+="00000000"
    # sh_info (0 for .text)
    section_headers+="00000000"
    # sh_addralign (16 for .text)
    local sh_addralign_hex=$(printf "%016x" 16)
    section_headers+="${sh_addralign_hex:14:2}${sh_addralign_hex:12:2}${sh_addralign_hex:10:2}${sh_addralign_hex:8:2}${sh_addralign_hex:6:2}${sh_addralign_hex:4:2}${sh_addralign_hex:2:2}${sh_addralign_hex:0:2}"
    # sh_entsize (0 for .text)
    section_headers+="0000000000000000"
    
    # Section 2: .data section
    # sh_name (offset in string table - 7 for ".data")
    sh_name_hex=$(printf "%08x" 7)
    section_headers+="${sh_name_hex:6:2}${sh_name_hex:4:2}${sh_name_hex:2:2}${sh_name_hex:0:2}"
    # sh_type (SHT_PROGBITS = 0x00000001)
    section_headers+="01000000"
    # sh_flags (SHF_ALLOC | SHF_WRITE = 0x0000000000000003)
    sh_flags_hex=$(printf "%016x" $((0x3)))
    section_headers+="${sh_flags_hex:14:2}${sh_flags_hex:12:2}${sh_flags_hex:10:2}${sh_flags_hex:8:2}${sh_flags_hex:6:2}${sh_flags_hex:4:2}${sh_flags_hex:2:2}${sh_flags_hex:0:2}"
    # sh_addr (virtual address - 0 for relocatable)
    section_headers+="0000000000000000"
    # sh_offset (file offset)
    sh_offset_hex=$(printf "%016x" $data_section_off)
    section_headers+="${sh_offset_hex:14:2}${sh_offset_hex:12:2}${sh_offset_hex:10:2}${sh_offset_hex:8:2}${sh_offset_hex:6:2}${sh_offset_hex:4:2}${sh_offset_hex:2:2}${sh_offset_hex:0:2}"
    # sh_size (size in bytes)
    sh_size_hex=$(printf "%016x" $data_size)
    section_headers+="${sh_size_hex:14:2}${sh_size_hex:12:2}${sh_size_hex:10:2}${sh_size_hex:8:2}${sh_size_hex:6:2}${sh_size_hex:4:2}${sh_size_hex:2:2}${sh_size_hex:0:2}"
    # sh_link (0 for .data)
    section_headers+="00000000"
    # sh_info (0 for .data)
    section_headers+="00000000"
    # sh_addralign (8 for .data)
    sh_addralign_hex=$(printf "%016x" 8)
    section_headers+="${sh_addralign_hex:14:2}${sh_addralign_hex:12:2}${sh_addralign_hex:10:2}${sh_addralign_hex:8:2}${sh_addralign_hex:6:2}${sh_addralign_hex:4:2}${sh_addralign_hex:2:2}${sh_addralign_hex:0:2}"
    # sh_entsize (0 for .data)
    section_headers+="0000000000000000"
    
    # Section 3: .shstrtab (section header string table)
    # sh_name (offset in string table - 13 for ".shstrtab") 
    sh_name_hex=$(printf "%08x" 13)
    section_headers+="${sh_name_hex:6:2}${sh_name_hex:4:2}${sh_name_hex:2:2}${sh_name_hex:0:2}"
    # sh_type (SHT_STRTAB = 0x00000003)
    section_headers+="03000000"
    # sh_flags (0x0000000000000000)
    sh_flags_hex=$(printf "%016x" 0)
    section_headers+="${sh_flags_hex:14:2}${sh_flags_hex:12:2}${sh_flags_hex:10:2}${sh_flags_hex:8:2}${sh_flags_hex:6:2}${sh_flags_hex:4:2}${sh_flags_hex:2:2}${sh_flags_hex:0:2}"
    # sh_addr (virtual address - 0 for relocatable)
    section_headers+="0000000000000000"
    # sh_offset (starts after section headers)
    sh_offset_hex=$(printf "%016x" $sec_header_table_off)
    section_headers+="${sh_offset_hex:14:2}${sh_offset_hex:12:2}${sh_offset_hex:10:2}${sh_offset_hex:8:2}${sh_offset_hex:6:2}${sh_offset_hex:4:2}${sh_offset_hex:2:2}${sh_offset_hex:0:2}"
    # sh_size (size of string table)
    sh_size_hex=$(printf "%016x" $strtab_size)
    section_headers+="${sh_size_hex:14:2}${sh_size_hex:12:2}${sh_size_hex:10:2}${sh_size_hex:8:2}${sh_size_hex:6:2}${sh_size_hex:4:2}${sh_size_hex:2:2}${sh_size_hex:0:2}"
    # sh_link (0 for string table)
    section_headers+="00000000"
    # sh_info (0 for string table)
    section_headers+="00000000"
    # sh_addralign (1 for string table)
    sh_addralign_hex=$(printf "%016x" 1)
    section_headers+="${sh_addralign_hex:14:2}${sh_addralign_hex:12:2}${sh_addralign_hex:10:2}${sh_addralign_hex:8:2}${sh_addralign_hex:6:2}${sh_addralign_hex:4:2}${sh_addralign_hex:2:2}${sh_addralign_hex:0:2}"
    # sh_entsize (0 for string table)
    section_headers+="0000000000000000"
    
    # Section name string table content  
    # "\0.text\0.data\0.shstrtab\0"
    local shstrtab_hex="002e74657874002e64617461002e736873747274616200"
    
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
    hex_to_bin "$shstrtab_hex" >>"$tmpf"
    
    chmod 644 "$tmpf" 
    mv -f "$tmpf" "$outfile"
    return 0
}