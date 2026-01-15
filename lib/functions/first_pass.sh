#!/usr/bin/env bash

# perform first pass: parse instructions, calculate sizes, collect labels
first_pass() {
    local raw_lines_ref="$1"
    local code_str="$2"
    local -n lines_ref="$1"
    
    # re-initialize variables for first pass
    data_bytes=""
    text_ins=()
    text_bytes_len=0
    in_section=""
    line_number=0
    
    # declare associative arrays
    declare -gA labels
    declare -gA data_label_off
    declare -gA equs
    
    # read lines
    mapfile -t lines_ref <<<"$code_str"

    # first pass: parse instructions, calculate sizes, collect labels
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
        global\ *) continue ;;
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
                # process escape sequences using pure bash
                txt="${txt//\\/\\\\x5c}"    # replace \ with \\x5c
                txt="${txt//
/\\n}"          # replace newlines with \n
                txt="${txt//\"/\\\"}"           # replace " with \"
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
        elif [[ "$in_section" == "text" ]]; then
            if [[ "$line" =~ ^([.a-zA-Z0-9_]+):$ ]]; then
                lbl="${BASH_REMATCH[1]}"
                labels["$lbl"]="$text_bytes_len"
                continue
            fi
            text_ins+=("$line")
            
            # handle mov reg, reg (3 bytes)
            if [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            # handle CMOV (4 bytes)
            elif [[ "$line" =~ $cmov_pattern ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            # handle various MOV patterns
            elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$ ]]; then
                calculate_mov_size
            # handle simple instructions (1-2 bytes)
            elif [[ "$line" =~ ^(syscall|nop|ret|leave|cqo|cdqe)$ ]]; then
                calculate_simple_instr_size
            # handle XOR reg, reg with same register (3 bytes)
            elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            # handle PUSH/POP (1 byte each)
            elif [[ "$line" =~ ^(push|pop)[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 1))
            # handle arithmetic reg, reg (3 bytes)
            elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            # handle arithmetic reg, immediate/memory
            elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]*(.*)$ ]]; then
                calculate_arith_ri_size
            # handle jumps (2 bytes)
            elif [[ "$line" =~ ^(je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jo|jno|js|jns|jmp)[[:space:]]+(.*)$ ]]; then
                text_bytes_len=$((text_bytes_len + 2))
            # handle loops (2 bytes)
            elif [[ "$line" =~ ^(loop|loope|loopne)[[:space:]]+(.*)$ ]]; then
                text_bytes_len=$((text_bytes_len + 2))
            # handle unary operations (inc, dec, neg, not) (3 bytes)
            elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            # handle CALL (5 bytes)
            elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 5))
            # handle MUL/DIV/IDIV (3 bytes)
            elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            # handle IMUL reg, reg (4 bytes)
            elif [[ "$line" =~ ^(imul)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            # handle LEA (7 bytes)
            elif [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
                text_bytes_len=$((text_bytes_len + 7))
            # handle shifts (4 bytes)
            elif [[ "$line" =~ ^(shl|shr|sar)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            # handle TEST reg, reg (3 bytes)
            elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            # handle TEST reg, immediate (7 bytes)
            elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
                text_bytes_len=$((text_bytes_len + 7))
            # handle MOVZX/MOVSX with 8/16-bit registers (4 bytes)
            elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh])$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            # handle MOVZX/MOVSX with 32/64-bit registers (4 bytes)
            elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 4))
            # handle MOVSXD (3 bytes)
            elif [[ "$line" =~ ^movsxd[[:space:]]+(r[a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            # handle SETCC (3 bytes)
            elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
                text_bytes_len=$((text_bytes_len + 3))
            # handle floating point instructions (4 bytes each)
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