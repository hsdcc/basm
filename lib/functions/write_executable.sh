#!/usr/bin/env bash

write_final_executable() {
    local header_hex="$1"
    local text_hex="$2"
    local data_bytes="$3"
    local file_text_off="$4"
    local text_size="$5"
    local data_size="$6"
    local file_data_off="$7"
    local outfile="$8"
    local tmpf
    tmpf="$(mktemp)" || { error_msg "failed to create temporary file"; return 1; }
    hex_to_bin "$header_hex" >"$tmpf"
    local cur_size=$((${#header_hex} / 2))
    if ((cur_size > file_text_off)); then
        error_msg "header too big"
        rm -f "$tmpf"
        return 1
    fi
    local pad=$((file_text_off - cur_size))
    generate_zeros "$pad" >>"$tmpf"
    hex_to_bin "$text_hex" >>"$tmpf"
    hex_to_bin "$data_bytes" >>"$tmpf"
    local actual_size=$((file_text_off + text_size + data_size))
    local filesz=$((file_data_off + data_size))
    if [ "$actual_size" -ne "$filesz" ]; then
        filesz=$actual_size
        local seek=$((0x38))
        local patch_data="$(u64le "$filesz")$(u64le "$filesz")"
        local temp_bin
        temp_bin=$(mktemp) || { error_msg "failed to create temporary file for patch"; rm -f "$tmpf"; return 1; }
        hex_to_bin "$patch_data" > "$temp_bin"
        write_at_offset "$temp_bin" "$tmpf" "$seek"
        rm -f "$temp_bin"
    fi
    chmod +x "$tmpf"
    mv -f "$tmpf" "$outfile"
    return 0
}
