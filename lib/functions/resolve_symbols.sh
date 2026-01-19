#!/usr/bin/env bash

# resolve symbols between multiple object files
# usage: resolve_symbols <objects_array_ref> <resolved_symbols_assoc_array_ref> <unresolved_symbols_array_ref>
resolve_symbols() {
    local objects_ref="$1"
    local resolved_ref="$2"
    local unresolved_ref="$3"
    local -n objects_n="$1"
    local -n resolved_n="$2"
    local -n unresolved_n="$3"
    
    # initialize associative array to collect all symbols
    declare -gA all_symbols=()
    declare -gA defined_symbols=()
    
    # collect symbols from all object files
    for obj_file in "${objects_n[@]}"; do
        declare -A obj_symbols=()
        declare -A obj_definitions=()
        
        if ! get_elf_symbols "$obj_file" "obj_symbols" "obj_definitions"; then
            error_msg "failed to parse symbols from object file: $obj_file"
            return 1
        fi
        
        # add defined symbols to global defined_symbols
        for sym_name in "${!obj_definitions[@]}"; do
            defined_symbols["$sym_name"]="${obj_definitions[$sym_name]}"
            all_symbols["$sym_name"]="defined:${obj_definitions[$sym_name]}"
        done
        
        # add undefined symbols to global symbol list
        for sym_name in "${!obj_symbols[@]}"; do
            if [[ "${obj_symbols[$sym_name]}" == "undefined" ]]; then
                all_symbols["$sym_name"]="undefined"
            fi
        done
    done
    
    # check for undefined symbols and see if they are defined elsewhere
    unresolved_n=()
    for sym_name in "${!all_symbols[@]}"; do
        if [[ "${all_symbols[$sym_name]}" == "undefined" ]]; then
            if [[ -n "${defined_symbols[$sym_name]:-}" ]]; then
                # symbol is defined in another file, resolve it
                resolved_n["$sym_name"]="${defined_symbols[$sym_name]}"
            else
                # symbol is genuinely undefined
                unresolved_n+=("$sym_name")
            fi
        fi
    done
    
    # clean up temporary global arrays
    unset all_symbols
    unset defined_symbols
    
    # if there are unresolved symbols, return error
    if [[ ${#unresolved_n[@]} -gt 0 ]]; then
        error_msg "undefined symbols: ${unresolved_n[*]}"
        return 1
    fi
    
    return 0
}