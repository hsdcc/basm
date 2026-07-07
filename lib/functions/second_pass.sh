#!/usr/bin/env bash
second_pass() {
    local text_ins_ref="$1"
    local -n ins_array="$1"
    
    text_hex=""
    current_address=0
    
    for line in "${ins_array[@]}"; do
            # Detect size keywords (from @markers or raw text) and strip
            detected_size_kw=""
            if [[ "$line" =~ @(byte|word|dword|qword)[[:space:]](.*) ]]; then
                detected_size_kw="${BASH_REMATCH[1]}"
                line="$(trim_string "${BASH_REMATCH[2]}")"
            elif [[ "$line" =~ (byte|word|dword|qword)[[:space:]]+\[ ]]; then
                if [[ "$line" =~ qword[[:space:]]+[[] ]]; then
                    detected_size_kw="qword"
                elif [[ "$line" =~ dword[[:space:]]+[[] ]]; then
                    detected_size_kw="dword"
                elif [[ "$line" =~ word[[:space:]]+[[] ]]; then
                    detected_size_kw="word"
                elif [[ "$line" =~ byte[[:space:]]+[[] ]]; then
                    detected_size_kw="byte"
                fi
                line="${line//dword [/[}"
                line="${line//qword [/[}"
                line="${line//word [/[}"
                line="${line//byte [/[}"
            fi
        
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
        elif [[ "$line" =~ $sse_mem_src_pattern ]]; then
            local sse_mne="${BASH_REMATCH[1]}"
            local sse_xmm="${BASH_REMATCH[2]}"
            local sse_mem_content="${BASH_REMATCH[3]}"
            local sse_mem_op="[$sse_mem_content]"
            local sse_opcode
            if [[ "$sse_mne" == "comiss" || "$sse_mne" == "comisd" || "$sse_mne" == "ucomiss" || "$sse_mne" == "ucomisd" ]]; then
                sse_opcode="${fp_opcodes[$sse_mne]}"
            else
                sse_opcode="${fp_opcodes[${sse_mne}_rr]}"
            fi
            local sse_hex=$(assemble_mem_operand "$sse_mem_op" "${xmm_regs[$sse_xmm]}" "$sse_opcode")
            text_hex+=$sse_hex
            current_address=$((current_address + ${#sse_hex}/2))
        elif [[ "$line" =~ $sse_mem_dst_pattern ]]; then
            local sd_mne="${BASH_REMATCH[1]}"
            local sd_mem_content="${BASH_REMATCH[2]}"
            local sd_xmm="${BASH_REMATCH[3]}"
            local sd_mem_op="[$sd_mem_content]"
            local sd_opcode="${fp_opcodes[${sd_mne}_store]}"
            local sd_hex=$(assemble_mem_operand "$sd_mem_op" "${xmm_regs[$sd_xmm]}" "$sd_opcode")
            text_hex+=$sd_hex
            current_address=$((current_address + ${#sd_hex}/2))
        elif [[ "$line" =~ $cvtsi2s_reg_pattern ]]; then
            local c2_mne="${BASH_REMATCH[1]}"
            local c2_xmm="${BASH_REMATCH[2]}"
            local c2_reg="${BASH_REMATCH[3]}"
            local c2_mod_rm=$(build_mod_rm 3 ${xmm_regs[$c2_xmm]} ${regs[$c2_reg]})
            text_hex+="${fp_opcodes[$c2_mne]}$(printf "%02x" $c2_mod_rm)"
            current_address=$((current_address + 4))
        elif [[ "$line" =~ $cvtsi2s_mem_pattern ]]; then
            local c2m_mne="${BASH_REMATCH[1]}"
            local c2m_xmm="${BASH_REMATCH[2]}"
            local c2m_mem_content="${BASH_REMATCH[3]}"
            local c2m_mem_op="[$c2m_mem_content]"
            local c2m_hex=$(assemble_mem_operand "$c2m_mem_op" "${xmm_regs[$c2m_xmm]}" "${fp_opcodes[$c2m_mne]}")
            text_hex+=$c2m_hex
            current_address=$((current_address + ${#c2m_hex}/2))
        elif [[ "$line" =~ $cvtss2si_rr_pattern ]]; then
            local cs_reg="${BASH_REMATCH[1]}"
            local cs_xmm="${BASH_REMATCH[2]}"
            local cs_mod_rm=$(build_mod_rm 3 ${regs[$cs_reg]} ${xmm_regs[$cs_xmm]})
            text_hex+="${fp_opcodes["cvtss2si"]}$(printf "%02x" $cs_mod_rm)"
            current_address=$((current_address + 4))
        elif [[ "$line" =~ $cvtss2s_mem_pattern ]]; then
            local csm_mne="${BASH_REMATCH[1]}"
            local csm_reg="${BASH_REMATCH[2]}"
            local csm_mem_content="${BASH_REMATCH[3]}"
            local csm_mem_op="[$csm_mem_content]"
            local csm_hex=$(assemble_mem_operand "$csm_mem_op" "${regs[$csm_reg]}" "${fp_opcodes[$csm_mne]}")
            text_hex+=$csm_hex
            current_address=$((current_address + ${#csm_hex}/2))
        elif [[ "$line" =~ $cvtsd2si_pattern ]]; then
            reg="${BASH_REMATCH[1]}"
            xmm="${BASH_REMATCH[2]}"
            mod_rm=$((0xc0 | regs[$reg] << 3 | xmm_regs[$xmm]))
            text_hex+="${fp_opcodes["cvtsd2si"]}$(printf "%02x" $mod_rm)"
            current_address=$((current_address + 4))
        elif [[ "$line" =~ $movzx_word_mem_pattern ]]; then
            # movzx reg, word|byte [mem]
            op="${BASH_REMATCH[1]}"
            dst="${BASH_REMATCH[2]}"
            local zwmem="${BASH_REMATCH[4]}"
            local zwmem_op="[$zwmem]"
            dst_reg=$(get_reg_num "$dst")
            local rex=$(get_rex_for_reg "$dst")
            if [[ "$detected_size_kw" == "word" ]]; then
                local zwhex=$(assemble_mem_operand "$zwmem_op" "${regs[$dst]}" "${rex}0fb7")
            else
                local zwhex=$(assemble_mem_operand "$zwmem_op" "${regs[$dst]}" "${rex}0fb6")
            fi
            text_hex+=$zwhex
            current_address=$((current_address + ${#zwhex}/2))
        elif [[ "$line" =~ $movsx_word_mem_pattern ]]; then
            # movsx reg, word|byte [mem]
            op="${BASH_REMATCH[1]}"
            dst="${BASH_REMATCH[2]}"
            local swmem="${BASH_REMATCH[4]}"
            local swmem_op="[$swmem]"
            dst_reg=$(get_reg_num "$dst")
            local rex=$(get_rex_for_reg "$dst")
            if [[ "$detected_size_kw" == "word" ]]; then
                local swhex=$(assemble_mem_operand "$swmem_op" "${regs[$dst]}" "${rex}0fbf")
            else
                local swhex=$(assemble_mem_operand "$swmem_op" "${regs[$dst]}" "${rex}0fbe")
            fi
            text_hex+=$swhex
            current_address=$((current_address + ${#swhex}/2))
        elif [[ "$line" =~ $movzx_mem_pattern ]]; then
            op="${BASH_REMATCH[1]}"
            dst="${BASH_REMATCH[2]}"
            local zmem="${BASH_REMATCH[4]}"
            local zmem_op="[$zmem]"
            dst_reg=$(get_reg_num "$dst")
            local rex=$(get_rex_for_reg "$dst")
            zhex=$(assemble_mem_operand "$zmem_op" "${regs[$dst]}" "${rex}0fb6")
            text_hex+=$zhex
            current_address=$((current_address + ${#zhex}/2))
        elif [[ "$line" =~ $movsx_mem_pattern ]]; then
            op="${BASH_REMATCH[1]}"
            dst="${BASH_REMATCH[2]}"
            local smem="${BASH_REMATCH[4]}"
            local smem_op="[$smem]"
            dst_reg=$(get_reg_num "$dst")
            local rex=$(get_rex_for_reg "$dst")
            shex=$(assemble_mem_operand "$smem_op" "${regs[$dst]}" "${rex}0fbe")
            text_hex+=$shex
            current_address=$((current_address + ${#shex}/2))
        elif [[ "$line" =~ $movsxd_mem_pattern ]]; then
            dst="${BASH_REMATCH[1]}"
            local xmem="${BASH_REMATCH[3]}"
            local xmem_op="[$xmem]"
            dst_reg=$(get_reg_num "$dst")
            local rex=$(get_rex_for_reg "$dst")
            xhex=$(assemble_mem_operand "$xmem_op" "${regs[$dst]}" "${rex}63")
            text_hex+=$xhex
            current_address=$((current_address + ${#xhex}/2))
        elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+([er][a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh]|dil|sil|bpl|spl|[er][a-z]{2})$ ]]; then
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
            local rex=$(get_rex_for_reg "$dst")
            if [[ "$op" == "movzx" ]]; then
                text_hex+="${rex}0fb6$(printf "%02x" $mod_rm)"
            else
                text_hex+="${rex}0fbe$(printf "%02x" $mod_rm)"
            fi
            current_address=$((current_address + 3 + ${#rex}/2))
        elif [[ "$line" =~ ^movsxd[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
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
            local rex=$(get_rex_for_reg "$dst")
            text_hex+="${rex}63$(printf "%02x" $mod_rm)"
            current_address=$((current_address + 2 + ${#rex}/2))
        elif [[ "$line" =~ $string_op_pattern ]]; then
            case "$line" in
                movsb) text_hex+="a4"; current_address=$((current_address + 1)) ;;
                movsw) text_hex+="66a5"; current_address=$((current_address + 2)) ;;
                movsl) text_hex+="a5"; current_address=$((current_address + 1)) ;;
                movsq) text_hex+="48a5"; current_address=$((current_address + 2)) ;;
                stosb) text_hex+="aa"; current_address=$((current_address + 1)) ;;
                stosw) text_hex+="66ab"; current_address=$((current_address + 2)) ;;
                stosl) text_hex+="ab"; current_address=$((current_address + 1)) ;;
                stosq) text_hex+="48ab"; current_address=$((current_address + 2)) ;;
                lodsb) text_hex+="ac"; current_address=$((current_address + 1)) ;;
                lodsw) text_hex+="66ad"; current_address=$((current_address + 2)) ;;
                lodsl) text_hex+="ad"; current_address=$((current_address + 1)) ;;
                lodsq) text_hex+="48ad"; current_address=$((current_address + 2)) ;;
                scasb) text_hex+="ae"; current_address=$((current_address + 1)) ;;
                scasw) text_hex+="66af"; current_address=$((current_address + 2)) ;;
                scasl) text_hex+="af"; current_address=$((current_address + 1)) ;;
                scasq) text_hex+="48af"; current_address=$((current_address + 2)) ;;
                cmpsb) text_hex+="a6"; current_address=$((current_address + 1)) ;;
                cmpsw) text_hex+="66a7"; current_address=$((current_address + 2)) ;;
                cmpsl) text_hex+="a7"; current_address=$((current_address + 1)) ;;
                cmpsq) text_hex+="48a7"; current_address=$((current_address + 2)) ;;
                cld) text_hex+="fc"; current_address=$((current_address + 1)) ;;
                std) text_hex+="fd"; current_address=$((current_address + 1)) ;;
            esac

        elif [[ "$line" =~ ^mov ]]; then
            local mov_operands="${line#mov }"
            local dst="${mov_operands%%,*}"
            local src="${mov_operands#*,}"
            dst=$(trim_string "$dst")
            src=$(trim_string "$src")
            local dst_reg_num=$(get_reg_num "$dst")
            local src_reg_num=$(get_reg_num "$src")
            if (( dst_reg_num >= 0 && src_reg_num >= 0 )); then
                # mov reg, reg — size depends on destination register
                local rex=$(get_rex_for_reg "$dst")
                local size=2  # opcode + modrm
                [[ -n "$rex" ]] && size=$((size + 1))
                local mod_rm=$((0xc0 + src_reg_num * 8 + dst_reg_num))
                if (( $(get_reg_size "$dst") == 1 )); then
                    # Byte move: use 8-bit opcode (88 for mov r/m8, r8)
                    text_hex+="${rex}88$(printf "%02x" "$mod_rm")"
                else
                    text_hex+="${rex}89$(printf "%02x" "$mod_rm")"
                fi
                current_address=$((current_address + size))
            elif [[ "$src" =~ ^(-?[0-9]+|0x[0-9a-fA-F]+)$ && "$dst" =~ \[.*\]$ ]]; then
                # mov [mem], imm
                local mmi_val=0
                if [[ "$src" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    mmi_val=$((16#${BASH_REMATCH[1]}))
                else
                    mmi_val=$((src))
                fi
                local mmi_mem_op="$dst"
                local mmi_opcode="48c7"
                if [[ "$detected_size_kw" == "byte" ]]; then
                    mmi_opcode="c6"
                elif [[ "$detected_size_kw" == "word" ]]; then
                    mmi_opcode="66c7"
                elif [[ "$detected_size_kw" == "dword" ]]; then
                    mmi_opcode="c7"
                elif [[ "$detected_size_kw" == "qword" ]]; then
                    mmi_opcode="48c7"
                fi
                local mmi_hex=$(assemble_mem_operand "$mmi_mem_op" 0 "$mmi_opcode")
                text_hex+=$mmi_hex
                current_address=$((current_address + ${#mmi_hex}/2))
                if [[ "$mmi_opcode" == "c6" ]]; then
                    text_hex+=$(printf "%02x" $((mmi_val & 0xff)))
                    current_address=$((current_address + 1))
                elif [[ "$detected_size_kw" == "word" ]]; then
                    local imm16=$((mmi_val & 0xffff))
                    text_hex+=$(printf "%02x%02x" $((imm16 & 0xff)) $(((imm16 >> 8) & 0xff)))
                    current_address=$((current_address + 2))
                else
                    text_hex+=$(u32le $mmi_val)
                    current_address=$((current_address + 4))
                fi
            elif [[ "$dst" =~ ^\[.*\]$ ]]; then 
                # mov [mem], reg
                local src_size=$(get_reg_size "$src")
                local rex=$(get_rex_for_reg "$src")
                local mop="89"
                if (( src_size == 1 )); then
                    mop="88"
                fi
                hex_code=$(assemble_mem_operand "$dst" "${regs[$src]}" "${rex}${mop}")
                text_hex+=$hex_code
                current_address=$((current_address + ${#hex_code}/2))
            elif [[ "$src" =~ ^\[.*\]$ ]]; then 
                # mov reg, [mem]
                local dst_size=$(get_reg_size "$dst")
                local rex=$(get_rex_for_reg "$dst")
                local mop="8b"
                if (( dst_size == 1 )); then
                    mop="8a"
                fi
                hex_code=$(assemble_mem_operand "$src" "${regs[$dst]}" "${rex}${mop}")
                text_hex+=$hex_code
                current_address=$((current_address + ${#hex_code}/2))
            elif (( dst_reg_num >= 0 )) && [[ "$src" =~ ^(-?[0-9]+|0x[0-9a-fA-F]+)$ ]]; then
                # mov reg, imm
                local byte_reg="$dst"
                local byte_val=0
                if [[ "$src" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    byte_val=$((16#${BASH_REMATCH[1]}))
                else
                    byte_val=$((src))
                fi
                local reg_size=$(get_reg_size "$byte_reg")
                local rex=$(get_rex_for_reg "$byte_reg")
                if (( reg_size == 1 )); then
                    if [[ "$byte_reg" == "spl" || "$byte_reg" == "bpl" || "$byte_reg" == "sil" || "$byte_reg" == "dil" ]]; then
                        text_hex+=$(printf "40%02x%02x" $((0xb0 + dst_reg_num)) $((byte_val & 0xff)) )
                    else
                        text_hex+=$(printf "%02x%02x" $((0xb0 + dst_reg_num)) $((byte_val & 0xff)) )
                    fi
                    current_address=$((current_address + 2))
                elif (( reg_size == 4 )); then
                    text_hex+=$(printf "%02x" $((0xb8 + dst_reg_num)))$(u32le $byte_val)
                    current_address=$((current_address + 5))
                elif (( byte_val >= -2147483648 && byte_val <= 2147483647 )); then
                    local opcode=$((0xc0 + dst_reg_num))
                    text_hex+="${rex}c7$(printf "%02x" "$opcode")"$(u32le $byte_val)
                    local isize=$((6 + ${#rex}/2))
                    current_address=$((current_address + isize))
                else
                    local op=$((0xb8 + dst_reg_num))
                    text_hex+="${rex}$(printf "%02x" "$op")"$(u64le $byte_val)
                    local isize=$((9 + ${#rex}/2))
                    current_address=$((current_address + isize))
                fi
            else
                # mov reg, label/equ/immediate
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
                local rex=$(get_rex_for_reg "$reg")
                if [[ "$val_is_immediate" -eq 1 ]]; then
                    if (( val >= -2147483648 && val <= 2147483647 )); then
                        opcode=$((0xc0 + regs[$reg]))
                        text_hex+="${rex}c7$(printf "%02x" "$opcode")"$(u32le $val)
                        current_address=$((current_address + 6 + ${#rex}/2))
                    else
                        op=$((0xb8 + regs[$reg]))
                        text_hex+="${rex}$(printf "%02x" "$op")"$(u64le $val)
                        current_address=$((current_address + 9 + ${#rex}/2))
                    fi
                else
                    op=$((0xb8 + regs[$reg]))
                    if [[ -n "${data_label_off[$arg]:-}" ]]; then
                        addr=$((data_vaddr + data_label_off[$arg]))
                        relocations+=("$((current_address + 2)):${arg}:1:0")
                    elif [[ -n "${rodata_label_off[$arg]:-}" ]]; then
                        addr=$((data_vaddr + rodata_label_off[$arg]))
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
                    text_hex+="${rex}$(printf "%02x" "$op")"$(u64le $addr)
                    current_address=$((current_address + 9 + ${#rex}/2))
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
            local rex=$(get_rex_for_reg "$dst")
            text_hex+="${rex}0f$(printf "%02x%02x" "$cc" "$mod_rm")"
            current_address=$((current_address + 3 + ${#rex}/2))
        elif [[ "$line" =~ ^(syscall|nop|ret|leave|cqo|cdqe)$ ]]; then
            
            case "$line" in
                syscall) text_hex+="0f05"; current_address=$((current_address + 2)) ;;
                nop) text_hex+="90"; current_address=$((current_address + 1)) ;;
                ret) text_hex+="c3"; current_address=$((current_address + 1)) ;;
                leave) text_hex+="c9"; current_address=$((current_address + 1)) ;;
                cqo) text_hex+="4899"; current_address=$((current_address + 2)) ;;
                cdqe) text_hex+="4898"; current_address=$((current_address + 2)) ;;
            esac
        elif [[ "$line" =~ ^xor[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
            reg="${BASH_REMATCH[1]}"
            local rex=$(get_rex_for_reg "$reg")
            mod_rm=$((0xc0 + regs[$reg] * 8 + regs[$reg]))
            text_hex+="${rex}31$(printf "%02x" $mod_rm)"
            current_address=$((current_address + 2 + ${#rex}/2))
        elif [[ "$line" =~ ^push[[:space:]]+([er][a-z]{2})$ ]]; then
            reg="${BASH_REMATCH[1]}"
            # In 64-bit mode, push/pop only use 64-bit registers
            op=$((0x50 + regs[$reg]))
            text_hex+=$(printf "%02x" $op)
            current_address=$((current_address + 1))
        elif [[ "$line" =~ ^pop[[:space:]]+([er][a-z]{2})$ ]]; then
            reg="${BASH_REMATCH[1]}"
            op=$((0x58 + regs[$reg]))
            text_hex+=$(printf "%02x" $op)
            current_address=$((current_address + 1))
        elif [[ "$line" =~ $push_imm_pattern ]]; then
            arg="${BASH_REMATCH[1]}"
            if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                val=$((16#${BASH_REMATCH[1]}))
            else
                val=$((arg))
            fi
            if (( val >= -128 && val <= 127 )); then
                text_hex+=$(printf "6a%02x" $((val & 0xff)))
                current_address=$((current_address + 2))
            else
                text_hex+=$(printf "68")$(u32le $val)
                current_address=$((current_address + 5))
            fi
        elif [[ "$line" =~ $push_equsym_pattern ]]; then
            sym="${BASH_REMATCH[1]}"
            if [[ -n "${equs[$sym]:-}" ]]; then
                val=${equs[$sym]}
                if (( val >= -128 && val <= 127 )); then
                    text_hex+=$(printf "6a%02x" $((val & 0xff)))
                    current_address=$((current_address + 2))
                else
                    text_hex+=$(printf "68")$(u32le $val)
                    current_address=$((current_address + 5))
                fi
            else
                error_msg "unknown symbol '$sym' in push instruction"
            fi
        elif [[ "$line" =~ $push_mem_pattern ]]; then
            local pmem_content="${BASH_REMATCH[2]}"
            local pmem_op="[$pmem_content]"
            hex_code=$(assemble_mem_operand "$pmem_op" 6 "ff")
            text_hex+=$hex_code
            current_address=$((current_address + ${#hex_code}/2))
        elif [[ "$line" =~ $pop_mem_pattern ]]; then
            local pmem_content="${BASH_REMATCH[2]}"
            local pmem_op="[$pmem_content]"
            hex_code=$(assemble_mem_operand "$pmem_op" 0 "488f")
            text_hex+=$hex_code
            current_address=$((current_address + ${#hex_code}/2))

        elif [[ "$line" =~ $arith_mem_imm_pattern ]]; then
            local mop="${BASH_REMATCH[1]}"
            local mmem_content="${BASH_REMATCH[2]}"
            local mimm="${BASH_REMATCH[3]}"
            local mval=0
            if [[ "$mimm" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                mval=$((16#${BASH_REMATCH[1]}))
            elif [[ "$mimm" =~ ^-?[0-9]+$ ]]; then
                mval=$((mimm))
            else
                error_msg "invalid immediate '$mimm' in '$line'"
                return 1
            fi
            local mext=0
            case "$mop" in
                add) mext=0 ;;
                or)  mext=1 ;;
                and) mext=4 ;;
                sub) mext=5 ;;
                xor) mext=6 ;;
                cmp) mext=7 ;;
            esac
            local mmem_op="[$mmem_content]"
            if (( mval >= -128 && mval <= 127 )); then
                local mhex=$(assemble_mem_operand "$mmem_op" "$mext" "4883")
                text_hex+=$mhex
                current_address=$((current_address + ${#mhex}/2))
                text_hex+=$(printf "%02x" $((mval & 0xff)))
                current_address=$((current_address + 1))
            else
                local mhex=$(assemble_mem_operand "$mmem_op" "$mext" "4881")
                text_hex+=$mhex
                current_address=$((current_address + ${#mhex}/2))
                text_hex+=$(u32le $mval)
                current_address=$((current_address + 4))
            fi
        
        elif [[ "$line" =~ ^(add|sub|cmp|or|and) ]]; then
            local op="${BASH_REMATCH[1]}"
            local operands="${line#$op }"
            local dst="${operands%%,*}"
            local src="${operands#*,}"
            dst=$(trim_string "$dst")
            src=$(trim_string "$src")
            if [[ "$dst" =~ ^[er][a-z]{2}$ && "$src" =~ ^[er][a-z]{2}$ ]]; then
                # reg, reg
                local reg1="$dst"
                local reg2="$src"
                local rex=$(get_rex_for_reg "$dst")
                local mod_rm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
                local asize=2
                [[ -n "$rex" ]] && asize=$((asize + 1))
                case "$op" in
                add) text_hex+="${rex}01$(printf "%02x" $mod_rm)" ;;
                sub) text_hex+="${rex}29$(printf "%02x" $mod_rm)" ;;
                and) text_hex+="${rex}21$(printf "%02x" $mod_rm)" ;;
                or) text_hex+="${rex}09$(printf "%02x" $mod_rm)" ;;
                cmp) text_hex+="${rex}39$(printf "%02x" $mod_rm)" ;;
                esac
                current_address=$((current_address + asize))
            elif [[ "$dst" =~ ^\[.*\]$ || "$src" =~ ^\[.*\]$ ]]; then
                # arith with mem operand
                assemble_arith_mem "$op" "$dst" "$src"
            else
                # reg, imm
                local reg="$dst"
                local arg="$src"
                if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                    val=$((16#${BASH_REMATCH[1]}))
                elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
                    val=$((arg))
                else
                    echo "error: unknown immediate value '$arg' in '$line'" >&2
                    return 1
                fi
                local rex
                if [[ "$reg" == "rax" ]]; then
                    rex=$(get_rex_for_reg "$reg")
                    case "$op" in
                    add)
                        text_hex+="${rex}05$(u32le $val)"
                        current_address=$((current_address + 5 + ${#rex}/2))
                        ;;
                    sub)
                        text_hex+="${rex}2d$(u32le $val)"
                        current_address=$((current_address + 5 + ${#rex}/2))
                        ;;
                    or)
                        text_hex+="${rex}0d$(u32le $val)"
                        current_address=$((current_address + 5 + ${#rex}/2))
                        ;;
                    and)
                        text_hex+="${rex}25$(u32le $val)"
                        current_address=$((current_address + 5 + ${#rex}/2))
                        ;;
                    cmp)
                        text_hex+="${rex}3d$(u32le $val)"
                        current_address=$((current_address + 5 + ${#rex}/2))
                        ;;
                    esac
                else
                    rex=$(get_rex_for_reg "$reg")
                    op_ext=0
                    case "$op" in
                    add) op_ext=0 ;;
                    sub) op_ext=5 ;;
                    cmp) op_ext=7 ;;
                    or) op_ext=1 ;;
                    and) op_ext=4 ;;
                    esac
                    # Check if imm8 is sufficient
                    if (( val >= -128 && val <= 127 )); then
                        mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
                        text_hex+="${rex}83$(printf "%02x%02x" "$mod_rm" $((val & 0xff)))"
                        current_address=$((current_address + 3 + ${#rex}/2))
                    else
                        mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
                        text_hex+="${rex}81$(printf "%02x" "$mod_rm")"$(u32le $val)
                        current_address=$((current_address + 6 + ${#rex}/2))
                    fi
                fi
            fi
        elif [[ "$line" =~ ^(je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jo|jno|js|jns|jmp|loop|loope|loopne)[[:space:]]+(.*)$ ]]; then
            local op="${BASH_REMATCH[1]}"
            local lbl="${BASH_REMATCH[2]}"
            local jmp_reg_num=$(get_reg_num "$lbl")
            if (( jmp_reg_num >= 0 )); then
                if [[ "$op" == "jmp" ]]; then
                    local jmp_modrm=$((0xc0 | (4 << 3) | jmp_reg_num))
                    text_hex+=$(printf "ff%02x" $jmp_modrm)
                    current_address=$((current_address + 2))
                elif [[ "$op" == "call" ]]; then
                    local call_modrm=$((0xc0 | (2 << 3) | jmp_reg_num))
                    text_hex+=$(printf "ff%02x" $call_modrm)
                    current_address=$((current_address + 2))
                else
                    error_msg "conditional jump to register not supported"
                fi
            elif [[ -n "${externals[$lbl]:-}" ]]; then
                case "$op" in
                    jmp)
                        text_hex+="e900000000"
                        relocations+=("$((current_address + 1)):${lbl}:2:-4")
                        current_address=$((current_address + 5))
                        ;;
                    je)  text_hex+="0f8400000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jne) text_hex+="0f8500000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jg)  text_hex+="0f8f00000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jl)  text_hex+="0f8c00000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jge) text_hex+="0f8d00000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jle) text_hex+="0f8e00000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    ja)  text_hex+="0f8700000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jb)  text_hex+="0f8200000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jae) text_hex+="0f8300000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jbe) text_hex+="0f8600000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jo)  text_hex+="0f8000000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jno) text_hex+="0f8100000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    js)  text_hex+="0f8800000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    jns) text_hex+="0f8900000000"; relocations+=("$((current_address + 2)):${lbl}:2:-4"); current_address=$((current_address + 6)) ;;
                    *) error_msg "unsupported jump for extern: $op" ;;
                esac
            else
                if [[ "$op" == "jmp" ]]; then
                    local target=${labels[$lbl]}
                    local offset=$((target - (current_address + 5)))
                    text_hex+="e9$(u32le $offset)"
                    current_address=$((current_address + 5))
                elif [[ "$op" == "loop" || "$op" == "loope" || "$op" == "loopne" ]]; then
                    assemble_short_jump "$op" "$lbl"
                else
                    local target=${labels[$lbl]}
                    local offset=$((target - (current_address + 6)))
                    local cc=0
                    case "$op" in
                        je) cc=$((0x84)) ;; jne) cc=$((0x85)) ;; jg) cc=$((0x8f)) ;; jl) cc=$((0x8c)) ;;
                        jge) cc=$((0x8d)) ;; jle) cc=$((0x8e)) ;; ja) cc=$((0x87)) ;; jb) cc=$((0x82)) ;;
                        jae) cc=$((0x83)) ;; jbe) cc=$((0x86)) ;; jo) cc=$((0x80)) ;; jno) cc=$((0x81)) ;;
                        js) cc=$((0x88)) ;; jns) cc=$((0x89)) ;;
                    esac
                    text_hex+=$(printf "0f%02x" $cc)$(u32le $offset)
                    current_address=$((current_address + 6))
                fi
            fi
        elif [[ "$line" =~ $unary_mem_pattern ]]; then
            local uop="${BASH_REMATCH[1]}"
            local umem_content="${BASH_REMATCH[2]}"
            local umem_op="[$umem_content]"
            if [[ "$uop" == "inc" || "$uop" == "dec" ]]; then
                local uext=0
                [[ "$uop" == "dec" ]] && uext=1
                local uhex=$(assemble_mem_operand "$umem_op" "$uext" "48ff")
                text_hex+=$uhex
                current_address=$((current_address + ${#uhex}/2))
            else
                local uext=2
                [[ "$uop" == "neg" ]] && uext=3
                local uhex=$(assemble_mem_operand "$umem_op" "$uext" "48f7")
                text_hex+=$uhex
                current_address=$((current_address + ${#uhex}/2))
            fi
        
        elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+([er][a-z]{2})$ ]]; then
            op="${BASH_REMATCH[1]}"
            reg="${BASH_REMATCH[2]}"
            local rex=$(get_rex_for_reg "$reg")
            op_ext=0
            if [[ "$op" == "inc" ]]; then
                mod_rm=$((0xc0 + regs[$reg]))
                text_hex+="${rex}ff$(printf "%02x" $mod_rm)"
            elif [[ "$op" == "dec" ]]; then
                mod_rm=$((0xc8 + regs[$reg]))
                text_hex+="${rex}ff$(printf "%02x" $mod_rm)"
            elif [[ "$op" == "neg" ]]; then
                op_ext=3
                mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
                text_hex+="${rex}f7$(printf "%02x" $mod_rm)"
            elif [[ "$op" == "not" ]]; then
                op_ext=2
                mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
                text_hex+="${rex}f7$(printf "%02x" $mod_rm)"
            fi
            current_address=$((current_address + 2 + ${#rex}/2))

        elif [[ "$line" =~ ^call[[:space:]]+([er][a-z]{2})$ ]]; then
            local call_reg="${BASH_REMATCH[1]}"
            if [[ -z "${regs[$call_reg]:-}" ]]; then
                error_msg "invalid register '$call_reg' in call"
            fi
            local call_modrm=$((0xc0 | (2 << 3) | regs[$call_reg]))
            text_hex+=$(printf "ff%02x" $call_modrm)
            current_address=$((current_address + 2))
        elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
            lbl="${BASH_REMATCH[1]}"
            text_hex+="e800000000"
            relocations+=("$((current_address + 1)):${lbl}:2:-4")
            current_address=$((current_address + 5))
        elif [[ "$line" =~ $mul_mem_pattern ]]; then
            local xop="${BASH_REMATCH[1]}"
            local xmem_content="${BASH_REMATCH[2]}"
            local xmem_op="[$xmem_content]"
            local xext=0
            case "$xop" in
            mul) xext=4 ;;
            div) xext=6 ;;
            idiv) xext=7 ;;
            esac
            local xhex=$(assemble_mem_operand "$xmem_op" "$xext" "48f7")
            text_hex+=$xhex
            current_address=$((current_address + ${#xhex}/2))
        
        elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+([er][a-z]{2})$ ]]; then
            op="${BASH_REMATCH[1]}"
            reg="${BASH_REMATCH[2]}"
            local rex=$(get_rex_for_reg "$reg")
            op_ext=0
            case "$op" in
            mul) op_ext=4 ;;
            div) op_ext=6 ;;
            idiv) op_ext=7 ;;
            esac
            mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
            text_hex+="${rex}f7$(printf "%02x" $mod_rm)"
            current_address=$((current_address + 2 + ${#rex}/2))
        elif [[ "$line" =~ $imul_mem_pattern ]]; then
            local ireg="${BASH_REMATCH[1]}"
            local imem_content="${BASH_REMATCH[2]}"
            local imem_op="[$imem_content]"
            local rex=$(get_rex_for_reg "$ireg")
            local ihex=$(assemble_mem_operand "$imem_op" "${regs[$ireg]}" "${rex}0faf")
            text_hex+=$ihex
            current_address=$((current_address + ${#ihex}/2))
        
        elif [[ "$line" =~ $imul3_pattern ]]; then
            local i3dst="${BASH_REMATCH[1]}"
            local i3src="${BASH_REMATCH[2]}"
            local i3imm="${BASH_REMATCH[3]}"
            local i3val=0
            if [[ "$i3imm" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                i3val=$((16#${BASH_REMATCH[1]}))
            elif [[ "$i3imm" =~ ^-?[0-9]+$ ]]; then
                i3val=$((i3imm))
            else
                error_msg "invalid immediate '$i3imm' in imul"
                return 1
            fi
            local rex=$(get_rex_for_reg "$i3dst")
            if [[ "$i3src" =~ ^[er][a-z]{2}$ ]]; then
                if (( i3val >= -128 && i3val <= 127 )); then
                    local i3mod=$((0xc0 | (regs[$i3dst] << 3) | regs[$i3src]))
                    text_hex+="${rex}6b$(printf "%02x%02x" $i3mod $((i3val & 0xff)))"
                    current_address=$((current_address + 3 + ${#rex}/2))
                else
                    local i3mod=$((0xc0 | (regs[$i3dst] << 3) | regs[$i3src]))
                    text_hex+="${rex}69$(printf "%02x" $i3mod)"$(u32le $i3val)
                    current_address=$((current_address + 6 + ${#rex}/2))
                fi
            else
                local i3opcode="69"
                if (( i3val >= -128 && i3val <= 127 )); then
                    i3opcode="6b"
                fi
                local i3hex=$(assemble_mem_operand "$i3src" "${regs[$i3dst]}" "${rex}${i3opcode}")
                text_hex+=$i3hex
                current_address=$((current_address + ${#i3hex}/2))
                if [[ "$i3opcode" == "6b" ]]; then
                    text_hex+=$(printf "%02x" $((i3val & 0xff)))
                    current_address=$((current_address + 1))
                else
                    text_hex+=$(u32le $i3val)
                    current_address=$((current_address + 4))
                fi
            fi
        
        elif [[ "$line" =~ ^imul[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
            reg1="${BASH_REMATCH[1]}"
            reg2="${BASH_REMATCH[2]}"
            local rex=$(get_rex_for_reg "$reg1")
            mod_rm=$((0xc0 | (regs[$reg1] << 3) | regs[$reg2]))
            text_hex+="${rex}0faf$(printf "%02x" $mod_rm)"
            current_address=$((current_address + 3 + ${#rex}/2))
        elif [[ "$line" =~ ^lea[[:space:]]+([er][a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
            reg="${BASH_REMATCH[1]}"
            lbl="${BASH_REMATCH[2]}"
            local l_lbl_num=$(get_reg_num "$lbl")
            if (( l_lbl_num >= 0 )); then
                # It's a register, use register form
                local lmem_op="[$lbl]"
                local lhex=$(assemble_mem_operand "$lmem_op" "${regs[$reg]}" "488d")
                text_hex+=$lhex
                current_address=$((current_address + ${#lhex}/2))
            else
                mod_rm=$(((regs[$reg] << 3) | 5))
                text_hex+=$(printf "488d%02x" $mod_rm)
                relocations+=("$((current_address + 3)):${lbl}:2:-4")
                text_hex+="00000000"
                current_address=$((current_address + 7))
            fi
        elif [[ "$line" =~ ^lea[[:space:]]+([er][a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
            local lr_reg="${BASH_REMATCH[1]}"
            local lr_lbl="${BASH_REMATCH[2]}"
            local lr_lbl_num=$(get_reg_num "$lr_lbl")
            if (( lr_lbl_num >= 0 )); then
                # It'"'"'s a register name, use register form via lea_mem_pattern
                local lmem_op="[$lr_lbl]"
                local lhex=$(assemble_mem_operand "$lmem_op" "${regs[$lr_reg]}" "488d")
                text_hex+=$lhex
                current_address=$((current_address + ${#lhex}/2))
            else
                local mod_rm=$(((regs[$lr_reg] << 3) | 5))
                text_hex+=$(printf "488d%02x" $mod_rm)
                relocations+=("$((current_address + 3)):${lr_lbl}:2:-4")
                text_hex+="00000000"
                current_address=$((current_address + 7))
            fi
        
                elif [[ "$line" =~ $lea_mem_pattern ]]; then
            local lreg="${BASH_REMATCH[1]}"
            local lmem_content="${BASH_REMATCH[2]}"
            local lmem_op="[$lmem_content]"
            local lhex=$(assemble_mem_operand "$lmem_op" "${regs[$lreg]}" "488d")
            text_hex+=$lhex
            current_address=$((current_address + ${#lhex}/2))
        elif [[ "$line" =~ $shift_mem_pattern ]]; then
            local s_op="${BASH_REMATCH[1]}"
            local s_mem_content="${BASH_REMATCH[2]}"
            local s_val="${BASH_REMATCH[3]}"
            local s_ext=0
            case "$s_op" in
                shl) s_ext=4 ;;
                shr) s_ext=5 ;;
                sar) s_ext=7 ;;
            esac
            local s_mem_op="[$s_mem_content]"
            local s_hex=$(assemble_mem_operand "$s_mem_op" "$s_ext" "48c1")
            text_hex+=$s_hex
            current_address=$((current_address + ${#s_hex}/2))
            text_hex+=$(printf "%02x" $((s_val & 0xff)))
            current_address=$((current_address + 1))
        
        elif [[ "$line" =~ ^(shl|shr|sar)[[:space:]]+([er][a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
            op="${BASH_REMATCH[1]}"
            reg="${BASH_REMATCH[2]}"
            val="${BASH_REMATCH[3]}"
            local rex=$(get_rex_for_reg "$reg")
            op_ext=0
            if [[ "$op" == "shl" ]]; then
                op_ext=4
            elif [[ "$op" == "shr" ]]; then
                op_ext=5
            elif [[ "$op" == "sar" ]]; then
                op_ext=7
            fi
            # Use c1 for imm8 shifts, d3 for variable shift by cl
            mod_rm=$((0xc0 | (op_ext << 3) | regs[$reg]))
            text_hex+="${rex}c1$(printf "%02x%02x" $mod_rm $val)"
            current_address=$((current_address + 3 + ${#rex}/2))
        elif [[ "$line" =~ ^test[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
            reg1="${BASH_REMATCH[1]}"
            reg2="${BASH_REMATCH[2]}"
            local rex=$(get_rex_for_reg "$reg1")
            mod_rm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
            text_hex+="${rex}85$(printf "%02x" $mod_rm)"
            current_address=$((current_address + 2 + ${#rex}/2))
        elif [[ "$line" =~ ^test[[:space:]]+([er][a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
            reg="${BASH_REMATCH[1]}"
            arg="${BASH_REMATCH[2]}"
            if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                val=$((16#${BASH_REMATCH[1]}))
            else
                val=$((arg))
            fi
            local rex=$(get_rex_for_reg "$reg")
            mod_rm=$((0xc0 | regs[$reg]))
            text_hex+="${rex}f7$(printf "%02x" "$mod_rm")"$(u32le "$val")
            current_address=$((current_address + 6 + ${#rex}/2))
        elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|dil|sil|bpl|spl|[er][a-z]{2})$ ]]; then
            cond="${BASH_REMATCH[1]}"
            dst="${BASH_REMATCH[2]}"
            dst_reg=$(get_reg_num "$dst")
            if (( dst_reg < 0 )); then
                error_msg "at line $line_number: invalid destination register '$dst' in '$line'"
            fi
            mod_rm=$((0xc0 | dst_reg))
            # setcc always operates on byte reg. spl/bpl/sil/dil need REX 40.
            local rex=""
            case "$dst" in
                spl|bpl|sil|dil) rex="40" ;;
            esac
            
            case "$cond" in
            e|z) text_hex+="${rex}0f94$(printf "%02x" $mod_rm)" ;;
            ne|nz) text_hex+="${rex}0f95$(printf "%02x" $mod_rm)";;
            a) text_hex+="${rex}0f97$(printf "%02x" $mod_rm)";;
            ae) text_hex+="${rex}0f93$(printf "%02x" $mod_rm)";;
            b) text_hex+="${rex}0f92$(printf "%02x" $mod_rm)";;
            be) text_hex+="${rex}0f96$(printf "%02x" $mod_rm)";;
            g) text_hex+="${rex}0f9f$(printf "%02x" $mod_rm)";;
            ge) text_hex+="${rex}0f9d$(printf "%02x" $mod_rm)";;
            l) text_hex+="${rex}0f9c$(printf "%02x" $mod_rm)";;
            le) text_hex+="${rex}0f9e$(printf "%02x" $mod_rm)";;
            o) text_hex+="${rex}0f90$(printf "%02x" $mod_rm)";;
            no) text_hex+="${rex}0f91$(printf "%02x" $mod_rm)";;
            s) text_hex+="${rex}0f98$(printf "%02x" $mod_rm)";;
            ns) text_hex+="${rex}0f99$(printf "%02x" $mod_rm)";;
            esac
            current_address=$((current_address + 3 + ${#rex}/2))
        elif [[ "$line" =~ $rep_pattern ]]; then
            local rep_instr="${BASH_REMATCH[1]}"
            text_hex+="f3"
            current_address=$((current_address + 1))
            case "$rep_instr" in
                movsb) text_hex+="a4"; current_address=$((current_address + 1)) ;;
                movsw) text_hex+="66a5"; current_address=$((current_address + 2)) ;;
                movsl) text_hex+="a5"; current_address=$((current_address + 1)) ;;
                movsq) text_hex+="48a5"; current_address=$((current_address + 2)) ;;
                stosb) text_hex+="aa"; current_address=$((current_address + 1)) ;;
                stosw) text_hex+="66ab"; current_address=$((current_address + 2)) ;;
                stosl) text_hex+="ab"; current_address=$((current_address + 1)) ;;
                stosq) text_hex+="48ab"; current_address=$((current_address + 2)) ;;
                lodsb) text_hex+="ac"; current_address=$((current_address + 1)) ;;
                lodsw) text_hex+="66ad"; current_address=$((current_address + 2)) ;;
                lodsl) text_hex+="ad"; current_address=$((current_address + 1)) ;;
                lodsq) text_hex+="48ad"; current_address=$((current_address + 2)) ;;
                scasb) text_hex+="ae"; current_address=$((current_address + 1)) ;;
                scasw) text_hex+="66af"; current_address=$((current_address + 2)) ;;
                scasl) text_hex+="af"; current_address=$((current_address + 1)) ;;
                scasq) text_hex+="48af"; current_address=$((current_address + 2)) ;;
                cmpsb) text_hex+="a6"; current_address=$((current_address + 1)) ;;
                cmpsw) text_hex+="66a7"; current_address=$((current_address + 2)) ;;
                cmpsl) text_hex+="a7"; current_address=$((current_address + 1)) ;;
                cmpsq) text_hex+="48a7"; current_address=$((current_address + 2)) ;;
            esac

        elif [[ "$line" =~ $shift_cl_pattern ]]; then
            local scl_op="${BASH_REMATCH[1]}"
            local scl_reg="${BASH_REMATCH[2]}"
            local rex=$(get_rex_for_reg "$scl_reg")
            local scl_ext=0
            case "$scl_op" in
                shl) scl_ext=4 ;;
                shr) scl_ext=5 ;;
                sar) scl_ext=7 ;;
            esac
            local scl_mod_rm=$((0xc0 | (scl_ext << 3) | regs[$scl_reg]))
            text_hex+="${rex}d3$(printf "%02x" $scl_mod_rm)"
            current_address=$((current_address + 2 + ${#rex}/2))
        elif [[ "$line" =~ $setcc_mem_pattern ]]; then
            local scond="${BASH_REMATCH[1]}"
            local smem_content="${BASH_REMATCH[3]}"
            local smem_op="[$smem_content]"
            local sopcode=""
            case "$scond" in
                e|z) sopcode="0f94" ;;
                ne|nz) sopcode="0f95" ;;
                a) sopcode="0f97" ;;
                ae) sopcode="0f93" ;;
                b) sopcode="0f92" ;;
                be) sopcode="0f96" ;;
                g) sopcode="0f9f" ;;
                ge) sopcode="0f9d" ;;
                l) sopcode="0f9c" ;;
                le) sopcode="0f9e" ;;
                o) sopcode="0f90" ;;
                no) sopcode="0f91" ;;
                s) sopcode="0f98" ;;
                ns) sopcode="0f99" ;;
            esac
            local shex=$(assemble_mem_operand "$smem_op" 0 "$sopcode")
            text_hex+=$shex
            current_address=$((current_address + ${#shex}/2))
        elif [[ "$line" =~ $imul_ri_pattern ]]; then
            local ireg="${BASH_REMATCH[1]}"
            local iimm="${BASH_REMATCH[2]}"
            local ival=0
            if [[ "$iimm" =~ ^0x([0-9a-fA-F]+)$ ]]; then
                ival=$((16#${BASH_REMATCH[1]}))
            else
                ival=$((iimm))
            fi
            local rex=$(get_rex_for_reg "$ireg")
            local imod=$((0xc0 | (regs[$ireg] << 3) | regs[$ireg]))
            if (( ival >= -128 && ival <= 127 )); then
                text_hex+="${rex}6b$(printf "%02x%02x" $imod $((ival & 0xff)))"
                current_address=$((current_address + 3 + ${#rex}/2))
            else
                text_hex+="${rex}69$(printf "%02x" $imod)"$(u32le $ival)
                current_address=$((current_address + 6 + ${#rex}/2))
            fi
        elif [[ "$line" =~ ^@align[[:space:]]+([0-9]+)$ ]]; then
            local align_n="${BASH_REMATCH[1]}"
            local aligned=$(( (current_address + align_n - 1) / align_n * align_n ))
            local pad=$((aligned - current_address))
            while ((pad-- > 0)); do text_hex+="90"; done
            current_address=$aligned
        else
            error_msg "internal error assembling: $line"
            return 1
        fi
    done
    
    return 0
}
