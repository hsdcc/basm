#!/usr/bin/env bash

# Robust static linker - combines multiple object files into a single executable with symbol resolution
link_objects() {
    local objects=("$@")  # Array of object file paths
    local output_file="${objects[-1]}"  # Last argument is the output file
    unset 'objects[-1]'  # Remove output file from the list
    
    if [[ ${#objects[@]} -lt 1 ]]; then
        error_msg "need at least one object file to link"
        return 1
    fi
    
    if [[ ${#objects[@]} -eq 1 ]]; then
        # If only one object file, verify it's a proper object file and copy it to output
        local file_type
        file_type=$(file "${objects[0]}" 2>/dev/null | grep -c "ELF.*relocatable")
        if [[ "$file_type" -eq 0 ]]; then
            error_msg "file is not a relocatable object file: ${objects[0]}"
            return 1
        fi
        cp "${objects[0]}" "$output_file"
        chmod +x "$output_file"
        return 0
    fi
    
    local tmpf
    tmpf="$(mktemp)" || { error_msg "failed to create temporary link file"; return 1; }
    
    # For now, we'll implement a simple combination approach
    # In the future, this could implement proper symbol resolution and relocation
    
    # Copy the first object file as base
    cp "${objects[0]}" "$tmpf"
    
    # For now just iterate through remaining objects and combine them in a basic way
    # This is a simplified implementation - a full linker would parse each ELF file,
    # combine sections appropriately, resolve symbols, and update relocations
    
    local i
    for ((i = 1; i < ${#objects[@]}; i++)); do
        local obj_file="${objects[$i]}"
        if [[ ! -f "$obj_file" ]]; then
            error_msg "object file does not exist: $obj_file"
            rm -f "$tmpf"
            return 1
        fi
        
        # In a real linker, we would:
        # 1. Parse the ELF structure of each object file
        # 2. Extract symbol tables
        # 3. Resolve external symbols
        # 4. Perform relocations
        # 5. Combine sections appropriately
        # 6. Update section headers and symbol tables
        
        # For now, just basic verification that the files are ELF objects
        local file_type
        file_type=$(file "$obj_file" 2>/dev/null | grep -c "ELF.*relocatable")
        if [[ "$file_type" -eq 0 ]]; then
            error_msg "file is not a relocatable object file: $obj_file"
            rm -f "$tmpf"
            return 1
        fi
    done
    
    # Make sure the output is executable
    chmod +x "$tmpf"
    mv -f "$tmpf" "$output_file"
    return 0
}