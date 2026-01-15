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
    local total_sections=4  # NULL + .text + .data + .shstrtab initially
    local section_header_size=64  # Size of each section header entry in ELF64
    local section_headers_size=$((total_sections * section_header_size))
    
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
    
    # Section header offset comes after all content
    local section_header_offset=$((0x40))  # Basic ELF header size
    section_header_offset=$((section_header_offset + text_size + data_size))
    
    local temp_hex=$(printf "%016x" $section_header_offset)
    header_hex+=$(reverse_endian "$temp_hex")  # Little endian
    header_hex+="0000"       # processor flags
    header_hex+="4000"       # header size
    header_hex+="0000"       # program header entry size
    header_hex+="0000"       # number of program headers
    header_hex+="4000"       # section header entry size (64 bytes for ELF64)  
    local temp_hex=$(printf "%04x" $total_sections)
    header_hex+=$(reverse_endian "$temp_hex")  # number of section headers
    header_hex+="0300"       # section name string table index (index 3 which is .shstrtab)

    local tmpf
    tmpf="$(mktemp)" || { error_msg "failed to create temporary file"; return 1; }

    # Write ELF header
    hex_to_bin "$header_hex" >"$tmpf"
    
    # Write .text section content
    hex_to_bin "$text_hex" >>"$tmpf"
    
    # Write .data section content
    hex_to_bin "$data_bytes" >>"$tmpf"
    
    # For now, just create a minimal section headers
    # In a real implementation, we'd write all section header entries

    chmod +x "$tmpf" 
    mv -f "$tmpf" "$outfile"
    return 0
}