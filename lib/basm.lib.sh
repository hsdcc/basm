#!/usr/bin/env bash

# shim to make hex constants (16#) work in all bash versions
hex_to_dec() {
    local hex="$1"
    local result=0
    local pos
    for ((pos = 0; pos < ${#hex}; pos++)); do
        local digit="${hex:$pos:1}"
        case "$digit" in
            a|A) digit=10 ;;
            b|B) digit=11 ;;
            c|C) digit=12 ;;
            d|D) digit=13 ;;
            e|E) digit=14 ;;
            f|F) digit=15 ;;
        esac
        result=$((result * 16 + digit))
    done
    echo "$result"
}

# source all function files
for func_file in "$(dirname "${BASH_SOURCE[0]}")/functions/"*.sh; do
    if [[ -f "$func_file" ]]; then
        source "$func_file"
    fi
done
