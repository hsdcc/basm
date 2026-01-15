#!/usr/bin/env bash

hex_to_bin() {
    local hex="$1"
    local -a bytes
    local i
    
    # ensure even length hex string
    if (( ${#hex} % 2 != 0 )); then
        hex="0$hex"
    fi
    
    # split hex string into byte pairs and convert to binary
    for ((i = 0; i < ${#hex}; i += 2)); do
        local byte="${hex:$i:2}"
        printf "\\x$byte"
    done
}