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
assemble_mem_operand() {
    local mem_op="$1"
    local reg_field="$2"
    local opcode="$3"
    
    if [[ "$mem_op" =~ \[([a-z0-9]+)(([+-])([0-9]+))?\] ]]; then
        local base_reg="${BASH_REMATCH[1]}"
        local sign="${BASH_REMATCH[3]:-+}"
        local disp_val="${BASH_REMATCH[4]:-0}"
        local disp=$((disp_val))
        if [[ "$sign" == "-" ]]; then
            disp=$((-disp))
        fi
        local mod
        local rm
        local sib=""
        local disp_hex=""
        
        if [[ -z "${regs[$base_reg]:-}" ]]; then
            error_msg "invalid base register '$base_reg' in memory operand '$mem_op'"
        fi
        
        if (( disp == 0 )); then
            mod=0
            if [[ "$base_reg" == "rbp" || "$base_reg" == "r13" || "$base_reg" == "ebp" ]]; then
                mod=1
                disp_hex="00"
            fi
        elif (( disp >= -128 && disp <= 127 )); then
            mod=1
            disp_hex=$(printf "%02x" $((disp & 0xff)))
        else
            mod=2
            disp_hex=$(u32le "$disp")
        fi
        rm=${regs[$base_reg]}
        if [[ "$base_reg" == "rsp" || "$base_reg" == "r12" || "$base_reg" == "esp" ]]; then
            rm=4 
            sib="24" 
        fi
        local mod_rm
        mod_rm=$(build_mod_rm "$mod" "$reg_field" "$rm")
        printf "%s%02x%s%s" "$opcode" "$mod_rm" "$sib" "$disp_hex"
    else
        error_msg "unsupported memory operand in mov: $mem_op"
    fi
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
