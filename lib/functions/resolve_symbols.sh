#!/usr/bin/env bash

# resolve symbols across object files
resolve_symbols() {
    local objects_ref="$1"
    local resolved_ref="$2"
    local unresolved_ref="$3"
    local -n objects_n="$1"
    local -n resolved_n="$2"
    local -n unresolved_n="$3"
    unset all_symbols defined_symbols 2>/dev/null
    declare -gA all_symbols=()
    declare -gA defined_symbols=()
    for obj_file in "${objects_n[@]}"; do
        declare -A obj_symbols=()
        declare -A obj_definitions=()
        if ! get_elf_symbols "$obj_file" "obj_symbols" "obj_definitions"; then
            error_msg "failed to parse symbols from object file: $obj_file"
            return 1
        fi
        for sym_name in "${!obj_definitions[@]}"; do
            defined_symbols["$sym_name"]="${obj_definitions[$sym_name]}"
            all_symbols["$sym_name"]="defined:${obj_definitions[$sym_name]}"
        done
        for sym_name in "${!obj_symbols[@]}"; do
            [[ "${obj_symbols[$sym_name]}" == "undefined" ]] && all_symbols["$sym_name"]="undefined"
        done
    done
    unresolved_n=()
    for sym_name in "${!all_symbols[@]}"; do
        if [[ "${all_symbols[$sym_name]}" == "undefined" ]]; then
            if [[ -n "${defined_symbols[$sym_name]:-}" ]]; then
                resolved_n["$sym_name"]="${defined_symbols[$sym_name]}"
            else
                unresolved_n+=("$sym_name")
            fi
        fi
    done
    unset all_symbols
    unset defined_symbols
    if [[ ${#unresolved_n[@]} -gt 0 ]]; then
        error_msg "undefined symbols: ${unresolved_n[*]}"
        return 1
    fi
    return 0
}
