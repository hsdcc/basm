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
            
            
            if [[ "$line" =~ ^mov[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^mov[[:space:]]+\[([er][a-z]{2})\],[[:space:]]+([er][a-z]{2})$ ]]; then
                local base="${BASH_REMATCH[1]}"
                local size=$(calc_mem_addr_size "$base" "")
                text_bytes_len=$((text_bytes_len + size))
            
            elif [[ "$line" =~ ^mov[[:space:]]+([er][a-z]{2}),[[:space:]]+\[([er][a-z]{2})\]$ ]]; then
                local base="${BASH_REMATCH[2]}"
                local size=$(calc_mem_addr_size "$base" "")
                text_bytes_len=$((text_bytes_len + size))
            
            elif [[ "$line" =~ $cmov_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ ^mov[[:space:]]+([er][a-z]{2}),[[:space:]]+(.*)$ ]]; then
                calculate_mov_size
            
            elif [[ "$line" =~ ^(syscall|nop|ret|leave|cqo|cdqe)$ ]]; then
                calculate_simple_instr_size
                elif [[ "$line" =~ $string_op_pattern ]]; then
                    case "$line" in
                        movsb|movsl|stosb|stosl|lodsb|lodsl|scasb|scasl|cmpsb|cmpsl|cld|std) text_bytes_len=$((text_bytes_len + 1)) ;;
                        movsw|movsq|stosw|stosq|lodsw|lodsq|scasw|scasq|cmpsw|cmpsq) text_bytes_len=$((text_bytes_len + 2)) ;;
                    esac

            
                elif [[ "$line" =~ ^xor[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^(push|pop)[[:space:]]+([er][a-z]{2})$ ]]; then
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
                # push [mem] uses 1-byte opcode (ff), calc assumes REX; subtract 1
                text_bytes_len=$((text_bytes_len + size - 1))
            elif [[ "$line" =~ $pop_mem_pattern ]]; then
                base="${BASH_REMATCH[2]}"
                disp="${BASH_REMATCH[3]:-}"
                size=$(calc_mem_addr_size "$base" "$disp")
                text_bytes_len=$((text_bytes_len + size))

            elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+([er][a-z]{2}),[[:space:]]*(.*)$ ]]; then
                calculate_arith_ri_size
            
            elif [[ "$line" =~ $arith_mem_imm_pattern ]]; then
                local ambase="${BASH_REMATCH[2]}"
                local amdisp="${BASH_REMATCH[3]:-}"
                local amsize=$(calc_mem_addr_size "$ambase" "$amdisp")
                local amimm="${BASH_REMATCH[4]}"
                local amval=0
                if [[ "$amimm" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    amval=$((16#${BASH_REMATCH[1]}))
                elif [[ "$amimm" =~ ^-?[0-9]+$ ]]; then
                    amval=$((amimm))
                fi
                if (( amval >= -128 && amval <= 127 )); then
                    text_bytes_len=$((text_bytes_len + amsize + 1))
                else
                    text_bytes_len=$((text_bytes_len + amsize + 4))
                fi
            
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
            
            elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ $unary_mem_pattern ]]; then
                local umbase="${BASH_REMATCH[2]}"
                local umdisp="${BASH_REMATCH[3]:-}"
                local umsize=$(calc_mem_addr_size "$umbase" "$umdisp")
                text_bytes_len=$((text_bytes_len + umsize))
            
            elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 5))
            
            elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ $mul_mem_pattern ]]; then
                local mbase="${BASH_REMATCH[2]}"
                local mdisp="${BASH_REMATCH[3]:-}"
                local msize=$(calc_mem_addr_size "$mbase" "$mdisp")
                text_bytes_len=$((text_bytes_len + msize))
            
            elif [[ "$line" =~ ^(imul)[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ $imul_mem_pattern ]]; then
                local ibase="${BASH_REMATCH[2]}"
                local idisp="${BASH_REMATCH[3]:-}"
                local isize=$(calc_mem_addr_size "$ibase" "$idisp")
                text_bytes_len=$((text_bytes_len + isize + 1))
            
            elif [[ "$line" =~ $imul3_pattern ]]; then
                local i3src="${BASH_REMATCH[2]}"
                local i3imm="${BASH_REMATCH[3]}"
                if [[ "$i3src" =~ ^[er][a-z]{2}$ ]]; then
                    local i3val=0
                    [[ "$i3imm" =~ ^-?[0-9]+$ ]] && i3val=$((i3imm))
                    if (( i3val >= -128 && i3val <= 127 )); then
                        text_bytes_len=$((text_bytes_len + 4))
                    else
                        text_bytes_len=$((text_bytes_len + 7))
                    fi
                else
                    if [[ "$i3src" =~ \[([er][a-z]{2})([\+\-][0-9]+)?\] ]]; then
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
            
            elif [[ "$line" =~ ^lea[[:space:]]+([er][a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
                text_bytes_len=$((text_bytes_len + 7))
            
            elif [[ "$line" =~ ^(shl|shr|sar)[[:space:]]+([er][a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ $shift_mem_pattern ]]; then
                local smbase="${BASH_REMATCH[2]}"
                local smdisp="${BASH_REMATCH[3]:-}"
                local smsize=$(calc_mem_addr_size "$smbase" "$smdisp")
                text_bytes_len=$((text_bytes_len + smsize + 1))
            
            elif [[ "$line" =~ ^test[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^test[[:space:]]+([er][a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 7))
            
              elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+([er][a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh])$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            
            elif [[ "$line" =~ ^movsxd[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            
            elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|[er][a-z]{2})$ ]]; then
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
            elif [[ "$line" =~ $sse_mem_src_pattern ]]; then
                local sse_mne="${BASH_REMATCH[1]}"
                local sse_base="${BASH_REMATCH[3]}"
                local sse_disp_str="${BASH_REMATCH[4]:-}"
                local sse_disp=""
                if [[ -n "$sse_disp_str" ]]; then
                    sse_disp=$((sse_disp_str))
                fi
                local sse_size
                if [[ "$sse_mne" == "comiss" || "$sse_mne" == "ucomiss" ]]; then
                    sse_size=$(calc_sse_mem_size "$sse_base" "$sse_disp" 2)
                else
                    sse_size=$(calc_sse_mem_size "$sse_base" "$sse_disp" 3)
                fi
                text_bytes_len=$((text_bytes_len + sse_size))
            elif [[ "$line" =~ $sse_mem_dst_pattern ]]; then
                local sd_base="${BASH_REMATCH[2]}"
                local sd_disp_str="${BASH_REMATCH[3]:-}"
                local sd_disp=""
                if [[ -n "$sd_disp_str" ]]; then
                    sd_disp=$((sd_disp_str))
                fi
                local sd_size=$(calc_sse_mem_size "$sd_base" "$sd_disp" 3)
                text_bytes_len=$((text_bytes_len + sd_size))
            elif [[ "$line" =~ $cvtsi2s_reg_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $cvtsi2s_mem_pattern ]]; then
                local c2_base="${BASH_REMATCH[3]}"
                local c2_disp_str="${BASH_REMATCH[4]:-}"
                local c2_disp=""
                if [[ -n "$c2_disp_str" ]]; then
                    c2_disp=$((c2_disp_str))
                fi
                local c2_size=$(calc_sse_mem_size "$c2_base" "$c2_disp" 3)
                text_bytes_len=$((text_bytes_len + c2_size))
            elif [[ "$line" =~ $cvtss2si_rr_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $cvtss2s_mem_pattern ]]; then
                local cs_base="${BASH_REMATCH[3]}"
                local cs_disp_str="${BASH_REMATCH[4]:-}"
                local cs_disp=""
                if [[ -n "$cs_disp_str" ]]; then
                    cs_disp=$((cs_disp_str))
                fi
                local cs_size=$(calc_sse_mem_size "$cs_base" "$cs_disp" 3)
                text_bytes_len=$((text_bytes_len + cs_size))
            elif [[ "$line" =~ $cvtsd2si_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            elif [[ "$line" =~ $rep_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 2))
            elif [[ "$line" =~ $lea_mem_pattern ]]; then
                local lea_base="${BASH_REMATCH[2]}"
                local lea_disp="${BASH_REMATCH[3]:-}"
                local lea_dval=0
                [[ -n "$lea_disp" ]] && lea_dval=$((lea_disp))
                local lea_size=$(calc_mem_addr_size "$lea_base" "$lea_dval")
                text_bytes_len=$((text_bytes_len + lea_size))
            elif [[ "$line" =~ $mov_mem_imm_pattern ]]; then
                local mmi_size_kw="${BASH_REMATCH[1]}"
                local mmi_base="${BASH_REMATCH[2]}"
                local mmi_disp="${BASH_REMATCH[3]:-}"
                local mmi_imm="${BASH_REMATCH[4]}"
                local mmi_dval=0
                [[ -n "$mmi_disp" ]] && mmi_dval=$((mmi_disp))
                local mmi_addrsize=$(calc_mem_addr_size "$mmi_base" "$mmi_dval")
                local mmi_immval=0
                [[ "$mmi_imm" =~ ^-?[0-9]+$ ]] && mmi_immval=$((mmi_imm))
                [[ "$mmi_imm" =~ ^0x([0-9a-fA-F]+)$ ]] && mmi_immval=$((16#${BASH_REMATCH[1]}))
                if [[ "$mmi_size_kw" == "byte " ]]; then
                    text_bytes_len=$((text_bytes_len + mmi_addrsize + 2))
                else
                    text_bytes_len=$((text_bytes_len + mmi_addrsize + 5))
                fi
            elif [[ "$line" =~ $shift_cl_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            elif [[ "$line" =~ $setcc_mem_pattern ]]; then
                local scc_base="${BASH_REMATCH[3]}"
                local scc_disp="${BASH_REMATCH[4]:-}"
                local scc_dval=0
                [[ -n "$scc_disp" ]] && scc_dval=$((scc_disp))
                local scc_size=$(calc_mem_addr_size "$scc_base" "$scc_dval")
                text_bytes_len=$((text_bytes_len + scc_size + 2))
            elif [[ "$line" =~ $imul_ri_pattern ]]; then
                local iri_imm="${BASH_REMATCH[2]}"
                local iri_val=0
                [[ "$iri_imm" =~ ^-?[0-9]+$ ]] && iri_val=$((iri_imm))
                [[ "$iri_imm" =~ ^0x([0-9a-fA-F]+)$ ]] && iri_val=$((16#${BASH_REMATCH[1]}))
                if (( iri_val >= -128 && iri_val <= 127 )); then
                    text_bytes_len=$((text_bytes_len + 4))
                else
                    text_bytes_len=$((text_bytes_len + 7))
                fi
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
