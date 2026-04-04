#!/usr/bin/env bash
generate_zeros() {
    local count="$1"
    local i
    for ((i = 0; i < count; i++)); do
        printf "\\x00"
    done
}