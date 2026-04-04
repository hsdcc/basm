#!/usr/bin/env bash

# pure bash binary file reading utilities
# uses xxd -p for binary-to-hex conversion (bash has no fast built-in for reading binary)
# all other processing (endianness, parsing, etc.) is pure bash

# read bytes from a file at a given offset and return as hex string
# usage: read_file_hex <file_path> <skip_bytes> <count_bytes> <output_var>
read_file_hex() {
    local file_path="$1"
    local skip_bytes="$2"
    local count_bytes="$3"
    local output_ref="$4"
    local -n _rfh_output="$4"

    _rfh_output=$(xxd -p -s "$skip_bytes" -l "$count_bytes" "$file_path" 2>/dev/null | tr -d '\n')
    return 0
}

# read a single null-terminated string from a file at a given offset
# usage: read_string_at <file_path> <offset> <output_var>
read_string_at() {
    local file_path="$1"
    local offset="$2"
    local output_ref="$3"
    local -n _rsa_output="$3"

    # read a chunk of bytes starting at offset
    local hex_data
    read_file_hex "$file_path" "$offset" 256 "hex_data"

    # find null terminator and convert to string
    local result=""
    local pos=0
    while ((pos + 1 < ${#hex_data})); do
        local byte_hex="${hex_data:$pos:2}"
        if [[ "$byte_hex" == "00" ]]; then
            break
        fi
        local byte_val=$((16#$byte_hex))
        if ((byte_val >= 32 && byte_val < 127)); then
            result+=$(printf "\\$(printf '%03o' "$byte_val")")
        fi
        pos=$((pos + 2))
    done

    _rsa_output="$result"
    return 0
}

# read a little-endian unsigned 32-bit integer from file
# usage: read_u32le <file_path> <offset> <output_var>
read_u32le() {
    local file_path="$1"
    local offset="$2"
    local output_ref="$3"
    local -n _ru_output="$3"

    local hex_data
    read_file_hex "$file_path" "$offset" 4 "hex_data"

    # reverse byte order for little endian
    local reversed="${hex_data:6:2}${hex_data:4:2}${hex_data:2:2}${hex_data:0:2}"
    _ru_output=$((16#$reversed))
    return 0
}

# read a little-endian unsigned 64-bit integer from file
# usage: read_u64le <file_path> <offset> <output_var>
read_u64le() {
    local file_path="$1"
    local offset="$2"
    local output_ref="$3"
    local -n _ru64_output="$3"

    local hex_data
    read_file_hex "$file_path" "$offset" 8 "hex_data"

    # reverse byte order for little endian
    local reversed=""
    for ((i = 14; i >= 0; i -= 2)); do
        reversed+="${hex_data:$i:2}"
    done
    _ru64_output=$((16#$reversed))
    return 0
}

# read a little-endian unsigned 16-bit integer from file
# usage: read_u16le <file_path> <offset> <output_var>
read_u16le() {
    local file_path="$1"
    local offset="$2"
    local output_ref="$3"
    local -n _ru16_output="$3"

    local hex_data
    read_file_hex "$file_path" "$offset" 2 "hex_data"

    # reverse byte order for little endian
    local reversed="${hex_data:2:2}${hex_data:0:2}"
    _ru16_output=$((16#$reversed))
    return 0
}
