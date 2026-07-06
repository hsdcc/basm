#!/usr/bin/env bash
second_pass() {
    local text_ins_ref="$1"
    local -n ins_array="$1"
    
    text_hex=""
    current_address=0
    
    for line in "${ins_array[@]}"; do
        
        if [[ "$line" =~ $movss_rr_pattern ]]; then
            handle_fp_operation "movss_rr" 4
        elif [[ "$line" =~ $movsd_rr_pattern ]]; then
            handle_fp_operation "movsd_rr" 4
        elif [[ "$line" =~ $addss_rr_pattern ]]; then
            handle_fp_operation "addss_rr" 4
        elif [[ "$line" =~ $addsd_rr_pattern ]]; then
            handle_fp_operation "addsd_rr" 4
        elif [[ "$line" =~ $mulss_rr_pattern ]]; then
            handle_fp_operation "mulss_rr" 4
        elif [[ "$line" =~ $mulsd_rr_pattern ]]; then
            handle_fp_operation "mulsd_rr" 4
        elif [[ "$line" =~ $subss_rr_pattern ]]; then
            handle_fp_operation "subss_rr" 4
        elif [[ "$line" =~ $subsd_rr_pattern ]]; then
            handle_fp_operation "subsd_rr" 4
        elif [[ "$line" =~ $divss_rr_pattern ]]; then
            handle_fp_operation "divss_rr" 4
        elif [[ "$line" =~ $divsd_rr_pattern ]]; then
            handle_fp_operation "divsd_rr" 4
        elif [[ "$line" =~ $movsd_mem_pattern ]]; then
            reg="${BASH_REMATCH[1]}"
            reg2="${BASH_REMATCH[2]}"
            mod_rm=$((xmm_regs[$reg] << 3 | regs[$reg2]))
            text_hex+="${fp_opcodes["movsd_mem"]}$(printf "%02x" $mod_rm)"
            current_address=$((current_address + 4))
        elif [[ "$line" =~ $cvtsd2si_pattern ]]; then
            reg="${BASH_REMATCH[1]}"
            xmm="${BASH_REMATCH[2]}"
            mod_rm=$((0xc0 | regs[$reg] << 3 | xmm_regs[$xmm]))
            text_hex+="${fp_opcodes["cvtsd2si"]}$(printf "%02x" $mod_rm)"
            current_address=$((current_address + 4))
        elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
            op="${BASH_REMATCH[1]}"
            dst="${BASH_REMATCH[2]}"
            src="${BASH_REMATCH[3]}"
            dst_reg=$(get_reg_num "$dst")
            src_reg=$(get_reg_num "$src")
            if (( dst_reg < 0 )); then
                echo "error at line $line_number: invalid destination register '$dst' in '$line'" >&2
                return 1
            fi
            if (( src_reg < 0 )); then
                echo "error at line $line_number: invalid source register '$src' in '$line'" >&2
                return 1
            fi
            mod_rm=$((0xc0 | (dst_reg << 3) | src_reg))
            if [[ "$op" == "movzx" ]]; then
                text_hex+=$(printf "480fb6%02x" $mod_rm)
            else
                text_hex+=$(printf "480fbe%02x" $mod_rm)
            fi
            current_address=$((current_address + 4))
        elif [[ "$line" =~ ^movsxd[[:space:]]+(r[a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
            dst="${BASH_REMATCH[1]}"
            src="${BASH_REMATCH[2]}"
            dst_reg=$(get_reg_num "$dst")
            src_reg=$(get_reg_num "$src")
            if (( dst_reg < 0 )); then
                echo "error at line $line_number: invalid destination register '$dst' in '$line'" >&2
                return 1
            fi
            if (( src_reg < 0 )); then
                echo "error at line $line_number: invalid source register '$src' in '$line'" >&2
                return 1
            fi
            mod_rm=$((0xc0 | (dst_reg << 3) | src_reg))
            text_hex+=$(printf "4863%02x" $mod_rm)
            current_address=$((current_address + 3))
        elif [[ "$line" =~ ^mov ]]; then
            local mov_operands="${line#mov }"
            local dst="${mov_operands%%,*}"
            local src="${mov_operands#*,}"
            dst=$(trim_string "$dst")
            src=$(trim_string "$src")
            if [[ "$dst" =~ ^r[a-z]{2}$ && "$src" =~ ^r[a-z]{2}$ ]]; then
                
                mod_rm=$((0xc0 + regs[$src] * 8 + regs[$dst]))
                text_hex+=$(printf "4889%02x" "$mod_rm")
                current_address=$((current_address + 3))
            elif [[ "$dst" =~ ^\[.*\]$ ]]; then 
                hex_code=$(assemble_mem_operand "$dst" "${regs[$src]}" "4889")
                text_hex+=$hex_code
                current_address=$((current_address + ${#hex_code}/2))
            elif [[ "$src" =~ ^\[.*\]$ ]]; then 
                hex_code=$(assemble_mem_operand "$src" "${regs[$dst]}" "488b")
                text_hex+=$hex_code
                current_address=$((current_address + ${#hex_code}/2))
            else
                
                local reg="$dst"
                local arg="$src"
                local val_is_immediate=0
                local val
                if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    val=$((16#${BASH_REMATCH[1]}))
                    val_is_immediate=1
                elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
                    if [[ "$arg" =~ ^-?(0|[1-9][0-9]*)$ ]]; then
                        val=$((arg))
                        val_is_immediate=1
                    else
                        error_msg "invalid integer format '$arg'"
                        return 1
                    fi
                elif [[ -n "${equs[$arg]:-}" ]]; then
                    val=${equs[$arg]}
                    if [[ ! "$val" =~ ^-?[0-9]+$ ]]; then
                        echo "error: equ '$arg' resolves to non-numeric value" >&2
                        return 1
                    fi
                    val_is_immediate=1
                else
                    val_is_immediate=0
                fi
                if [[ "$val_is_immediate" -eq 1 ]]; then
                    if (( val >= -2147483648 && val <= 2147483647 )); then
                        opcode=$((0xc0 + regs[$reg]))
                        text_hex+=$(printf "48c7%02x" "$opcode")$(u32le $val)
                        current_address=$((current_address + 7))
                    else
                        op=$((0xb8 + regs[$reg]))
                        text_hex+=$(printf "48%02x" "$op")$(u64le $val)
                        current_address=$((current_address + 10))
                    fi
                else
                    op=$((0xb8 + regs[$reg]))
                    if [[ -n "${data_label_off[$arg]:-}" ]]; then
                        addr=$((data_vaddr + data_label_off[$arg]))
                        relocations+=("$((current_address + 2)):${arg}:1:0")
                    elif [[ -n "${labels[$arg]:-}" ]]; then
                        addr=$((text_vaddr + labels[$arg]))
                        relocations+=("$((current_address + 2)):${arg}:1:0")
                    elif [[ -n "${externals[$arg]:-}" ]]; then
                        addr=0
                        relocations+=("$((current_address + 2)):${arg}:1:0")
                    else
                        echo "error at line $line_number: unknown label '$arg' in mov instruction '$line'" >&2
                        return 1
                    fi
                    text_hex+=$(printf "48%02x" "$op")$(u64le $addr)
                    current_address=$((current_address + 10))
                fi
            fi
        elif [[ "$line" =~ $cmov_pattern ]]; then
            cond="${BASH_REMATCH[1]}"
            dst="${BASH_REMATCH[2]}"
            src="${BASH_REMATCH[3]}"
            case "$cond" in
            e) cc=0x44 ;;
            ne) cc=0x45 ;;
            a) cc=0x47 ;;
            ae) cc=0x43 ;;
            b) cc=0x42 ;;
            be) cc=0x46 ;;
            g) cc=0x4f ;;
            ge) cc=0x4d ;;
            l) cc=0x4c ;;
            le) cc=0x4e ;;
            o) cc=0x40 ;;
            no) cc=0x41 ;;
            s) cc=0x48 ;;
            ns) cc=0x49 ;;
            p) cc=0x4a ;;
            np) cc=0x4b ;;
            *) echo "unknown cmov condition $cond" >&2; return 1 ;;
            esac
            mod_rm=$((0xc0 | (regs[$dst] << 3) | regs[$src]))
            text_hex+="48"
            text_hex+=$(printf "0f%02x%02x" "$cc" "$mod_rm")
            current_address=$((current_address + 4))
        elif [[ "$line" =~ ^(syscall|nop|ret|leave|cqo|cdqe)$ ]]; then
            
            case "$line" in
                syscall) text_hex+="0f05"; current_address=$((current_address + 2)) ;;
                nop) text_hex+="90"; current_address=$((current_address + 1)) ;;
                ret) text_hex+="c3"; current_address=$((current_address + 1)) ;;
                leave) text_hex+="c9"; current_address=$((current_address + 1)) ;;
                cqo) text_hex+="4899"; current_address=$((current_address + 2)) ;;
                cdqe) text_hex+="4898"; current_address=$((current_address + 2)) ;;
            esac
        elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
            reg="${BASH_REMATCH[1]}"
            mod_rm=$((0xc0 + regs[$reg] * 8 + regs[$reg]))
            text_hex+=$(printf "4831%02x" $mod_rm)
            current_address=$((current_address + 3))
        elif [[ "$line" =~ ^push[[:space:]]+(r[a-z]{2})$ ]]; then
            reg="${BASH_REMATCH[1]}"
            op=$((0x50 + regs[$reg]))
            text_hex+=$(printf "%02x" $op)
            current_address=$((current_address + 1))
        elif [[ "$line" =~ ^pop[[:space:]]+(r[a-z]{2})$ ]]; then
            reg="${BASH_REMATCH[1]}"
            op=$((0x58 + regs[$reg]))
            text_hex+=$(printf "%02x" $op)
            current_address=$((current_address + 1))
        elif [[ "$line" =~ ^(add|sub|cmp|or|and) ]]; then
            local op="${BASH_REMATCH[1]}"
            local operands="${line#$op }"
            local dst="${operands%%,*}"
            local src="${operands#*,}"
            dst=$(trim_string "$dst")
            src=$(trim_string "$src")
            if [[ "$dst" =~ ^r[a-z]{2}$ && "$src" =~ ^r[a-z]{2}$ ]]; then
                
                local reg1="$dst"
                local reg2="$src"
                local mod_rm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
                case "$op" in
                add) text_hex+=$(printf "4801%02x" $mod_rm) ;;
                sub) text_hex+=$(printf "4829%02x" $mod_rm) ;;
                and) text_hex+=$(printf "4821%02x" $mod_rm) ;;
                or) text_hex+=$(printf "4809%02x" $mod_rm) ;;
                cmp) text_hex+=$(printf "4839%02x" $mod_rm) ;;
                esac
                current_address=$((current_address + 3))
            elif [[ "$dst" =~ ^\[.*\]$ || "$src" =~ ^\[.*\]$ ]]; then
                
                assemble_arith_mem "$op" "$dst" "$src"
            else
                
                local reg="$dst"
                local arg="$src"
                if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    val=$((16#${BASH_REMATCH[1]}))
                elif [[ "$arg" =~ ^[0-9]+$ ]]; then
                    val=$((arg))
                else
                    echo "error: unknown immediate value '$arg' in '$line'" >&2
                    return 1
                fi
                if [[ "$reg" == "rax" ]]; then
                    case "$op" in
                    add)
                        text_hex+="4881c0$(u32le $val)"
                        current_address=$((current_address + 7))
                        ;;
                    sub)
                        text_hex+="4881e8$(u32le $val)"
                        current_address=$((current_address + 7))
                        ;;
                    or)
                        text_hex+="4881c8$(u32le $val)"
                        current_address=$((current_address + 7))
                        ;;
                    and)
                        text_hex+="4881e0$(u32le $val)"
                        current_address=$((current_address + 7))
                        ;;
                    cmp)
                        text_hex+="483d$(u32le $val)"
                        current_address=$((current_address + 6))
                        ;;
                    esac
                else
                    op_ext=0
                    case "$op" in
                    add) op_ext=0 ;;
                    sub) op_ext=5 ;;
                    cmp) op_ext=7 ;;
                    or) op_ext=1 ;;
                    and) op_ext=4 ;;
                    esac
                    mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
                    text_hex+=$(printf "4883%02x%02x" "$mod_rm" "$val")
                    current_address=$((current_address + 4))
                fi
            fi
        elif [[ "$line" =~ ^(je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jo|jno|js|jns|jmp|loop|loope|loopne)[[:space:]]+(.*)$ ]]; then
            local op="${BASH_REMATCH[1]}"
            local lbl="${BASH_REMATCH[2]}"
            assemble_short_jump "$op" "$lbl"
        elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+(r[a-z]{2})$ ]]; then
            op="${BASH_REMATCH[1]}"
            reg="${BASH_REMATCH[2]}"
            op_ext=0
            if [[ "$op" == "inc" ]]; then
                mod_rm=$((0xc0 + regs[$reg]))
                text_hex+=$(printf "48ff%02x" $mod_rm)
            elif [[ "$op" == "dec" ]]; then
                mod_rm=$((0xc8 + regs[$reg]))
                text_hex+=$(printf "48ff%02x" $mod_rm)
            elif [[ "$op" == "neg" ]]; then
                op_ext=3
                mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
                text_hex+=$(printf "48f7%02x" $mod_rm)
            elif [[ "$op" == "not" ]]; then
                op_ext=2
                mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
                text_hex+=$(printf "48f7%02x" $mod_rm)
            fi
            current_address=$((current_address + 3))
        elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
            lbl="${BASH_REMATCH[1]}"
            if [[ -z "${labels[$lbl]:-}" ]]; then
                error_msg "unknown label '$lbl' in call instruction '$line'"
                return 1
            fi
            target_address=${labels[$lbl]}
            offset=$((target_address - (current_address + 5)))
            text_hex+="e8$(u32le $offset)"
            current_address=$((current_address + 5))
        elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
            op="${BASH_REMATCH[1]}"
            reg="${BASH_REMATCH[2]}"
            op_ext=0
            case "$op" in
            mul) op_ext=4 ;;
            div) op_ext=6 ;;
            idiv) op_ext=7 ;;
            esac
            mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
            text_hex+=$(printf "48f7%02x" $mod_rm)
            current_address=$((current_address + 3))
        elif [[ "$line" =~ ^imul[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
            reg1="${BASH_REMATCH[1]}"
            reg2="${BASH_REMATCH[2]}"
            mod_rm=$((0xc0 | (regs[$reg1] << 3) | regs[$reg2]))
            text_hex+=$(printf "480faf%02x" $mod_rm)
            current_address=$((current_address + 4))
        elif [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
            reg="${BASH_REMATCH[1]}"
            lbl="${BASH_REMATCH[2]}"
            if [[ -z "${data_label_off[$lbl]:-}" ]]; then
                echo "unknown label $lbl" >&2
                return 1
            fi
            mod_rm=$(((regs[$reg] << 3) | 5))
            text_hex+=$(printf "488d%02x" $mod_rm)
            relocations+=("$((current_address + 3)):${lbl}:2:0")
            text_hex+="00000000"
            current_address=$((current_address + 7))
        elif [[ "$line" =~ ^(shl|shr|sar)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
            op="${BASH_REMATCH[1]}"
            reg="${BASH_REMATCH[2]}"
            val="${BASH_REMATCH[3]}"
            op_ext=0
            if [[ "$op" == "shl" ]]; then
                op_ext=4
            elif [[ "$op" == "shr" ]]; then
                op_ext=5
            elif [[ "$op" == "sar" ]]; then
                op_ext=7
            fi
            mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
            text_hex+=$(printf "48c1%02x%02x" $mod_rm $val)
            current_address=$((current_address + 4))
        elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
            reg1="${BASH_REMATCH[1]}"
            reg2="${BASH_REMATCH[2]}"
            mod_rm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
            text_hex+=$(printf "4885%02x" $mod_rm)
            current_address=$((current_address + 3))
        elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
            reg="${BASH_REMATCH[1]}"
            arg="${BASH_REMATCH[2]}"
            if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                val=$((16#${BASH_REMATCH[1]}))
            else
                val=$((arg))
            fi
            mod_rm=$((0xc0 | regs[$reg]))
            text_hex+=$(printf "48f7%02x" "$mod_rm")$(u32le "$val")
            current_address=$((current_address + 7))
        elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
            cond="${BASH_REMATCH[1]}"
            dst="${BASH_REMATCH[2]}"
            dst_reg=$(get_reg_num "$dst")
            if (( dst_reg < 0 )); then
                error_msg "at line $line_number: invalid destination register '$dst' in '$line'"
            fi
            if (( src_reg < 0 )); then
                error_msg "at line $line_number: invalid destination register '$src' in '$line'"
            fi
            mod_rm=$((0xc0 | dst_reg))
            
            case "$cond" in
            e|z) text_hex+=$(printf "0f94%02x" $mod_rm) ;;
            ne|nz) text_hex+=$(printf "0f95%02x" $mod_rm) ;;
            a) text_hex+=$(printf "0f97%02x" $mod_rm) ;;
            ae) text_hex+=$(printf "0f93%02x" $mod_rm) ;;
            b) text_hex+=$(printf "0f92%02x" $mod_rm) ;;
            be) text_hex+=$(printf "0f96%02x" $mod_rm) ;;
            g) text_hex+=$(printf "0f9f%02x" $mod_rm) ;;
            ge) text_hex+=$(printf "0f9d%02x" $mod_rm) ;;
            l) text_hex+=$(printf "0f9c%02x" $mod_rm) ;;
            le) text_hex+=$(printf "0f9e%02x" $mod_rm) ;;
            o) text_hex+=$(printf "0f90%02x" $mod_rm) ;;
            no) text_hex+=$(printf "0f91%02x" $mod_rm) ;;
            s) text_hex+=$(printf "0f98%02x" $mod_rm) ;;
            ns) text_hex+=$(printf "0f99%02x" $mod_rm) ;;
            esac
            current_address=$((current_address + 3))
        else
            error_msg "internal error assembling: $line"
            return 1
        fi
    done
    
    return 0
}