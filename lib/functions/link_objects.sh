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
    local cur_text_pos=0
    for obj_file in "${objects[@]}"; do
        local obj_text=""
        extract_section_by_name "$obj_file" ".text" "obj_text"
        local obj_text_size=$((${#obj_text} / 2))
        local obj_data=""
        extract_section_by_name "$obj_file" ".data" "obj_data"
        local obj_data_size=$((${#obj_data} / 2))
        local relocs=()
        parse_relocations "$obj_file" "relocs"
        for reloc_entry in "${relocs[@]}"; do
            IFS=':' read -r r_offset sym_name r_type r_addend <<< "$reloc_entry"
            local sym_final_addr=0
            local sym_obj_idx=-1
            local sym_obj_off=0
            local sym_shndx=0
            local header_prefix="lk"
            parse_elf_header "$obj_file" "$header_prefix"
            local sections
            parse_section_headers "$obj_file" "${lk_shoff}" "${lk_num_sections}" "sections"
            local symtab_off=0 symtab_size=0
            local strtab_off=0 strtab_size=0
            for ((si = 0; si < lk_num_sections; si++)); do
                IFS=',' read -r sn st so ssz <<< "${sections[$si]}"
                [[ $st -eq 2 ]] && { symtab_off=$so; symtab_size=$ssz; }
            done
            [[ $symtab_size -eq 0 ]] && continue
            local symtab_hex=""
            read_file_hex "$obj_file" "$symtab_off" "$symtab_size" "symtab_hex"
            local strtab_hex=""
            for ((si = 0; si < lk_num_sections; si++)); do
                IFS=',' read -r sn st so ssz <<< "${sections[$si]}"
                if [[ $st -eq 3 && $so -ne 0 ]]; then
                    strtab_off=$so
                    strtab_size=$ssz
                    break
                fi
            done
            [[ -n "$strtab_hex" ]] || read_file_hex "$obj_file" "$strtab_off" "$strtab_size" "strtab_hex"
            local sym_idx=0
            local found_sym=0
            local spos=0
            while ((spos + 48 <= ${#symtab_hex})); do
                local entry_hex="${symtab_hex:$spos:48}"
                local st_name_hex="${entry_hex:0:8}"
                local st_name=""
                for ((i = 6; i >= 0; i -= 2)); do
                    st_name+="${st_name_hex:$i:2}"
                done
                local st_name_val=$((16#$st_name))
                local st_shndx_hex="${entry_hex:24:4}"
                local st_shndx=""
                for ((i = 2; i >= 0; i -= 2)); do
                    st_shndx+="${st_shndx_hex:$i:2}"
                done
                local st_shndx_val=$((16#$st_shndx))
                local st_value_hex="${entry_hex:32:16}"
                local st_value=""
                for ((i = 14; i >= 0; i -= 2)); do
                    st_value+="${st_value_hex:$i:2}"
                done
                local st_value_val=$((16#$st_value))
                local sname=""
                local npos=$((st_name_val * 2))
                while ((npos + 1 < ${#strtab_hex})); do
                    local bh="${strtab_hex:$npos:2}"
                    [[ "$bh" == "00" ]] && break
                    local bv=$((16#$bh))
                    ((bv >= 32 && bv < 127)) && sname+=$(printf "\\$(printf '%03o' "$bv")")
                    npos=$((npos + 2))
                done
                if [[ "$sname" == "$sym_name" ]]; then
                    sym_shndx=$st_shndx_val
                    sym_obj_off=$st_value_val
                    found_sym=1
                    break
                fi
                spos=$((spos + 48))
                sym_idx=$((sym_idx + 1))
            done
            [[ $found_sym -eq 0 ]] && continue
            if [[ $sym_shndx -eq 1 ]]; then
                sym_final_addr=$((text_vaddr + text_offsets[obj_idx] + sym_obj_off))
            elif [[ $sym_shndx -eq 2 ]]; then
                sym_final_addr=$((data_vaddr + data_offsets[obj_idx] + sym_obj_off))
            fi
            sym_final_addr=$((sym_final_addr + r_addend))
            local patch_pos=$((r_offset + text_offsets[obj_idx]))
            local patch_hex=$(printf "%016x" "$sym_final_addr")
            local patch_le=""
            for ((i = 14; i >= 0; i -= 2)); do
                patch_le+="${patch_hex:$i:2}"
            done
            local hex_pos=$((patch_pos * 2))
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
