#!/usr/bin/env bash

# macro preprocessor for assembly code - supports NASM-style %macro/%endmacro
preprocess_macros() {
    local input_code="$1"
    local processed_code=""

    # Read input line by line
    local lines
    readarray -t lines <<<"$input_code"

    # Associative arrays for macro storage
    declare -A macro_bodies=()      # macro_name -> body lines (newline-separated)
    declare -A macro_param_counts=() # macro_name -> expected param count
    local in_macro=0
    local current_macro_name=""
    local current_macro_body=""
    local current_macro_params=0

    # First pass: collect all macro definitions
    local collected_lines=()
    for line in "${lines[@]}"; do
        local trimmed_line
        trimmed_line=$(trim_string "$line")

        if [[ $in_macro -eq 1 ]]; then
            if [[ "$trimmed_line" =~ ^%endmacro ]]; then
                macro_bodies["$current_macro_name"]="$current_macro_body"
                macro_param_counts["$current_macro_name"]=$current_macro_params
                in_macro=0
                current_macro_name=""
                current_macro_body=""
            else
                if [[ -n "$current_macro_body" ]]; then
                    current_macro_body+=$'\n'"$line"
                else
                    current_macro_body="$line"
                fi
            fi
            continue
        fi

        if [[ "$trimmed_line" =~ ^%macro[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+([0-9]+) ]]; then
            current_macro_name="${BASH_REMATCH[1]}"
            current_macro_params="${BASH_REMATCH[2]}"
            in_macro=1
            current_macro_body=""
            continue
        fi

        collected_lines+=("$line")
    done

    # Second pass: expand macro invocations
    for line in "${collected_lines[@]}"; do
        local trimmed_line
        trimmed_line=$(trim_string "$line")

        # Skip comments and empty lines
        if [[ "$trimmed_line" =~ ^[[:space:]]*# ]] || [[ "$trimmed_line" =~ ^[[:space:]]*\; ]] || [[ -z "$trimmed_line" ]]; then
            processed_code+="$line"$'\n'
            continue
        fi

        # Check if this line is a macro invocation
        local expanded=0
        for macro_name in "${!macro_bodies[@]}"; do
            if [[ "$trimmed_line" =~ ^${macro_name}([[:space:]]+(.*))?$ ]]; then
                local args_str="${BASH_REMATCH[2]}"
                local expected_params=${macro_param_counts[$macro_name]}

                # Parse comma-separated arguments
                local -a args=()
                if [[ -n "$args_str" ]]; then
                    IFS=',' read -ra args <<< "$args_str"
                    # Trim whitespace from each argument
                    for i in "${!args[@]}"; do
                        args[$i]=$(trim_string "${args[$i]}")
                    done
                fi

                if [[ ${#args[@]} -ne $expected_params ]]; then
                    error_msg "macro '$macro_name' expects $expected_params arguments, got ${#args[@]}"
                    return 1
                fi

                # Expand the macro body
                local macro_body="${macro_bodies[$macro_name]}"
                local expanded_body="$macro_body"

                # Replace %1, %2, etc. with actual arguments
                for ((i = 1; i <= expected_params; i++)); do
                    local param_ref="%$i"
                    local param_value="${args[$((i - 1))]}"
                    # Replace all occurrences of %N with the argument
                    expanded_body="${expanded_body//$param_ref/$param_value}"
                done

                processed_code+="$expanded_body"$'\n'
                expanded=1
                break
            fi
        done

        if [[ $expanded -eq 0 ]]; then
            processed_code+="$line"$'\n'
        fi
    done

    echo -n "$processed_code"
    return 0
}