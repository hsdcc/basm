#!/usr/bin/env bash

# check if a file is an elf object file using pure bash
# returns 0 if it's an elf object file, 1 otherwise
is_elf_object() {
    local file_path="$1"
    
    # check if file exists
    if [[ ! -f "$file_path" ]]; then
        return 1
    fi
    
    # read first 4 bytes for elf magic
    local fd
    exec 3< "$file_path"
    local magic_bytes=()
    
    # read first 4 bytes for elf magic
    for ((i=0; i<4; i++)); do
        read -n1 -u 3 byte
        magic_bytes+=("$byte")
    done
    exec 3<&-
    
    # check if first four bytes are elf magic: 0x7f 'e' 'l' 'f'
    if [[ ${#magic_bytes[@]} -ge 4 ]] && \
       [[ "${magic_bytes[0]}" == $'\x7F' ]] && \
       [[ "${magic_bytes[1]}" == "E" ]] && \
       [[ "${magic_bytes[2]}" == "L" ]] && \
       [[ "${magic_bytes[3]}" == "F" ]]; then
       
        # accept as elf if it has proper magic for our linking purposes
        return 0  # is elf file with proper magic
    fi
    
    return 1  # not an elf file
}