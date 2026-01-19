#!/usr/bin/env bash

# extract section data from an elf object file
# usage: extract_section_data <file_path> <section_type> <output_hex_ref>
extract_section_data() {
    local file_path="$1"
    local section_type="$2"  # 0x1 for progbits (text/data), 0x8 for nobits (bss)
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
    
    # open file to read section content
    local fd
    exec 9< "$file_path"
    
    # iterate through sections to find the requested type
    for ((i=0; i<num_sections; i++)); do
        IFS=',' read -r sec_name sec_type sec_offset sec_size <<< "${sections[$i]}"
        
        if [[ $sec_type -eq $section_type ]]; then
            # seek to section offset
            exec 9<&-
            exec 9< "$file_path"
            
            # skip to section offset
            for ((j=0; j<sec_offset; j++)); do
                read -n1 -u 9 dummy_byte
            done
            
            # read section content
            local section_content=""
            for ((j=0; j<sec_size; j++)); do
                read -n1 -u 9 byte
                local byte_val
                byte_val=$(printf "%02x" "'$byte")
                section_content+="$byte_val"
            done
            
            output_n="$section_content"
            exec 9<&-
            return 0
        fi
    done
    
    exec 9<&-
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
        
        # extract .text section (progbits = 0x1)
        local text_content
        extract_section_data "$obj_file" 1 "text_content"
        if [[ -n "$text_content" ]]; then
            combined_text_n+="$text_content"
        fi
        
        # extract .data section (progbits = 0x1) - though we distinguish by position/context
        local data_content
        extract_section_data "$obj_file" 1 "data_content"  # same type but different sections
        if [[ -n "$data_content" ]]; then
            combined_data_n+="$data_content"
        fi
    done
    
    return 0
}