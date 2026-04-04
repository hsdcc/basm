#!/usr/bin/env bash
hex_to_bin() {
    local hex="$1"
    local -a bytes
    local i
    
    
    if (( ${#hex} % 2 != 0 )); then
        hex="0$hex"
    fi
    
    
    for ((i = 0; i < ${#hex}; i += 2)); do
        local byte="${hex:$i:2}"
        printf "\\x$byte"
    done
}