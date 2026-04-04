#!/usr/bin/env bash

# check elf magic
is_elf_object() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        return 1
    fi
    local magic_hex=""
    read_file_hex "$file_path" 0 4 "magic_hex"
    if [[ "$magic_hex" == "7f454c46" ]]; then
        return 0
    fi
    return 1
}
