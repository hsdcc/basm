#!/usr/bin/env bash

# Simple macro preprocessor for assembly code
preprocess_macros() {
    local input_code="$1"
    local processed_code=""
    
    # Read input line by line
    local lines
    readarray -t lines <<<"$input_code"
    
    for line in "${lines[@]}"; do
        local trimmed_line
        trimmed_line=$(trim_string "$line")
        
        # Skip lines that start with # or ; (comments)
        local first_char="${trimmed_line:0:1}"
        if [[ "$trimmed_line" =~ ^[[:space:]]*# ]] || [[ "$trimmed_line" =~ ^[[:space:]]*\; ]] || [[ -z "$trimmed_line" ]]; then
            # Add the comment line to processed code but as valid assembly (by just passing it through)
            processed_code+="$line"$'\n'
            continue
        fi
        
        # Check if the line contains a macro definition or invocation
        if [[ "$trimmed_line" =~ ^%macro ]]; then
            # For now, just return the original code as-is until we have proper macro implementation
            echo -n "$input_code"
            return 0
        elif [[ "$trimmed_line" =~ ^%[a-zA-Z_][a-zA-Z0-9_]*[[:space:]] ]]; then
            # Might be a macro invocation
            echo -n "$input_code"
            return 0
        fi
        
        # Regular line - add to processed code
        processed_code+="$line"$'\n'
    done
    
    # If we reach here, no macros were detected, so return processed code
    echo -n "$processed_code"
    return 0
}