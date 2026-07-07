#!/usr/bin/env bash
assemble_simple() {
    local op=$1
    case "$op" in
        syscall) append_instruction "0f05" 2 ;;
        nop) append_instruction "90" 1 ;;
        ret) append_instruction "c3" 1 ;;
        leave) append_instruction "c9" 1 ;;
        cqo) append_instruction "4899" 2 ;;
        cdqe) append_instruction "4898" 2 ;;
        *) error_msg "unknown simple op '$op'" ;;
    esac
}
assemble_xor_self() {
    local reg=$1
    local mod_rm=$(build_mod_rm 3 ${regs[$reg]} ${regs[$reg]})
    local hex=$(printf "4831%02x" $mod_rm)
    append_instruction "$hex" 3
}
assemble_push_pop() {
    local op=$1 reg=$2
    local opcode
    if [[ "$op" == "push" ]]; then
        opcode=$((0x50 + regs[$reg]))
    else
        opcode=$((0x58 + regs[$reg]))
    fi
    local hex=$(printf "%02x" $opcode)
    append_instruction "$hex" 1
}
assemble_arith_rr() {
    local op=$1 dst=$2 src=$3
    local mod_rm=$(build_mod_rm 3 ${regs[$src]} ${regs[$dst]})
    local hex=$(printf "${arith_opcodes[$op]}" $mod_rm)
    append_instruction "$hex" 3
}
assemble_mov() {
    local operands="$1"
    if output=$(parse_rr_operands "$operands"); then
        read dst src <<< "$output"
        
        local mod_rm=$(build_mod_rm 3 ${regs[$src]} ${regs[$dst]})
        text_hex+=$(printf "4889%02x" $mod_rm)
        current_address=$((current_address + 3))
    elif [[ "$operands" =~ $mem_dest_operands ]]; then
        
        local mem_op="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        local reg="${BASH_REMATCH[3]}"
        hex_code=$(assemble_mem_operand "$mem_op" "${regs[$reg]}" "4889")
        text_hex+=$hex_code
        current_address=$((current_address + ${#hex_code}/2))
    elif output=$(parse_mem_operands "$operands"); then
        read reg mem <<< "$output"
        
        hex_code=$(assemble_mem_operand "$mem" "${regs[$reg]}" "488b")
        text_hex+=$hex_code
        current_address=$((current_address + ${#hex_code}/2))
    else
        
        if output=$(parse_ri_operands "$operands"); then
            read reg arg <<< "$output"
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
                    echo "error: invalid integer format '$arg'" >&2
                    return 1
                fi
            elif [[ -n "${equs[$arg]:-}" ]]; then
                val=${equs[$arg]}
                if [[ ! "$val" =~ ^-?[0-9]+$ ]]; then
                    error_msg "equ '$arg' resolves to non-numeric value"
                fi
                val_is_immediate=1
            else
                val_is_immediate=0
            fi
            if [[ "$val_is_immediate" -eq 1 ]]; then
                if (( val >= -2147483648 && val <= 2147483647 )); then
                    local opcode=$((0xc0 + regs[$reg]))
                    text_hex+=$(printf "48c7%02x" "$opcode")$(u32le $val)
                    current_address=$((current_address + 7))
                else
                    local op=$((0xb8 + regs[$reg]))
                    text_hex+=$(printf "48%02x" "$op")$(u64le $val)
                    current_address=$((current_address + 10))
                fi
            else
                local op=$((0xb8 + regs[$reg]))
                if [[ -n "${data_label_off[$arg]:-}" ]]; then
                    addr=$((data_vaddr + data_label_off[$arg]))
                elif [[ -n "${rodata_label_off[$arg]:-}" ]]; then
                    addr=$((data_vaddr + rodata_label_off[$arg]))
                elif [[ -n "${labels[$arg]:-}" ]]; then
                    addr=$((text_vaddr + labels[$arg]))
                else
                    error_msg "unknown label '$arg' in mov instruction"
                fi
                text_hex+=$(printf "48%02x" "$op")$(u64le $addr)
                current_address=$((current_address + 10))
            fi
        else
            error_msg "invalid mov operands: $operands"
        fi
    fi
}
assemble_arith() {
    local mnemonic="$1"
    local operands="$2"
    if output=$(parse_rr_operands "$operands"); then
        read dst src <<< "$output"
        local mod_rm=$(build_mod_rm 3 ${regs[$src]} ${regs[$dst]})
        text_hex+=$(printf "${arith_opcodes[$mnemonic]}" $mod_rm)
        current_address=$((current_address + 3))
    elif output=$(parse_mem_operands "$operands"); then
        read reg mem <<< "$output"
        local mem_op="$mem"
        local opcode_reg_mem
        case "$mnemonic" in
            add) opcode_reg_mem="4803" ;;
            sub) opcode_reg_mem="482b" ;;
            and) opcode_reg_mem="4823" ;;
            or)  opcode_reg_mem="480b" ;;
            cmp) opcode_reg_mem="483b" ;;
        esac
        hex_code=$(assemble_mem_operand "$mem_op" "${regs[$reg]}" "$opcode_reg_mem")
        text_hex+=$hex_code
        current_address=$((current_address + ${#hex_code}/2))
    elif [[ "$operands" =~ $mem_dest_operands ]]; then
        
        local mem_op="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        local reg="${BASH_REMATCH[3]}"
        local opcode_mem_reg
        case "$mnemonic" in
            add) opcode_mem_reg="4801" ;;
            sub) opcode_mem_reg="4829" ;;
            and) opcode_mem_reg="4821" ;;
            or)  opcode_mem_reg="4809" ;;
            cmp) opcode_mem_reg="4839" ;;
        esac
        hex_code=$(assemble_mem_operand "$mem_op" "${regs[$reg]}" "$opcode_mem_reg")
        text_hex+=$hex_code
        current_address=$((current_address + ${#hex_code}/2))
    else
        
        if [[ "$operands" =~ $ri_operands ]]; then
            local reg="${BASH_REMATCH[1]}"
            local arg="${BASH_REMATCH[2]}"
            if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                val=$((16#${BASH_REMATCH[1]}))
            elif [[ "$arg" =~ ^[0-9]+$ ]]; then
                val=$((arg))
            else
                error_msg "unknown immediate value '$arg' in '$mnemonic'"
            fi
            if [[ "$reg" == "rax" ]]; then
                case "$mnemonic" in
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
                local op_ext=0
                case "$mnemonic" in
                    add) op_ext=0 ;;
                    sub) op_ext=5 ;;
                    cmp) op_ext=7 ;;
                    or) op_ext=1 ;;
                    and) op_ext=4 ;;
                esac
                local mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
                text_hex+=$(printf "4883%02x%02x" "$mod_rm" "$val")
                current_address=$((current_address + 4))
            fi
        else
            error_msg "invalid $mnemonic operands: $operands"
        fi
    fi
}
# Parse memory operand content between [ and ], extract base, index, scale, disp
# Output: "base|index|scale|disp"
parse_mem_content() {
    local content="$1"
    local has_sib=0
    local base=""
    local index=""
    local sib_scale=1
    local disp=0
    local tokens=()
    local current=""
    local sign="+"
    local i
    
    # Character-by-character lexer to split on + and -
    for ((i=0; i<${#content}; i++)); do
        local ch="${content:$i:1}"
        if [[ "$ch" == "+" || "$ch" == "-" ]]; then
            tokens+=("${sign}${current}")
            current=""
            sign="$ch"
        else
            current+="$ch"
        fi
    done
    tokens+=("${sign}${current}")
    
    # Strip leading +
    local parsed_tokens=()
    for tok in "${tokens[@]}"; do
        local stripped="${tok#+}"
        parsed_tokens+=("$stripped")
    done
    
    for tok in "${parsed_tokens[@]}"; do
        # tok has format: "+term" or "-term" (sign already embedded if negative)
        # Actually, the sign is the first char: + or -
        local sign="${tok:0:1}"
        local term="${tok:1}"
        # Reconstruct original sign+term for negative disp handling
        if [[ "$sign" == "+" ]]; then
            term="${tok:1}"
        else
            term="$tok"  # keep the - sign embedded
        fi
        
        if [[ "$term" =~ ^-?[0-9]+$ ]]; then
            # Numeric displacement
            disp=$((disp + term))
        elif [[ "$term" =~ ^([er]?[a-z0-9]+)\*([0-9]+)$ ]]; then
            # Scaled index: reg*scale
            local creg="${BASH_REMATCH[1]}"
            local cscale="${BASH_REMATCH[2]}"
            if [[ -n "${regs[$creg]:-}" ]]; then
                index="$creg"
                sib_scale="$cscale"
                has_sib=1
            else
                error_msg "invalid scaled register '$creg' in memory operand"
                return 1
            fi
        elif [[ -n "${regs[$term]:-}" ]]; then
            # Plain register
            if [[ -z "$base" ]]; then
                base="$term"
            elif [[ -z "$index" ]]; then
                index="$term"
                sib_scale=1
                has_sib=1
            else
                error_msg "too many registers in memory operand: '$content'"
                return 1
            fi
        else
            error_msg "invalid term '$term' in memory operand: '$content'"
            return 1
        fi
    done
    
    # Check: if we have only an index (no base), it's still SIB
    if [[ -n "$index" && -z "$base" ]]; then
        has_sib=1
    fi
    
    echo "${base:-}|${index:-}|${sib_scale}|${disp}|${has_sib}"
}
calc_mem_encoding_size() {
    local content="$1"
    local rex_prefix="${2:-1}"  # 1 = include REX.W
    
    local parsed
    parsed=$(parse_mem_content "$content") || return 1
    
    local base="${parsed%%|*}"
    local rest="${parsed#*|}"
    local index="${rest%%|*}"
    rest="${rest#*|}"
    local scale="${rest%%|*}"
    rest="${rest#*|}"
    local disp="${rest%%|*}"
    rest="${rest#*|}"
    local has_sib="${rest}"
    
    local size=0
    [[ "$rex_prefix" == "1" ]] && size=$((size + 1))  # REX.W
    size=$((size + 1))  # opcode
    size=$((size + 1))  # ModRM
    [[ "$has_sib" == "1" ]] && size=$((size + 1))  # SIB
    
    # Displacement
    if [[ -z "$base" && "$has_sib" == "1" ]]; then
        # index*scale+disp (no base) — always need disp32
        size=$((size + 4))
    elif [[ "$base" == "rbp" || "$base" == "ebp" || "$base" == "r13" ]]; then
        if [[ -z "$index" && "$disp" == "0" ]]; then
            # disp=0 with rbp and no index: need mod=01, disp8=00 to avoid RIP-relative
            size=$((size + 1))
        elif (( disp >= -128 && disp <= 127 )); then
            size=$((size + 1))
        else
            size=$((size + 4))
        fi
    elif [[ "$base" == "rsp" || "$base" == "esp" || "$base" == "r12" ]]; then
        # rsp-based addressing always uses SIB (even without index), so count SIB already added
        if [[ -z "$index" && "$disp" == "0" ]]; then
            size=$((size))  # SIB index=4, mod=00, disp=0
        elif (( disp >= -128 && disp <= 127 )); then
            size=$((size + 1))
        else
            size=$((size + 4))
        fi
    else
        if [[ "$disp" == "0" ]]; then
            : # mod=00, no disp
        elif (( disp >= -128 && disp <= 127 )); then
            size=$((size + 1))
        else
            size=$((size + 4))
        fi
    fi
    
    echo "$size"
}
assemble_mem_operand() {
    local mem_op="$1"
    local reg_field="$2"
    local opcode="$3"
    
    # Strip brackets to get content
    local content="${mem_op#\[}"
    content="${content%\]}"
    # Remove whitespace
    content="${content// /}"
    
    local parsed
    parsed=$(parse_mem_content "$content") || return 1
    
    local base="${parsed%%|*}"
    local rest="${parsed#*|}"
    local index="${rest%%|*}"
    rest="${rest#*|}"
    local sib_scale="${rest%%|*}"
    rest="${rest#*|}"
    local disp_val="${rest%%|*}"
    rest="${rest#*|}"
    local has_sib="${rest}"
    
    local mod rm
    local sib_byte=""
    local disp_hex=""
    
    if [[ "$has_sib" == "1" ]]; then
        # SIB form
        local scale_bits=0
        case "$sib_scale" in
            1) scale_bits=0 ;;
            2) scale_bits=1 ;;
            4) scale_bits=2 ;;
            8) scale_bits=3 ;;
            *) error_msg "invalid scale '$sib_scale' (must be 1,2,4,8)" ;;
        esac
        local index_num=4  # "no index"
        if [[ -n "$index" ]]; then
            index_num=${regs[$index]}
            if (( index_num == 4 )); then
                error_msg "rsp/r12 cannot be used as index register"
                return 1
            fi
        fi
        
        if [[ -n "$base" ]]; then
            local base_num=${regs[$base]}
            if (( disp_val == 0 )); then
                if [[ "$base" == "rbp" || "$base" == "ebp" || "$base" == "r13" ]]; then
                    mod=1
                    disp_hex="00"
                else
                    mod=0
                fi
            elif (( disp_val >= -128 && disp_val <= 127 )); then
                mod=1
                disp_hex=$(printf "%02x" $((disp_val & 0xff)))
            else
                mod=2
                disp_hex=$(u32le "$disp_val")
            fi
            rm=4  # SIB follows
            # SIB byte: scale|index|base
            local sib_val=$((scale_bits << 6 | index_num << 3 | base_num))
            sib_byte=$(printf "%02x" $sib_val)
        else
            # No base: mod=00, rm=4, SIB base=5 (requires disp32)
            mod=0
            rm=4
            local sib_val=$((scale_bits << 6 | index_num << 3 | 5))
            sib_byte=$(printf "%02x" $sib_val)
            if [[ "$disp_val" == "0" ]]; then
                disp_hex="00000000"  # still need disp32 for [index*scale]
            elif (( disp_val >= -128 && disp_val <= 127 )); then
                disp_hex=$(u32le "$disp_val")
            else
                disp_hex=$(u32le "$disp_val")
            fi
        fi
    else
        # Simple [base+disp] form — no SIB
        [[ -z "$base" ]] && { error_msg "empty memory operand"; return 1; }
        local base_num=${regs[$base]}
        
        if (( disp_val == 0 )); then
            if [[ "$base" == "rbp" || "$base" == "ebp" || "$base" == "r13" ]]; then
                mod=1
                disp_hex="00"
            else
                mod=0
            fi
        elif (( disp_val >= -128 && disp_val <= 127 )); then
            mod=1
            disp_hex=$(printf "%02x" $((disp_val & 0xff)))
        else
            mod=2
            disp_hex=$(u32le "$disp_val")
        fi
        
        if [[ "$base" == "rsp" || "$base" == "esp" || "$base" == "r12" ]]; then
            rm=4
            sib_byte="24"  # scale=00, index=4 (none), base=rsp(4)
        else
            rm=$base_num
        fi
    fi
    
    local mod_rm_val
    mod_rm_val=$(build_mod_rm "$mod" "$reg_field" "$rm")
    printf "%s%02x%s%s" "$opcode" "$mod_rm_val" "$sib_byte" "$disp_hex"
}
assemble_arith_mem() {
    local op="$1"
    local dst="$2"
    local src="$3"
    local opcode_reg_mem 
    local opcode_mem_reg 
    case "$op" in
        add) opcode_reg_mem="4803"; opcode_mem_reg="4801" ;;
        sub) opcode_reg_mem="482b"; opcode_mem_reg="4829" ;;
        and) opcode_reg_mem="4823"; opcode_mem_reg="4821" ;;
        or)  opcode_reg_mem="480b"; opcode_mem_reg="4809" ;;
        cmp) opcode_reg_mem="483b"; opcode_mem_reg="4839" ;;
        *) echo "unsupported arith op" >&2; return 1 ;;
    esac
    if [[ "$dst" =~ ^\[.*\]$ ]]; then 
        hex_code=$(assemble_mem_operand "$dst" "${regs[$src]}" "$opcode_mem_reg")
        text_hex+=$hex_code
        current_address=$((current_address + ${#hex_code}/2))
    elif [[ "$src" =~ ^\[.*\]$ ]]; then 
        hex_code=$(assemble_mem_operand "$src" "${regs[$dst]}" "$opcode_reg_mem")
        text_hex+=$hex_code
        current_address=$((current_address + ${#hex_code}/2))
    fi
}
assemble_short_jump() {
    local op="$1"
    local lbl="$2"
    local opcode
    case "$op" in
        je) opcode="74" ;;
        jne) opcode="75" ;;
        jg) opcode="7f" ;;
        jl) opcode="7c" ;;
        jge) opcode="7d" ;;
        jle) opcode="7e" ;;
        ja) opcode="77" ;;
        jb) opcode="72" ;;
        jae) opcode="73" ;;
        jbe) opcode="76" ;;
        jo) opcode="70" ;;
        jno) opcode="71" ;;
        js) opcode="78" ;;
        jns) opcode="79" ;;
        jmp) opcode="eb" ;;
        loop) opcode="e2" ;;
        loope) opcode="e1" ;;
        loopne) opcode="e0" ;;
        *) echo "unsupported jump/loop op" >&2; return 1;;
    esac
    if [[ -z "${labels[$lbl]:-}" ]]; then
        error_msg "unknown label '$lbl'"
    fi
    local target_address=${labels[$lbl]}
    local offset=$((target_address - (current_address + 2)))
    if [ "$offset" -lt -128 ] || [ "$offset" -gt 127 ]; then
        error_msg "short jump out of range: $offset"
    fi
    local offset_hex=$(printf "%02x" $((offset & 0xff)))
    text_hex+="$opcode$offset_hex"
    current_address=$((current_address + 2))
}
calc_sse_mem_size() {
    local base="$1"
    local disp="$2"
    local prefix_len="${3:-3}"
    local size=$prefix_len
    (( size++ ))
    if [[ -z "$disp" ]]; then
        if [[ "$base" == "rbp" || "$base" == "r13" ]]; then
            (( size++ ))
        elif [[ "$base" == "rsp" || "$base" == "r12" ]]; then
            (( size++ ))
        fi
    elif (( disp >= -128 && disp <= 127 )); then
        (( size++ ))
        if [[ "$base" == "rsp" || "$base" == "r12" ]]; then
            (( size++ ))
        fi
    else
        (( size += 4 ))
        if [[ "$base" == "rsp" || "$base" == "r12" ]]; then
            (( size++ ))
        fi
    fi
    echo $size
}
