#!/usr/bin/env bash

generate_object_file() {
    local text_hex="$1"
    local data_bytes="$2"
    local labels_ref="$3"
    local equs_ref="$4"
    local outfile="$5"

    # local refs for easier access
    local -n labels_n="$3"
    local -n equs_n="$4"

    # Calculate section sizes and offsets
    local text_size=$((${#text_hex} / 2))
    local data_size=$((${#data_bytes} / 2))
    local total_sections=4  # NULL + .text + .data + .shstrtab
    local section_header_size=64  # Size of each section header entry in ELF64

    # Calculate positions
    local header_size=64
    local text_section_off=$header_size
    local data_section_off=$((text_section_off + text_size))
    local shstrtab_off=$((data_section_off + data_size))
    local sec_header_table_off=$shstrtab_off

    # Section header string table: "\0.text\0.data\0.shstrtab\0"
    # offsets: .text=1, .data=7, .shstrtab=13
    local shstrtab_hex="002e74657874002e64617461002e736873747274616200"
    local shstrtab_size=19

    # ELF header for relocatable object file
    local header_hex=""
    header_hex+="7f454c46"  # ELF magic
    header_hex+="02"         # 64-bit
    header_hex+="01"         # little endian
    header_hex+="01"         # version
    header_hex+="00"         # os abi
    header_hex+="0000000000000000"  # padding
    header_hex+="0100"       # relocatable file type (ET_REL)
    header_hex+="3e00"       # x86-64 machine
    header_hex+="01000000"   # version
    header_hex+="0000000000000000"  # entry point (0 for relocatable)
    header_hex+="0000000000000000"  # program header offset (0 for relocatable)

    # Section header offset
    local temp_hex=$(printf "%016x" $sec_header_table_off)
    header_hex+=$(reverse_endian "$temp_hex")  # Little endian
    header_hex+="00000000"  # processor flags
    header_hex+="4000"       # header size
    header_hex+="0000"       # program header entry size
    header_hex+="0000"       # number of program headers
    header_hex+="4000"       # section header entry size (64 bytes for ELF64)
    temp_hex=$(printf "%04x" $total_sections)
    header_hex+=$(reverse_endian "$temp_hex")  # number of section headers
    header_hex+="0300"       # section name string table index (index 3 which is .shstrtab)

    # Create section headers
    local section_headers=""

    # Section 0: NULL section (all zeros)
    for ((i = 0; i < 64; i++)); do
        section_headers+="00"
    done

    # Section 1: .text section
    local sh_name_hex=$(printf "%08x" 1)  # Points to ".text" in shstrtab
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
    sh_name_hex=$(printf "%08x" 7)  # Points to ".data" in shstrtab
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

    # Section 3: .shstrtab (section header string table)
    sh_name_hex=$(printf "%08x" 13)  # Points to ".shstrtab" in shstrtab
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="03000000"  # SHT_STRTAB
    sh_flags_hex=$(printf "%016x" 0)
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"  # sh_addr
    sh_offset_hex=$(printf "%016x" $shstrtab_off)
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" $shstrtab_size)
    section_headers+=$(reverse_endian "$sh_size_hex")
    section_headers+="00000000"  # sh_link
    section_headers+="00000000"  # sh_info
    sh_addralign_hex=$(printf "%016x" 1)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    section_headers+="0000000000000000"  # sh_entsize

    local tmpf
    tmpf="$(mktemp)" || { error_msg "failed to create temporary file"; return 1; }

    # Write ELF header
    hex_to_bin "$header_hex" >"$tmpf"

    # Write .text section content
    hex_to_bin "$text_hex" >>"$tmpf"

    # Write .data section content
    hex_to_bin "$data_bytes" >>"$tmpf"

    # Write section header string table
    hex_to_bin "$shstrtab_hex" >>"$tmpf"

    # Write section headers table
    hex_to_bin "$section_headers" >>"$tmpf"

    chmod 644 "$tmpf"
    mv -f "$tmpf" "$outfile"
    return 0
}