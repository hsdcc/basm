#!/usr/bin/env bash

# preprocess macros
preprocess_macros() {
    local input_code="$1"
    local processed_code=""
    local lines
    readarray -t lines <<<"$input_code"
    declare -A macro_bodies=()
    declare -A macro_param_counts=()
    local in_macro=0
    local current_macro_name=""
    local current_macro_body=""
    local current_macro_params=0
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
                [[ -n "$current_macro_body" ]] && current_macro_body+=$'\n'"$line" || current_macro_body="$line"
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
    for line in "${collected_lines[@]}"; do
        local trimmed_line
        trimmed_line=$(trim_string "$line")
        if [[ "$trimmed_line" =~ ^[[:space:]]*# ]] || [[ "$trimmed_line" =~ ^[[:space:]]*\; ]] || [[ -z "$trimmed_line" ]]; then
            processed_code+="$line"$'\n'
            continue
        fi
        local expanded=0
        for macro_name in "${!macro_bodies[@]}"; do
            if [[ "$trimmed_line" =~ ^${macro_name}([[:space:]]+(.*))?$ ]]; then
                local args_str="${BASH_REMATCH[2]}"
                local expected_params=${macro_param_counts[$macro_name]}
                local -a args=()
                if [[ -n "$args_str" ]]; then
                    IFS=',' read -ra args <<< "$args_str"
                    for i in "${!args[@]}"; do
                        args[$i]=$(trim_string "${args[$i]}")
                    done
                fi
                if [[ ${#args[@]} -ne $expected_params ]]; then
                    error_msg "macro '$macro_name' expects $expected_params arguments, got ${#args[@]}"
                    return 1
                fi
                local macro_body="${macro_bodies[$macro_name]}"
                local expanded_body="$macro_body"
                for ((i = 1; i <= expected_params; i++)); do
                    local param_ref="%$i"
                    local param_value="${args[$((i - 1))]}"
                    expanded_body="${expanded_body//$param_ref/$param_value}"
                done
                processed_code+="$expanded_body"$'\n'
                expanded=1
                break
            fi
        done
        [[ $expanded -eq 0 ]] && processed_code+="$line"$'\n'
    done
    echo -n "$processed_code"
    return 0
}
