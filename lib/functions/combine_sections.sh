#!/usr/bin/env bash

# extract section by name
extract_section_by_name() {
    local file_path="$1"
    local section_name="$2"
    local output_ref="$3"
    local -n output_n="$3"
    local header_prefix="extract"
    if ! parse_elf_header "$file_path" "$header_prefix"; then
        return 1
    fi
    local shoff num_sections shstrndx
    shoff="${extract_shoff}"
    num_sections="${extract_num_sections}"
    shstrndx="${extract_shstrndx}"
    local sections
    parse_section_headers "$file_path" "$shoff" "$num_sections" "sections" || return 1
    local shstrtab_offset=0
    local shstrtab_size=0
    for ((i = 0; i < num_sections; i++)); do
        IFS=',' read -r sec_name sec_type sec_off sec_size <<< "${sections[$i]}"
        if [[ $i -eq $shstrndx ]]; then
            shstrtab_offset=$sec_off
            shstrtab_size=$sec_size
            break
        fi
    done
    local shstrtab_hex=""
    read_file_hex "$file_path" "$shstrtab_offset" "$shstrtab_size" "shstrtab_hex"
    _rb_get_string() {
        local hex_str="$1"
        local str_offset="$2"
        local result=""
        local pos=$str_offset
        while ((pos + 1 < ${#hex_str})); do
            local byte_hex="${hex_str:$pos:2}"
            [[ "$byte_hex" == "00" ]] && break
            local byte_val=$((16#$byte_hex))
            ((byte_val >= 32 && byte_val < 127)) && result+=$(printf "\\$(printf '%03o' "$byte_val")")
            pos=$((pos + 2))
        done
        _rb_str_result="$result"
    }
    for ((i = 0; i < num_sections; i++)); do
        IFS=',' read -r sec_name sec_type sec_off sec_size <<< "${sections[$i]}"
        local actual_name=""
        _rb_get_string "$shstrtab_hex" "$((sec_name * 2))"
        actual_name="$_rb_str_result"
        if [[ "$actual_name" == "$section_name" ]]; then
            local section_content=""
            read_file_hex "$file_path" "$sec_off" "$sec_size" "section_content"
            output_n="$section_content"
            return 0
        fi
    done
    output_n=""
    return 0
}

combine_sections() {
    local objects_ref="$1"
    local combined_text_ref="$2"
    local combined_data_ref="$3"
    local -n objects_n="$1"
    local -n combined_text_n="$2"
    local -n combined_data_n="$3"
    combined_text_n=""
    combined_data_n=""
    for obj_file in "${objects_n[@]}"; do
        if [[ ! -f "$obj_file" ]]; then
            error_msg "object file does not exist: $obj_file"
            return 1
        fi
        if ! is_elf_object "$obj_file"; then
            error_msg "file is not a relocatable object file: $obj_file"
            return 1
        fi
        local text_content
        extract_section_by_name "$obj_file" ".text" "text_content"
        [[ -n "$text_content" ]] && combined_text_n+="$text_content"
        local data_content
        extract_section_by_name "$obj_file" ".data" "data_content"
        [[ -n "$data_content" ]] && combined_data_n+="$data_content"
    done
    return 0
}
