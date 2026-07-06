#!/usr/bin/env bash
first_pass() {
    local raw_lines_ref="$1"
    local code_str="$2"
    local -n lines_ref="$1"
    
    
    data_bytes=""
    rodata_bytes=""
    bss_bytes=""
    text_ins=()
    text_bytes_len=0
    rodata_bytes_len=0
    bss_bytes_len=0
    in_section=""
    line_number=0
    
    
    unset labels data_label_off rodata_label_off bss_label_off equs externals relocations 2>/dev/null
    declare -gA labels=()
    declare -gA data_label_off=()
    declare -gA rodata_label_off=()
    declare -gA bss_label_off=()
    declare -gA equs=()
    declare -gA externals=()
    declare -ga relocations=()  
    
    
    mapfile -t lines_ref <<<"$code_str"
    
    for raw in "${lines_ref[@]}"; do
        line_number=$((line_number + 1))
        line="${raw%%;*}"
        line="$(trim_string "$line")"
        [ -z "$line" ] && continue
        case "$line" in
        section\ .data)
            in_section="data"
            continue
            ;;
        section\ .text)
            in_section="text"
            continue
            ;;
        section\ .rodata)
            in_section="rodata"
            continue
            ;;
        section\ .bss)
            in_section="bss"
            continue
            ;;
        section\ .*)
            
            in_section="${line#section .}"
            in_section=$(trim_string "$in_section")
            continue
            ;;
        global\ *) continue ;;
        extern\ *)
            local ext_list="${line#extern }"
            IFS=',' read -ra ext_syms <<< "$ext_list"
            for ext_sym in "${ext_syms[@]}"; do
                ext_sym=$(trim_string "$ext_sym")
                [[ -n "$ext_sym" ]] && externals["$ext_sym"]=1
            done
            continue
            ;;
        esac
        if [[ "$in_section" == "data" ]]; then
            if [[ "$line" =~ $equ_pattern ]]; then
                name="${BASH_REMATCH[1]}"
                ref="${BASH_REMATCH[2]}"
                if [[ -z "${data_label_off[$ref]:-}" ]]; then
                    error_msg "at line $line_number: unknown equ reference '$ref' - label not defined in .data section"
                    return 1
                fi
                cur_off=$((${#data_bytes} / 2))
                val=$((cur_off - data_label_off[$ref]))
                equs["$name"]=$val
                continue
            fi
            if [[ "$line" =~ $db_pattern ]]; then
                name="${BASH_REMATCH[1]}"
                txt="${BASH_REMATCH[2]}"
                extra="${BASH_REMATCH[4]}"
                
                txt="${txt//\\/\\\\x5c}"    
                txt="${txt//
/\\n}"          
                txt="${txt//\"/\\\"}"           
                hex=""
                i=0
                while [ "$i" -lt ${#txt} ]; do
                    ch="${txt:$i:1}"
                    oc=$(printf "%d" "'$ch")
                    hex+="$(printf "%02x" "$oc")"
                    i=$((i + 1))
                done
                if [ -n "$extra" ]; then
                    hex+="$(printf "%02x" "$extra")"
                fi
                data_label_off["$name"]=$((${#data_bytes} / 2))
                data_bytes+="$hex"
                continue
            fi
            if [[ "$line" =~ $dq_pattern ]]; then
                name="${BASH_REMATCH[1]}"
                val="${BASH_REMATCH[2]}"
                if [[ "$val" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    val=$((16#${BASH_REMATCH[1]}))
                else
                    val=$((val))
                fi
                data_label_off["$name"]=$((${#data_bytes} / 2))
                data_bytes+=$(u64le $val)
                continue
            fi
            error_msg "at line $line_number: unsupported data line format: '$line'"
            return 1
        elif [[ "$in_section" == "rodata" ]]; then
            if [[ "$line" =~ $db_pattern ]]; then
                name="${BASH_REMATCH[1]}"
                txt="${BASH_REMATCH[2]}"
                extra="${BASH_REMATCH[4]}"
                
                txt="${txt//\\/\\\\x5c}"    
                txt="${txt//
/\\n}"          
                txt="${txt//\"/\\\"}"           
                hex=""
                i=0
                while [ "$i" -lt ${#txt} ]; do
                    ch="${txt:$i:1}"
                    oc=$(printf "%d" "'$ch")
                    hex+="$(printf "%02x" "$oc")"
                    i=$((i + 1))
                done
                if [ -n "$extra" ]; then
                    hex+="$(printf "%02x" "$extra")"
                fi
                
                declare -gA rodata_label_off
                rodata_label_off["$name"]=$((${#rodata_bytes} / 2))
                rodata_bytes+="$hex"
                continue
            fi
            if [[ "$line" =~ $dq_pattern ]]; then
                name="${BASH_REMATCH[1]}"
                val="${BASH_REMATCH[2]}"
                if [[ "$val" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    val=$((16#${BASH_REMATCH[1]}))
                else
                    val=$((val))
                fi
                rodata_label_off["$name"]=$((${#rodata_bytes} / 2))
                rodata_bytes+=$(u64le $val)
                continue
            fi
            error_msg "at line $line_number: unsupported rodata line format: '$line'"
            return 1
        elif [[ "$in_section" == "bss" ]]; then
            
            if [[ "$line" =~ $dq_pattern ]]; then
                name="${BASH_REMATCH[1]}"
                val="${BASH_REMATCH[2]}"
                if [[ "$val" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    val=$((16#${BASH_REMATCH[1]}))
                else
                    val=$((val))
                fi
                
                declare -gA bss_label_off
                bss_label_off["$name"]=$((${#bss_bytes} / 2))
                
                bss_bytes+=$(generate_zeros $val)
                continue
            fi
            error_msg "at line $line_number: unsupported bss line format: '$line'"
            return 1
        elif [[ "$in_section" == "text" ]]; then
            if [[ "$line" =~ ^([.a-zA-Z0-9_]+):$ ]]; then
                lbl="${BASH_REMATCH[1]}"
                labels["$lbl"]="$text_bytes_len"
                continue
            fi
            text_ins+=("$line")
            
            
            if [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ $cmov_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$ ]]; then
                calculate_mov_size
            
            elif [[ "$line" =~ ^(syscall|nop|ret|leave|cqo|cdqe)$ ]]; then
                calculate_simple_instr_size
            
                elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^(push|pop)[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 1))
            
            elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]*(.*)$ ]]; then
                calculate_arith_ri_size
            
            elif [[ "$line" =~ ^(je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jo|jno|js|jns|jmp)[[:space:]]+(.*)$ ]]; then
                local jlbl="${BASH_REMATCH[2]}"
                jlbl="$(trim_string "$jlbl")"
                if [[ -n "${externals[$jlbl]:-}" ]]; then
                    if [[ "${BASH_REMATCH[1]}" == "jmp" ]]; then
                        text_bytes_len=$((text_bytes_len + 5))
                    else
                        text_bytes_len=$((text_bytes_len + 6))
                    fi
                else
                    text_bytes_len=$((text_bytes_len + 2))
                fi
            
            elif [[ "$line" =~ ^(loop|loope|loopne)[[:space:]]+(.*)$ ]]; then
                text_bytes_len=$((text_bytes_len + 2))
            
            elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 5))
            
            elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^(imul)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
                text_bytes_len=$((text_bytes_len + 7))
            
            elif [[ "$line" =~ ^(shl|shr|sar)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 7))
            
              elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh])$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ ^movsxd[[:space:]]+(r[a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ $movss_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $movsd_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $addss_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $addsd_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $mulss_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $mulsd_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $subss_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $subsd_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $divss_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $divsd_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $movsd_mem_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $cvtsd2si_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            else
                error_msg "unsupported instruction: '$line'"
                return 1
            fi
        else
            error_msg "at line $line_number: instruction outside of section: '$line'"
            return 1
        fi
    done
    
    return 0
}
