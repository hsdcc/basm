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
    local magic_hex=""
    read_file_hex "$file_path" 0 4 "magic_hex"

    # check if first four bytes are elf magic: 0x7f 'e' 'l' 'f'
    if [[ "$magic_hex" == "7f454c46" ]]; then
        return 0  # is elf file with proper magic
    fi

    return 1  # not an elf file
}