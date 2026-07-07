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
                    bss_bytes_len=$((bss_bytes_len + val))
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
            
            elif [[ "$line" =~ ^mov[[:space:]]+\[(r[a-z]{2})\],[[:space:]]+(r[a-z]{2})$ ]]; then
                local base="${BASH_REMATCH[1]}"
                local size=$(calc_mem_addr_size "$base" "")
                text_bytes_len=$((text_bytes_len + size))
            
            elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+\[(r[a-z]{2})\]$ ]]; then
                local base="${BASH_REMATCH[2]}"
                local size=$(calc_mem_addr_size "$base" "")
                text_bytes_len=$((text_bytes_len + size))
            
            elif [[ "$line" =~ $cmov_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$ ]]; then
                calculate_mov_size
            
            elif [[ "$line" =~ ^(syscall|nop|ret|leave|cqo|cdqe)$ ]]; then
                calculate_simple_instr_size
                elif [[ "$line" =~ $string_op_pattern ]]; then
                    case "$line" in
                        movsb|movsl|stosb|stosl|lodsb|lodsl|scasb|scasl|cmpsb|cmpsl|cld|std) text_bytes_len=$((text_bytes_len + 1)) ;;
                        movsw|movsq|stosw|stosq|lodsw|lodsq|scasw|scasq|cmpsw|cmpsq) text_bytes_len=$((text_bytes_len + 2)) ;;
                    esac

            
                elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^(push|pop)[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 1))

            elif [[ "$line" =~ $push_imm_pattern ]]; then
                arg="${BASH_REMATCH[1]}"
                if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    val=$((16#${BASH_REMATCH[1]}))
                else
                    val=$((arg))
                fi
                if (( val >= -128 && val <= 127 )); then
                    text_bytes_len=$((text_bytes_len + 2))
                else
                    text_bytes_len=$((text_bytes_len + 5))
                fi
            elif [[ "$line" =~ $push_equsym_pattern ]]; then
                sym="${BASH_REMATCH[1]}"
                if [[ -n "${equs[$sym]:-}" ]]; then
                    val=${equs[$sym]}
                    if (( val >= -128 && val <= 127 )); then
                        text_bytes_len=$((text_bytes_len + 2))
                    else
                        text_bytes_len=$((text_bytes_len + 5))
                    fi
                else
                    text_bytes_len=$((text_bytes_len + 5))
                fi
            elif [[ "$line" =~ $push_mem_pattern ]]; then
                base="${BASH_REMATCH[2]}"
                disp="${BASH_REMATCH[3]:-}"
                size=$(calc_mem_addr_size "$base" "$disp")
                text_bytes_len=$((text_bytes_len + size))
            elif [[ "$line" =~ $pop_mem_pattern ]]; then
                base="${BASH_REMATCH[2]}"
                disp="${BASH_REMATCH[3]:-}"
                size=$(calc_mem_addr_size "$base" "$disp")
                text_bytes_len=$((text_bytes_len + size))

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
                    if [[ "${BASH_REMATCH[1]}" == "jmp" ]]; then
                        text_bytes_len=$((text_bytes_len + 5))
                    else
                        text_bytes_len=$((text_bytes_len + 6))
                    fi
                fi
            
            elif [[ "$line" =~ ^(loop|loope|loopne)[[:space:]]+(.*)$ ]]; then
                text_bytes_len=$((text_bytes_len + 2))
            
            elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 5))
            
            elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ $mul_mem_pattern ]]; then
                local mbase="${BASH_REMATCH[2]}"
                local mdisp="${BASH_REMATCH[3]:-}"
                local msize=$(calc_mem_addr_size "$mbase" "$mdisp")
                text_bytes_len=$((text_bytes_len + msize))
            
            elif [[ "$line" =~ ^(imul)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ $imul_mem_pattern ]]; then
                local ibase="${BASH_REMATCH[2]}"
                local idisp="${BASH_REMATCH[3]:-}"
                local isize=$(calc_mem_addr_size "$ibase" "$idisp")
                text_bytes_len=$((text_bytes_len + isize + 1))
            
            elif [[ "$line" =~ $imul3_pattern ]]; then
                local i3src="${BASH_REMATCH[2]}"
                local i3imm="${BASH_REMATCH[3]}"
                if [[ "$i3src" =~ ^r[a-z]{2}$ ]]; then
                    local i3val=0
                    [[ "$i3imm" =~ ^-?[0-9]+$ ]] && i3val=$((i3imm))
                    if (( i3val >= -128 && i3val <= 127 )); then
                        text_bytes_len=$((text_bytes_len + 4))
                    else
                        text_bytes_len=$((text_bytes_len + 7))
                    fi
                else
                    if [[ "$i3src" =~ \[(r[a-z]{2})([\+\-][0-9]+)?\] ]]; then
                        local ebase="${BASH_REMATCH[1]}"
                        local edisp="${BASH_REMATCH[2]:-}"
                        local esize=$(calc_mem_addr_size "$ebase" "$edisp")
                        local eVal=0
                        [[ "$i3imm" =~ ^-?[0-9]+$ ]] && eVal=$((i3imm))
                        if (( eVal >= -128 && eVal <= 127 )); then
                            text_bytes_len=$((text_bytes_len + esize + 1))
                        else
                            text_bytes_len=$((text_bytes_len + esize + 4))
                        fi
                    fi
                fi
            
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
