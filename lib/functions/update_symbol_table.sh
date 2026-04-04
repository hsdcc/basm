#!/usr/bin/env bash

# update symbol table in combined object file after section merging
# usage: update_symbol_table <orig_symtab_ref> <section_offset> <updated_symtab_ref>
update_symbol_table() {
    local orig_symtab_ref="$1"
    local section_offset="$2"
    local updated_symtab_ref="$3"
    local -n orig_symtab_n="$1"
    local -n updated_symtab_n="$3"

    # update each symbol's address by adding the section offset
    # this accounts for where the symbol's section ended up after combining
    updated_symtab_n=()
    for sym_entry in "${orig_symtab_n[@]}"; do
        # parse symbol entry: format is "name:address:section_index"
        IFS=':' read -r sym_name sym_addr sym_shndx <<< "$sym_entry"

        # only update addresses for symbols in allocatable sections (shndx > 0)
        # shndx 0 is undefined/absolute, shndx 0xfff1 is common, etc.
        if [[ "$sym_shndx" -gt 0 && "$sym_shndx" -lt 0xff00 ]]; then
            local new_addr=$((sym_addr + section_offset))
            updated_symtab_n+=("${sym_name}:${new_addr}:${sym_shndx}")
        else
            # keep undefined/absolute/common symbols unchanged
            updated_symtab_n+=("$sym_entry")
        fi
    done

    return 0
}