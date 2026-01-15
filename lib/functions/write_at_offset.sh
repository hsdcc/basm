#!/usr/bin/env bash

write_at_offset() {
    local src_file="$1"      # source file containing data to write
    local dest_file="$2"     # destination file to write to
    local offset="$3"        # byte offset to write at

    # read the source file content
    local src_content
    src_content=$(< "$src_file")

    # read the destination file content
    local dest_content
    if [[ -f "$dest_file" ]]; then
        dest_content=$(< "$dest_file")
    else
        dest_content=""
    fi

    # ensure destination is at least 'offset' bytes long by padding with nulls if necessary
    local current_len=${#dest_content}
    local padded_content="$dest_content"
    if (( current_len < offset )); then
        local padding_len=$((offset - current_len))
        local i
        for ((i = 0; i < padding_len; i++)); do
            padded_content+=$'\0'
        done
    fi

    # calculate where to place the source content
    local prefix="${padded_content:0:offset}"
    local suffix="${padded_content:offset}"

    # combine: prefix + src_content + suffix
    local result="$prefix$src_content$suffix"

    # write the combined content back to the destination file
    printf '%s' "$result" > "$dest_file"
}