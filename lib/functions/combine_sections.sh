#!/usr/bin/env bash

# extract section data from an elf object file by section name
# usage: extract_section_by_name <file_path> <section_name> <output_hex_ref>
extract_section_by_name() {
    local file_path="$1"
    local section_name="$2"
    local output_ref="$3"
    local -n output_n="$3"

    # get elf header info
    local header_prefix="extract"
    if ! parse_elf_header "$file_path" "$header_prefix"; then
        return 1
    fi

    local shoff num_sections shstrndx
    shoff="${extract_shoff}"
    num_sections="${extract_num_sections}"
    shstrndx="${extract_shstrndx}"

    # get section headers
    local sections
    parse_section_headers "$file_path" "$shoff" "$num_sections" "sections" || return 1

    # find the shstrtab section info
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

    # read the shstrtab into a hex string
    local shstrtab_hex=""
    read_file_hex "$file_path" "$shstrtab_offset" "$shstrtab_size" "shstrtab_hex"

    # helper: get null-terminated string from hex at offset
    _rb_get_string() {
        local hex_str="$1"
        local str_offset="$2"
        local result=""
        local pos=$str_offset
        while ((pos + 1 < ${#hex_str})); do
            local byte_hex="${hex_str:$pos:2}"
            if [[ "$byte_hex" == "00" ]]; then
                break
            fi
            local byte_val=$((16#$byte_hex))
            if ((byte_val >= 32 && byte_val < 127)); then
                result+=$(printf "\\$(printf '%03o' "$byte_val")")
            fi
            pos=$((pos + 2))
        done
        _rb_str_result="$result"
    }

    # iterate through sections to find the requested name
    for ((i = 0; i < num_sections; i++)); do
        IFS=',' read -r sec_name sec_type sec_off sec_size <<< "${sections[$i]}"

        # get the actual section name from the string table
        local actual_name=""
        _rb_get_string "$shstrtab_hex" "$((sec_name * 2))"
        actual_name="$_rb_str_result"

        if [[ "$actual_name" == "$section_name" ]]; then
            # read section content
            local section_content=""
            read_file_hex "$file_path" "$sec_off" "$sec_size" "section_content"
            output_n="$section_content"
            return 0
        fi
    done

    # section not found, return empty
    output_n=""
    return 0
}

# combine sections from multiple object files into single hex strings
# usage: combine_sections <objects_array_ref> <combined_text_ref> <combined_data_ref>
combine_sections() {
    local objects_ref="$1"
    local combined_text_ref="$2"
    local combined_data_ref="$3"
    local -n objects_n="$1"
    local -n combined_text_n="$2"
    local -n combined_data_n="$3"

    # initialize output variables
    combined_text_n=""
    combined_data_n=""

    # process each object file
    for obj_file in "${objects_n[@]}"; do
        if [[ ! -f "$obj_file" ]]; then
            error_msg "object file does not exist: $obj_file"
            return 1
        fi

        # check that it's a proper elf object file
        if ! is_elf_object "$obj_file"; then
            error_msg "file is not a relocatable object file: $obj_file"
            return 1
        fi

        # extract .text section by name
        local text_content
        extract_section_by_name "$obj_file" ".text" "text_content"
        if [[ -n "$text_content" ]]; then
            combined_text_n+="$text_content"
        fi

        # extract .data section by name
        local data_content
        extract_section_by_name "$obj_file" ".data" "data_content"
        if [[ -n "$data_content" ]]; then
            combined_data_n+="$data_content"
        fi
    done

    return 0
}