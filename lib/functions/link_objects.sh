#!/usr/bin/env bash

# link object files into executable
link_objects() {
    local objects=("$@")
    local output_file="${objects[-1]}"
    unset 'objects[-1]'
    if [[ ${#objects[@]} -lt 1 ]]; then
        error_msg "need at least one object file to link"
        return 1
    fi
    if [[ ${#objects[@]} -eq 1 ]]; then
        if ! is_elf_object "${objects[0]}"; then
            error_msg "file is not a proper ELF object file: ${objects[0]}"
            return 1
        fi
        local obj_text=""
        extract_section_by_name "${objects[0]}" ".text" "obj_text"
        local obj_data=""
        extract_section_by_name "${objects[0]}" ".data" "obj_data"
        local text_size=$((${#obj_text} / 2))
        local data_size=$((${#obj_data} / 2))
        local file_text_off=0x200
        local file_data_off=$((file_text_off + text_size))
        local text_vaddr=0x400000+file_text_off
        local data_vaddr=$((text_vaddr + text_size))
        local entry_vaddr=$text_vaddr
        local combined_text="$obj_text"
        local combined_data="$obj_data"
        local relocs=()
        parse_relocations "${objects[0]}" "relocs"
        for reloc_entry in "${relocs[@]}"; do
            IFS=':' read -r r_offset sym_name r_type r_addend <<< "$reloc_entry"
            local sym_final_addr=0
            if [[ -n "${data_label_off[$sym_name]:-}" ]]; then
                sym_final_addr=$((data_vaddr + data_label_off[$sym_name] + r_addend))
            elif [[ -n "${labels[$sym_name]:-}" ]]; then
                sym_final_addr=$((text_vaddr + labels[$sym_name] + r_addend))
            else
                continue
            fi
            local patch_hex=$(printf "%016x" "$sym_final_addr")
            local patch_le=""
            for ((i = 14; i >= 0; i -= 2)); do patch_le+="${patch_hex:$i:2}"; done
            local hex_pos=$((r_offset * 2))
            combined_text="${combined_text:0:$hex_pos}${patch_le}${combined_text:$((hex_pos + 16))}"
        done
        local header_hex
        header_hex=$(build_elf_header "$entry_vaddr" "$file_text_off" "$text_vaddr" "$data_size" "$file_data_off")
        write_final_executable "$header_hex" "$combined_text" "$combined_data" \
            "$file_text_off" "$text_size" "$data_size" "$file_data_off" "$output_file"
        return 0
    fi
    for obj_file in "${objects[@]}"; do
        if [[ ! -f "$obj_file" ]]; then
            error_msg "object file does not exist: $obj_file"
            return 1
        fi
        if ! is_elf_object "$obj_file"; then
            error_msg "file is not a proper ELF object file: $obj_file"
            return 1
        fi
    done
    declare -A resolved_symbols=()
    declare -a unresolved_symbols=()
    if ! resolve_symbols "objects" "resolved_symbols" "unresolved_symbols"; then
        error_msg "failed to resolve symbols"
        return 1
    fi
    if [[ ${#unresolved_symbols[@]} -gt 0 ]]; then
        error_msg "linking failed: undefined symbols: ${unresolved_symbols[*]}"
        return 1
    fi
    local combined_text=""
    local combined_data=""
    local -a text_offsets=()
    local -a data_offsets=()
    local cur_text=0
    local cur_data=0
    for obj_file in "${objects[@]}"; do
        text_offsets+=($cur_text)
        data_offsets+=($cur_data)
        local obj_text=""
        extract_section_by_name "$obj_file" ".text" "obj_text"
        [[ -n "$obj_text" ]] && combined_text+="$obj_text"
        cur_text=$((cur_text + ${#obj_text} / 2))
        local obj_data=""
        extract_section_by_name "$obj_file" ".data" "obj_data"
        [[ -n "$obj_data" ]] && combined_data+="$obj_data"
        cur_data=$((cur_data + ${#obj_data} / 2))
    done
    local text_size=$((${#combined_text} / 2))
    local data_size=$((${#combined_data} / 2))
    local file_text_off=0x200
    local file_data_off=$((file_text_off + text_size))
    local text_vaddr=0x400000+file_text_off
    local data_vaddr=$((text_vaddr + text_size))
    local entry_vaddr=$text_vaddr
    local obj_idx=0
    for obj_file in "${objects[@]}"; do
        local relocs=()
        parse_relocations "$obj_file" "relocs"
        for reloc_entry in "${relocs[@]}"; do
            IFS=':' read -r r_offset sym_name r_type r_addend <<< "$reloc_entry"
            local sym_final_addr=0
            if [[ -n "${resolved_symbols[$sym_name]:-}" ]]; then
                local res="${resolved_symbols[$sym_name]}"
                IFS=':' read -r res_shndx res_off <<< "$res"
                if [[ $res_shndx -eq 1 ]]; then
                    local cum=0
                    for ((oi=0; oi<${#objects[@]}; oi++)); do
                        local ot=""
                        extract_section_by_name "${objects[$oi]}" ".text" "ot"
                        local ots=$((${#ot} / 2))
                        if ((cum + ots > res_off)); then
                            res_off=$((res_off - cum))
                            break
                        fi
                        cum=$((cum + ots))
                    done
                    sym_final_addr=$((text_vaddr + res_off))
                elif [[ $res_shndx -eq 2 ]]; then
                    local cum=0
                    for ((oi=0; oi<${#objects[@]}; oi++)); do
                        local od=""
                        extract_section_by_name "${objects[$oi]}" ".data" "od"
                        local ods=$((${#od} / 2))
                        if ((cum + ods > res_off)); then
                            res_off=$((res_off - cum))
                            break
                        fi
                        cum=$((cum + ods))
                    done
                    sym_final_addr=$((data_vaddr + res_off))
                fi
            elif [[ -n "${data_label_off[$sym_name]:-}" ]]; then
                sym_final_addr=$((data_vaddr + data_offsets[obj_idx] + data_label_off[$sym_name] + r_addend))
            elif [[ -n "${labels[$sym_name]:-}" ]]; then
                sym_final_addr=$((text_vaddr + text_offsets[obj_idx] + labels[$sym_name] + r_addend))
            else
                continue
            fi
            local patch_hex=$(printf "%016x" "$sym_final_addr")
            local patch_le=""
            for ((i = 14; i >= 0; i -= 2)); do patch_le+="${patch_hex:$i:2}"; done
            local hex_pos=$(((text_offsets[obj_idx] + r_offset) * 2))
            combined_text="${combined_text:0:$hex_pos}${patch_le}${combined_text:$((hex_pos + 16))}"
        done
        obj_idx=$((obj_idx + 1))
    done
    text_size=$((${#combined_text} / 2))
    data_size=$((${#combined_data} / 2))
    file_data_off=$((file_text_off + text_size))
    local header_hex
    header_hex=$(build_elf_header "$entry_vaddr" "$file_text_off" "$text_vaddr" "$data_size" "$file_data_off")
    write_final_executable "$header_hex" "$combined_text" "$combined_data" \
        "$file_text_off" "$text_size" "$data_size" "$file_data_off" "$output_file"
    return 0
}
