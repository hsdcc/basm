#!/usr/bin/env bash
write_at_offset() {
    local src_file="$1"      
    local dest_file="$2"     
    local offset="$3"        
    
    local src_content
    src_content=$(< "$src_file")
    
    local dest_content
    if [[ -f "$dest_file" ]]; then
        dest_content=$(< "$dest_file")
    else
        dest_content=""
    fi
    
    local current_len=${#dest_content}
    local padded_content="$dest_content"
    if (( current_len < offset )); then
        local padding_len=$((offset - current_len))
        local i
        for ((i = 0; i < padding_len; i++)); do
            padded_content+=$'\0'
        done
    fi
    
    local prefix="${padded_content:0:offset}"
    local suffix="${padded_content:offset}"
    
    local result="$prefix$src_content$suffix"
    
    printf '%s' "$result" > "$dest_file"
}