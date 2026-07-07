#!/usr/bin/env bash
get_reg_num() {
    local reg="$1"
    case "$reg" in
        al|rax|eax) echo 0 ;;
        cl|rcx|ecx) echo 1 ;;
        dl|rdx|edx) echo 2 ;;
        bl|rbx|ebx) echo 3 ;;
        spl|rsp|esp) echo 4 ;;
        bpl|rbp|ebp) echo 5 ;;
        sil|rsi|esi) echo 6 ;;
        dil|rdi|edi) echo 7 ;;
        ah) echo 4 ;;
        ch) echo 5 ;;
        dh) echo 6 ;;
        bh) echo 7 ;;
        *) echo -1 ;;
    esac
}

get_reg_size() {
    local reg="$1"
    case "$reg" in
        al|cl|dl|bl|ah|ch|dh|bh|spl|bpl|sil|dil) echo 1 ;;
        ax|cx|dx|bx|sp|bp|si|di) echo 2 ;;
        eax|ecx|edx|ebx|esp|ebp|esi|edi) echo 4 ;;
        *) echo 8 ;;
    esac
}
# Return REX prefix for a register, empty for no prefix
# 48 for 64-bit, 66 for 16-bit, 40 for spl/bpl/sil/dil, empty for 32-bit/8-bit
get_rex_for_reg() {
    local reg="$1"
    local size=$(get_reg_size "$reg")
    if (( size == 8 )); then
        echo "48"
    elif (( size == 4 )); then
        echo ""
    elif (( size == 2 )); then
        echo "66"
    else
        case "$reg" in
            spl|bpl|sil|dil) echo "40" ;;
            *) echo "" ;;
        esac
    fi
}
build_mod_rm() {
    local mod=$1 reg=$2 rm=$3
    echo $((mod * 64 + reg * 8 + rm))
}
parse_immediate() {
    local arg=$1
    if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
        echo $((16#${BASH_REMATCH[1]}))
    elif [[ "$arg" =~ ^[0-9]+$ ]]; then
        echo $((arg))
    elif [[ -n "${equs[$arg]:-}" ]]; then
        echo ${equs[$arg]}
    else
        error_msg "unknown immediate '$arg'"
    fi
}
calc_mem_addr_size() {
    local base="$1"
    local disp="$2"
    
    local size=4
    if [[ "$base" == "rsp" || "$base" == "r12" || "$base" == "esp" ]]; then
        if [[ -z "$disp" ]]; then
            size=3
        else
            if (( disp >= -128 && disp <= 127 )); then
                size=5
            else
                size=8
            fi
        fi
    else
        if [[ -z "$disp" ]]; then
            size=3
        elif [[ "$base" == "rbp" || "$base" == "r13" || "$base" == "ebp" ]]; then
            size=4
        else
            if (( disp >= -128 && disp <= 127 )); then
                size=4
            else
                size=7
            fi
        fi
    fi
    echo $size
}
# SIB-aware memory operand size: accepts content of [ ], e.g., "rbx" or "rbx+rcx*4+16"
calc_mem_operand_size() {
    local mem_content="$1"
    local rex_prefix="${2:-1}"
    calc_mem_encoding_size "$mem_content" "$rex_prefix"
}
calculate_mov_size() {
    local dest_reg="${BASH_REMATCH[1]}"
    local dreg_num=$(get_reg_num "$dest_reg")
    arg="${BASH_REMATCH[2]}"
    if [[ "$arg" =~ ^\[([^]]+)\]$ ]]; then
        # reg, [mem]
        local mem="${BASH_REMATCH[1]}"
        local cm_size=$(calc_mem_operand_size "$mem")
        local cm_rex=$(get_rex_for_reg "$dest_reg")
        [[ -z "$cm_rex" ]] && cm_size=$((cm_size - 1))
        text_bytes_len=$((text_bytes_len + cm_size))
    elif [[ "$arg" =~ ^\[([^]]+)\],[[:space:]]+([er][a-z]{2})$ ]]; then
        # [mem], reg
        local mem="${BASH_REMATCH[1]}"
        local cm2_reg="${BASH_REMATCH[2]}"
        local cm2_size=$(calc_mem_operand_size "$mem")
        local cm2_rex=$(get_rex_for_reg "$cm2_reg")
        [[ -z "$cm2_rex" ]] && cm2_size=$((cm2_size - 1))
        text_bytes_len=$((text_bytes_len + cm2_size))
    elif [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^-?[0-9]+$ ]] || [[ "$arg" =~ ^0x[0-9a-fA-F]+$ ]] || [[ -n "${equs[$arg]:-}" ]]; then
        if (( dreg_num >= 0 && $(get_reg_size "$dest_reg") == 1 )); then
            text_bytes_len=$((text_bytes_len + 2))
        elif (( dreg_num >= 0 && $(get_reg_size "$dest_reg") == 4 )); then
            text_bytes_len=$((text_bytes_len + 5))
        else
            if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                val=$((16#${BASH_REMATCH[1]}))
            elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
                val=$((arg))
            elif [[ -n "${equs[$arg]:-}" ]]; then
                val=${equs[$arg]}
            fi
            if (( val >= -2147483648 && val <= 2147483647 )); then
                text_bytes_len=$((text_bytes_len + 7))
            else
                text_bytes_len=$((text_bytes_len + 10))
            fi
        fi
    else
        text_bytes_len=$((text_bytes_len + 10))
    fi
}
calculate_arith_ri_size() {
    reg="${BASH_REMATCH[2]}"
    arg="${BASH_REMATCH[3]}"
    local ar_rex=$(get_rex_for_reg "$reg")
    if [[ "$reg" == "rax" ]]; then
        if [[ "$line" =~ ^cmp.*$ ]]; then
            text_bytes_len=$((text_bytes_len + 5 + ${#ar_rex}/2))
        else
            text_bytes_len=$((text_bytes_len + 6 + ${#ar_rex}/2))
        fi
    else
        # Check if imm8 is sufficient
        local arv=0
        if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
            arv=$((16#${BASH_REMATCH[1]}))
        elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
            arv=$((arg))
        fi
        if (( arv >= -128 && arv <= 127 )); then
            # 83 /0 ib (3 bytes) + REX
            text_bytes_len=$((text_bytes_len + 3 + ${#ar_rex}/2))
        else
            # 81 /0 id (6 bytes) + REX
            text_bytes_len=$((text_bytes_len + 6 + ${#ar_rex}/2))
        fi
    fi
}
calculate_simple_instr_size() {
    case "$line" in
        syscall) text_bytes_len=$((text_bytes_len + 2)) ;;
        nop) text_bytes_len=$((text_bytes_len + 1)) ;;
        ret) text_bytes_len=$((text_bytes_len + 1)) ;;
        leave) text_bytes_len=$((text_bytes_len + 1)) ;;
        cqo) text_bytes_len=$((text_bytes_len + 2)) ;;
        cdqe) text_bytes_len=$((text_bytes_len + 2)) ;;
    esac
}
handle_fp_operation() {
    local op_name="$1"
    local size="$2"
    local dst="${BASH_REMATCH[1]}"
    local src="${BASH_REMATCH[2]}"
    local mod_rm=$((0xc0 + xmm_regs[$dst] * 8 + xmm_regs[$src]))
    text_hex+="${fp_opcodes["$op_name"]}$(printf "%02x" $mod_rm)"
    current_address=$((current_address + size))
}
append_instruction() {
    local hex=$1 size=$2
    text_hex+=$hex
    ((current_address += size))
}
parse_operands() {
    local line=$1
    
    IFS=' ' read -r mnemonic op1 op2 op3 <<< "$line"
    
    mnemonic=$(trim_string "$mnemonic")
    op1=$(trim_string "$op1")
    op2=$(trim_string "$op2")
    op3=$(trim_string "$op3")
    echo "$mnemonic|$op1|$op2|$op3"
}
