#!/usr/bin/env bash

generate_relocation_section() {
    local relocations_ref="$1"
    local labels_ref="$2"
    local data_labels_ref="$3"
    local rodata_labels_ref="$4"
    local externals_ref="$5"
    local bss_labels_ref="$6"
    local output_ref="$7"
    local -n _gr_relocs="$1"
    local -n _gr_labels="$2"
    local -n _gr_data_labels="$3"
    local -n _gr_rodata_labels="$4"
    local -n _gr_externals="$5"
    local -n _gr_bss_labels="$6"
    local -n _gr_output="$7"
    _gr_output=""
    local sym_idx=1
    for label_name in "${!_gr_labels[@]}"; do
        sym_idx=$((sym_idx + 1))
    done
    local data_sym_start=$sym_idx
    for label_name in "${!_gr_data_labels[@]}"; do
        sym_idx=$((sym_idx + 1))
    done
    local rodata_sym_start=$sym_idx
    for label_name in "${!_gr_rodata_labels[@]}"; do
        sym_idx=$((sym_idx + 1))
    done
    local bss_sym_start=$sym_idx
    for label_name in "${!_gr_bss_labels[@]}"; do
        sym_idx=$((sym_idx + 1))
    done
    local ext_sym_start=$sym_idx
    for ext_name in "${!_gr_externals[@]}"; do
        sym_idx=$((sym_idx + 1))
    done
    for reloc_entry in "${_gr_relocs[@]}"; do
        IFS=':' read -r r_offset sym_name r_type r_addend <<< "$reloc_entry"
        local sym_index=0
        local found=0
        local idx=1
        for label_name in "${!_gr_labels[@]}"; do
            [[ "$label_name" == "$sym_name" ]] && { sym_index=$idx; found=1; break; }
            idx=$((idx + 1))
        done
        if [[ $found -eq 0 ]]; then
            idx=$data_sym_start
            for label_name in "${!_gr_data_labels[@]}"; do
                [[ "$label_name" == "$sym_name" ]] && { sym_index=$idx; found=1; break; }
                idx=$((idx + 1))
            done
        fi
        if [[ $found -eq 0 ]]; then
            idx=$rodata_sym_start
            for label_name in "${!_gr_rodata_labels[@]}"; do
                [[ "$label_name" == "$sym_name" ]] && { sym_index=$idx; found=1; break; }
                idx=$((idx + 1))
            done
        fi
        if [[ $found -eq 0 ]]; then
            idx=$bss_sym_start
            for label_name in "${!_gr_bss_labels[@]}"; do
                [[ "$label_name" == "$sym_name" ]] && { sym_index=$idx; found=1; break; }
                idx=$((idx + 1))
            done
        fi
        if [[ $found -eq 0 ]]; then
            idx=$ext_sym_start
            for ext_name in "${!_gr_externals[@]}"; do
                [[ "$ext_name" == "$sym_name" ]] && { sym_index=$idx; found=1; break; }
                idx=$((idx + 1))
            done
        fi
        [[ $found -eq 0 ]] && continue
        local r_offset_hex=$(printf "%016x" "$r_offset")
        local r_info=$(( (sym_index << 32) | r_type ))
        local r_info_hex=$(printf "%016x" "$r_info")
        local r_addend_hex=$(printf "%016x" "$r_addend")
        _gr_output+=$(reverse_endian "$r_offset_hex")
        _gr_output+=$(reverse_endian "$r_info_hex")
        _gr_output+=$(reverse_endian "$r_addend_hex")
    done
    return 0
}
