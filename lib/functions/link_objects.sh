#!/usr/bin/env bash

# Basic static linker - combines multiple object files into a single executable
link_objects() {
    local objects=("$@")  # Array of object file paths
    local output_file="${objects[-1]}"  # Last argument is the output file
    unset 'objects[-1]'  # Remove output file from the list
    
    if [[ ${#objects[@]} -lt 1 ]]; then
        error_msg "need at least one object file to link"
        return 1
    fi
    
    # For now, we'll just concatenate the text sections from all object files
    # In a real linker, we'd resolve symbols, relocate addresses, combine sections, etc.
    
    local tmpf
    tmpf="$(mktemp)" || { error_msg "failed to create temporary link file"; return 1; }
    
    # For our basic linker, we'll just pick the first object and use its content
    # In a real linker, we'd need to parse each ELF object file, combine sections,
    # resolve symbols, and create a proper executable
    
    # For now, just copy the first object as-is to test the function integration
    cp "${objects[0]}" "$tmpf"
    
    # Make it executable
    chmod +x "$tmpf"
    mv -f "$tmpf" "$output_file"
    
    return 0
}