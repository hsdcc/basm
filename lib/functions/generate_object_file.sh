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
    header_hex+="4000000000000000"  # section header offset
    header_hex+="0000"       # processor flags
    header_hex+="4000"       # header size
    header_hex+="0000"       # program header entry size
    header_hex+="0000"       # number of program headers
    header_hex+="4000"       # section header entry size  
    header_hex+="0400"       # number of section headers (we'll have at least 4)
    header_hex+="0100"       # section name string table index

    local tmpf
    tmpf="$(mktemp)" || { error_msg "failed to create temporary file"; return 1; }

    hex_to_bin "$header_hex" >"$tmpf"

    chmod +x "$tmpf" 
    mv -f "$tmpf" "$outfile"
    return 0
}