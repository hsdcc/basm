#!/usr/bin/env bash

# helper to get register number for byte registers too
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

# helper functions for assembling
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

# calculate mov memory operand size based on addressing mode
# used by both first pass (sizing) and second pass (code generation)
calc_mem_addr_size() {
    local base="$1"
    local disp="$2"
    
    local size=4
    if [[ "$base" == "rsp" || "$base" == "r12" ]]; then
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
        elif [[ "$base" == "rbp" || "$base" == "r13" ]]; then
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

# helper function to calculate mov instruction size based on addressing mode
calculate_mov_size() {
    arg="${BASH_REMATCH[2]}"
    if [[ "$arg" =~ ^\[(r[a-z]{2})([\+\-][0-9]+)?\]$ ]]; then
        base="${BASH_REMATCH[1]}"
        disp="${BASH_REMATCH[2]:-}"
        size=$(calc_mem_addr_size "$base" "$disp")
        text_bytes_len=$((text_bytes_len + size))
    elif [[ "$arg" =~ ^\[(r[a-z]{2})([\+\-][0-9]+)?\],[[:space:]]+(r[a-z]{2})$ ]]; then
        base="${BASH_REMATCH[1]}"
        disp="${BASH_REMATCH[2]:-}"
        size=$(calc_mem_addr_size "$base" "$disp")
        text_bytes_len=$((text_bytes_len + size))
    elif [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^-?[0-9]+$ ]] || [[ "$arg" =~ ^0x[0-9a-fA-F]+$ ]] || [[ -n "${equs[$arg]:-}" ]]; then
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
    else
        text_bytes_len=$((text_bytes_len + 10))
    fi
}

# helper function to calculate arithmetic reg,imm size based on register and value
calculate_arith_ri_size() {
    reg="${BASH_REMATCH[2]}"
    arg="${BASH_REMATCH[3]}"
    if [[ "$reg" == "rax" ]]; then
        if [[ "$line" =~ ^cmp.*$ ]]; then
            text_bytes_len=$((text_bytes_len + 6))
        else
            text_bytes_len=$((text_bytes_len + 7))
        fi
    else
        text_bytes_len=$((text_bytes_len + 4))
    fi
}

# helper function to calculate simple instruction size
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

# helper function to handle floating point operations
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
    # simple split by space, assume max 3 operands
    IFS=' ' read -r mnemonic op1 op2 op3 <<< "$line"
    # trim
    mnemonic=$(trim_string "$mnemonic")
    op1=$(trim_string "$op1")
    op2=$(trim_string "$op2")
    op3=$(trim_string "$op3")
    echo "$mnemonic|$op1|$op2|$op3"
}