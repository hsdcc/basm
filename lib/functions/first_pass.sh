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
    # Strip size keywords before mem operands, encoding size as @marker
    if [[ "$line" =~ (byte|word|dword|qword)[[:space:]]+\[ ]]; then
      local sz_kw="${BASH_REMATCH[1]}"
      line="${line//$sz_kw [/[}"
      line="@$sz_kw $line"
    fi
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
        IFS=',' read -ra ext_syms <<<"$ext_list"
        for ext_sym in "${ext_syms[@]}"; do
          ext_sym=$(trim_string "$ext_sym")
          ext_sym="${ext_sym%%:*}"
          [[ -n "$ext_sym" ]] && externals["$ext_sym"]=1
        done
        continue
        ;;
    esac
    if [[ "$in_section" == "data" ]]; then
      if [[ "$line" =~ $align_pattern ]]; then
        local align_type="${BASH_REMATCH[1]}"
        local align_n="${BASH_REMATCH[2]}"
        [[ "$align_type" == "p2align" ]] && align_n=$((1 << align_n))
        ((align_n <= 1)) && continue
        local cur_size=$((${#data_bytes} / 2))
        local aligned=$(( (cur_size + align_n - 1) / align_n * align_n ))
        local pad=$((aligned - cur_size))
        while ((pad-- > 0)); do data_bytes+="00"; done
        continue
      fi
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
      if [[ "$line" =~ $align_pattern ]]; then
        local align_type="${BASH_REMATCH[1]}"
        local align_n="${BASH_REMATCH[2]}"
        [[ "$align_type" == "p2align" ]] && align_n=$((1 << align_n))
        ((align_n <= 1)) && continue
        local cur_size=$((${#rodata_bytes} / 2))
        local aligned=$(( (cur_size + align_n - 1) / align_n * align_n ))
        local pad=$((aligned - cur_size))
        while ((pad-- > 0)); do rodata_bytes+="00"; done
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
      if [[ "$line" =~ $resb_pattern ]]; then
        name="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        declare -gA bss_label_off
        bss_label_off["$name"]=$((${#bss_bytes} / 2))
        bss_bytes_len=$((bss_bytes_len + val))
        bss_bytes+=$(generate_zeros $val)
        continue
      fi
      if [[ "$line" =~ $resw_pattern ]]; then
        name="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        declare -gA bss_label_off
        bss_label_off["$name"]=$((${#bss_bytes} / 2))
        total=$((val * 2))
        bss_bytes_len=$((bss_bytes_len + total))
        bss_bytes+=$(generate_zeros $total)
        continue
      fi
      if [[ "$line" =~ $resd_pattern ]]; then
        name="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        declare -gA bss_label_off
        bss_label_off["$name"]=$((${#bss_bytes} / 2))
        total=$((val * 4))
        bss_bytes_len=$((bss_bytes_len + total))
        bss_bytes+=$(generate_zeros $total)
        continue
      fi
      if [[ "$line" =~ $resq_pattern ]]; then
        name="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        declare -gA bss_label_off
        bss_label_off["$name"]=$((${#bss_bytes} / 2))
        total=$((val * 8))
        bss_bytes_len=$((bss_bytes_len + total))
        bss_bytes+=$(generate_zeros $total)
        continue
      fi
      error_msg "at line $line_number: unsupported bss line format: '$line'"
      return 1
    elif [[ "$in_section" == "text" ]]; then
      # Handle alignment directives
      if [[ "$line" =~ $align_pattern ]]; then
        local align_type="${BASH_REMATCH[1]}"
        local align_n="${BASH_REMATCH[2]}"
        [[ "$align_type" == "p2align" ]] && align_n=$((1 << align_n))
        ((align_n <= 1)) && continue
        local aligned=$(( (text_bytes_len + align_n - 1) / align_n * align_n ))
        text_bytes_len=$aligned
        text_ins+=("@align $align_n")
        continue
      fi
      # Handle times directive
      if [[ "$line" =~ ^times[[:space:]]+([0-9]+)[[:space:]]+(.*)$ ]]; then
        local tcount="${BASH_REMATCH[1]}"
        local tinstr="${BASH_REMATCH[2]}"
        for ((ti = 0; ti < tcount; ti++)); do
          line="$tinstr"
          # Process the repeated instruction inline
          if [[ "$line" =~ ^([.a-zA-Z0-9_]+):$ ]]; then
            lbl="${BASH_REMATCH[1]}"
            labels["$lbl"]="$text_bytes_len"
            text_ins+=("$tinstr")
            # fall through to size calculation below
          fi
          # Handle the instruction
          text_ins+=("$tinstr")
          first_pass_ins_size "$tinstr" || return 1
        done
        continue
      fi
      if [[ "$line" =~ ^([.a-zA-Z0-9_]+):$ ]]; then
        lbl="${BASH_REMATCH[1]}"
        labels["$lbl"]="$text_bytes_len"
        continue
      fi
      text_ins+=("$line")
      first_pass_ins_size "$line" || return 1
    else
      error_msg "at line $line_number: instruction outside of section: '$line'"
      return 1
    fi
  done
    return 0
}

# Calculate size of one instruction line (used by first_pass)
first_pass_ins_size() {
  local line="$1"
  # Strip @size_kw marker if present (from first_pass stripping)
  detected_size_kw=""
  if [[ "$line" =~ ^@(byte|word|dword|qword)[[:space:]]+(.*)$ ]]; then
    detected_size_kw="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  fi

  if [[ "$line" =~ ^mov[[:space:]]+([er][a-z]{2}|[absd][ilh]|spl|bpl|sil|dil),[[:space:]]+([er][a-z]{2}|[absd][ilh]|spl|bpl|sil|dil)$ ]]; then
    local mv_reg1="${BASH_REMATCH[1]}"
    local mv_reg2="${BASH_REMATCH[2]}"
    if (($(get_reg_num "$mv_reg1") >= 0 && $(get_reg_num "$mv_reg2") >= 0)); then
      local mv_rex=$(get_rex_for_reg "$mv_reg1")
      text_bytes_len=$((text_bytes_len + 2 + ${#mv_rex} / 2))
    else
      error_msg "invalid register in mov '$line'"
      return 1
    fi

  elif [[ "$line" =~ ^mov[[:space:]]+\[([^]]+)\],[[:space:]]+([er][a-z]{2}|[absd][ilh]|spl|bpl|sil|dil)$ ]]; then
    local mem="${BASH_REMATCH[1]}"
    local ms_src="${BASH_REMATCH[2]}"
    local ms_size=$(calc_mem_operand_size "$mem")
    local ms_rex=$(get_rex_for_reg "$ms_src")
    [[ -z "$ms_rex" ]] && ms_size=$((ms_size - 1))
    text_bytes_len=$((text_bytes_len + ms_size))

  elif [[ "$line" =~ ^mov[[:space:]]+([er][a-z]{2}|[absd][ilh]|spl|bpl|sil|dil),[[:space:]]+\[([^]]+)\]$ ]]; then
    local mem="${BASH_REMATCH[2]}"
    local ml_dst="${BASH_REMATCH[1]}"
    local ml_size=$(calc_mem_operand_size "$mem")
    local ml_rex=$(get_rex_for_reg "$ml_dst")
    [[ -z "$ml_rex" ]] && ml_size=$((ml_size - 1))
    text_bytes_len=$((text_bytes_len + ml_size))

  elif [[ "$line" =~ $cmov_pattern ]]; then
    text_bytes_len=$((text_bytes_len + 4))

  elif [[ "$line" =~ ^mov[[:space:]]+([er][a-z]{2}|[absd][ilh]|spl|bpl|sil|dil),[[:space:]]+(.*)$ ]]; then
    calculate_mov_size

  elif [[ "$line" =~ ^(syscall|nop|ret|leave|cqo|cdqe)$ ]]; then
    calculate_simple_instr_size
  elif [[ "$line" =~ $string_op_pattern ]]; then
    case "$line" in
      movsb | movsl | stosb | stosl | lodsb | lodsl | scasb | scasl | cmpsb | cmpsl | cld | std) text_bytes_len=$((text_bytes_len + 1)) ;;
      movsw | movsq | stosw | stosq | lodsw | lodsq | scasw | scasq | cmpsw | cmpsq) text_bytes_len=$((text_bytes_len + 2)) ;;
    esac

  elif [[ "$line" =~ ^xor[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
    local xr_reg="${BASH_REMATCH[1]}"
    local xr_rex=$(get_rex_for_reg "$xr_reg")
    text_bytes_len=$((text_bytes_len + 2 + ${#xr_rex} / 2))

  elif [[ "$line" =~ ^(push|pop)[[:space:]]+([er][a-z]{2})$ ]]; then
    text_bytes_len=$((text_bytes_len + 1))

  elif [[ "$line" =~ $push_imm_pattern ]]; then
    arg="${BASH_REMATCH[1]}"
    if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
      val=$((16#${BASH_REMATCH[1]}))
    else
      val=$((arg))
    fi
    if ((val >= -128 && val <= 127)); then
      text_bytes_len=$((text_bytes_len + 2))
    else
      text_bytes_len=$((text_bytes_len + 5))
    fi
  elif [[ "$line" =~ $push_equsym_pattern ]]; then
    sym="${BASH_REMATCH[1]}"
    if [[ -n "${equs[$sym]:-}" ]]; then
      val=${equs[$sym]}
      if ((val >= -128 && val <= 127)); then
        text_bytes_len=$((text_bytes_len + 2))
      else
        text_bytes_len=$((text_bytes_len + 5))
      fi
    else
      text_bytes_len=$((text_bytes_len + 5))
    fi
  elif [[ "$line" =~ $push_mem_pattern ]]; then
    local pmem="${BASH_REMATCH[2]}"
    local psize=$(calc_mem_operand_size "$pmem")
    # push [mem] uses 1-byte opcode (ff), calc assumes REX; subtract 1
    text_bytes_len=$((text_bytes_len + psize - 1))
  elif [[ "$line" =~ $pop_mem_pattern ]]; then
    local pmem="${BASH_REMATCH[2]}"
    local psize=$(calc_mem_operand_size "$pmem")
    text_bytes_len=$((text_bytes_len + psize))

  elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
    local ar_reg="${BASH_REMATCH[2]}"
    local ar_rex=$(get_rex_for_reg "$ar_reg")
    text_bytes_len=$((text_bytes_len + 2 + ${#ar_rex} / 2))

  elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+([er][a-z]{2}),[[:space:]]*(.*)$ ]]; then
    calculate_arith_ri_size

  elif [[ "$line" =~ $arith_mem_imm_pattern ]]; then
    local amem="${BASH_REMATCH[2]}"
    local amsize=$(calc_mem_operand_size "$amem")
    local amimm="${BASH_REMATCH[3]}"
    local amval=0
    if [[ "$amimm" =~ ^0x([0-9a-fA-F]+)$ ]]; then
      amval=$((16#${BASH_REMATCH[1]}))
    elif [[ "$amimm" =~ ^-?[0-9]+$ ]]; then
      amval=$((amimm))
    fi
    if ((amval >= -128 && amval <= 127)); then
      text_bytes_len=$((text_bytes_len + amsize + 1))
    else
      text_bytes_len=$((text_bytes_len + amsize + 4))
    fi

  elif [[ "$line" =~ ^(je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jo|jno|js|jns|jmp)[[:space:]]+(.*)$ ]]; then
    local jlbl="${BASH_REMATCH[2]}"
    jlbl="$(trim_string "$jlbl")"
    local jreg_num=$(get_reg_num "$jlbl")
    if ((jreg_num >= 0)); then
      if [[ "${BASH_REMATCH[1]}" == "jmp" ]]; then
        text_bytes_len=$((text_bytes_len + 2))
      else
        error_msg "conditional jump to register not supported"
      fi
    elif [[ -n "${externals[$jlbl]:-}" ]]; then
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
    local un_reg="${BASH_REMATCH[2]}"
    local un_rex=$(get_rex_for_reg "$un_reg")
    text_bytes_len=$((text_bytes_len + 2 + ${#un_rex} / 2))

  elif [[ "$line" =~ $unary_mem_pattern ]]; then
    local umem="${BASH_REMATCH[2]}"
    local umsize=$(calc_mem_operand_size "$umem")
    text_bytes_len=$((text_bytes_len + umsize))

  elif [[ "$line" =~ ^call[[:space:]]+([er][a-z]{2})$ ]]; then
    text_bytes_len=$((text_bytes_len + 2))
  elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
    text_bytes_len=$((text_bytes_len + 5))

  elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+([er][a-z]{2})$ ]]; then
    local mu_reg="${BASH_REMATCH[2]}"
    local mu_rex=$(get_rex_for_reg "$mu_reg")
    text_bytes_len=$((text_bytes_len + 2 + ${#mu_rex} / 2))

  elif [[ "$line" =~ $mul_mem_pattern ]]; then
    local mmem="${BASH_REMATCH[2]}"
    local msize=$(calc_mem_operand_size "$mmem")
    text_bytes_len=$((text_bytes_len + msize))

  elif [[ "$line" =~ ^(imul)[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
    local im_reg="${BASH_REMATCH[2]}"
    local im_rex=$(get_rex_for_reg "$im_reg")
    text_bytes_len=$((text_bytes_len + 3 + ${#im_rex} / 2))

  elif [[ "$line" =~ $imul_mem_pattern ]]; then
    local imem="${BASH_REMATCH[2]}"
    local isize=$(calc_mem_operand_size "$imem")
    text_bytes_len=$((text_bytes_len + isize + 1))

  elif [[ "$line" =~ $imul3_pattern ]]; then
    local i3src="${BASH_REMATCH[2]}"
    local i3imm="${BASH_REMATCH[3]}"
    if [[ "$i3src" =~ ^[er][a-z]{2}$ ]]; then
      local i3val=0
      [[ "$i3imm" =~ ^-?[0-9]+$ ]] && i3val=$((i3imm))
      if ((i3val >= -128 && i3val <= 127)); then
        text_bytes_len=$((text_bytes_len + 4))
      else
        text_bytes_len=$((text_bytes_len + 7))
      fi
    else
      if [[ "$i3src" =~ \[([^]]+)\] ]]; then
        local emem="${BASH_REMATCH[1]}"
        local esize=$(calc_mem_operand_size "$emem")
        local eVal=0
        [[ "$i3imm" =~ ^-?[0-9]+$ ]] && eVal=$((i3imm))
        if ((eVal >= -128 && eVal <= 127)); then
          text_bytes_len=$((text_bytes_len + esize + 1))
        else
          text_bytes_len=$((text_bytes_len + esize + 4))
        fi
      fi
    fi

  elif [[ "$line" =~ ^lea[[:space:]]+([er][a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
    local l_lbl2="${BASH_REMATCH[2]}"
    local l_lbl2_num=$(get_reg_num "$l_lbl2")
    if ((l_lbl2_num >= 0)); then
      local l_size2=$(calc_mem_operand_size "$l_lbl2")
      text_bytes_len=$((text_bytes_len + l_size2))
    else
      text_bytes_len=$((text_bytes_len + 7))
    fi

  elif [[ "$line" =~ $lea_mem_pattern ]]; then
    local lea_mem="${BASH_REMATCH[2]}"
    local lea_size=$(calc_mem_operand_size "$lea_mem")
    text_bytes_len=$((text_bytes_len + lea_size))

  elif [[ "$line" =~ ^(shl|shr|sar)[[:space:]]+([er][a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
    local sh_reg="${BASH_REMATCH[2]}"
    local sh_rex=$(get_rex_for_reg "$sh_reg")
    text_bytes_len=$((text_bytes_len + 3 + ${#sh_rex} / 2))

  elif [[ "$line" =~ $shift_mem_pattern ]]; then
    local smem="${BASH_REMATCH[2]}"
    local smsize=$(calc_mem_operand_size "$smem")
    text_bytes_len=$((text_bytes_len + smsize + 1))

  elif [[ "$line" =~ ^test[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
    local tt_reg="${BASH_REMATCH[1]}"
    local tt_rex=$(get_rex_for_reg "$tt_reg")
    text_bytes_len=$((text_bytes_len + 2 + ${#tt_rex} / 2))

  elif [[ "$line" =~ ^test[[:space:]]+([er][a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
    text_bytes_len=$((text_bytes_len + 7))

  elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+([er][a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh]|dil|sil|bpl|spl)$ ]]; then
    local zx_reg="${BASH_REMATCH[2]}"
    local zx_rex=$(get_rex_for_reg "$zx_reg")
    text_bytes_len=$((text_bytes_len + 3 + ${#zx_rex} / 2))

  elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
    local zx2_reg="${BASH_REMATCH[2]}"
    local zx2_rex=$(get_rex_for_reg "$zx2_reg")
    text_bytes_len=$((text_bytes_len + 3 + ${#zx2_rex} / 2))

  elif [[ "$line" =~ ^movsxd[[:space:]]+([er][a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
    local ms_reg="${BASH_REMATCH[1]}"
    local ms_rex=$(get_rex_for_reg "$ms_reg")
    text_bytes_len=$((text_bytes_len + 2 + ${#ms_rex} / 2))

  elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|dil|sil|bpl|spl|[er][a-z]{2})$ ]]; then
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
    local sse_mem="${BASH_REMATCH[3]}"
    local sse_size
    if [[ "$sse_mne" == "comiss" || "$sse_mne" == "ucomiss" ]]; then
      sse_size=$(calc_mem_operand_size "$sse_mem" 0)
      sse_size=$((sse_size + 2)) # 2-byte opcode (0f 2f/2e), no REX prefix
    else
      sse_size=$(calc_mem_operand_size "$sse_mem")
    fi
    text_bytes_len=$((text_bytes_len + sse_size))
  elif [[ "$line" =~ $sse_mem_dst_pattern ]]; then
    local sd_mem="${BASH_REMATCH[2]}"
    local sd_size=$(calc_mem_operand_size "$sd_mem")
    text_bytes_len=$((text_bytes_len + sd_size))
  elif [[ "$line" =~ $cvtsi2s_reg_pattern ]]; then
    text_bytes_len=$((text_bytes_len + 4))
  elif [[ "$line" =~ $cvtsi2s_mem_pattern ]]; then
    local c2_mem="${BASH_REMATCH[3]}"
    local c2_size=$(calc_mem_operand_size "$c2_mem")
    text_bytes_len=$((text_bytes_len + c2_size))
  elif [[ "$line" =~ $cvtss2si_rr_pattern ]]; then
    text_bytes_len=$((text_bytes_len + 4))
  elif [[ "$line" =~ $cvtss2s_mem_pattern ]]; then
    local cs_mem="${BASH_REMATCH[3]}"
    local cs_size=$(calc_mem_operand_size "$cs_mem")
    text_bytes_len=$((text_bytes_len + cs_size))
  elif [[ "$line" =~ $cvtsd2si_pattern ]]; then
    text_bytes_len=$((text_bytes_len + 4))
  elif [[ "$line" =~ $rep_pattern ]]; then
    text_bytes_len=$((text_bytes_len + 2))
  elif [[ "$line" =~ $mov_mem_imm_pattern ]]; then
    local mmi_size_kw="$detected_size_kw"
    local mmi_mem="${BASH_REMATCH[2]}"
    local mmi_imm="${BASH_REMATCH[3]}"
    local mmi_immval=0
    [[ "$mmi_imm" =~ ^-?[0-9]+$ ]] && mmi_immval=$((mmi_imm))
    [[ "$mmi_imm" =~ ^0x([0-9a-fA-F]+)$ ]] && mmi_immval=$((16#${BASH_REMATCH[1]}))

    if [[ "$mmi_size_kw" == "byte" ]]; then
      local mmi_addrsize=$(calc_mem_operand_size "$mmi_mem" 0)
      text_bytes_len=$((text_bytes_len + mmi_addrsize + 1))
    elif [[ "$mmi_size_kw" == "word" ]]; then
      local mmi_addrsize=$(calc_mem_operand_size "$mmi_mem" 0)
      text_bytes_len=$((text_bytes_len + mmi_addrsize + 3))
    elif [[ "$mmi_size_kw" == "dword" ]]; then
      local mmi_addrsize=$(calc_mem_operand_size "$mmi_mem" 0)
      text_bytes_len=$((text_bytes_len + mmi_addrsize + 4))
    else
      local mmi_addrsize=$(calc_mem_operand_size "$mmi_mem")
      text_bytes_len=$((text_bytes_len + mmi_addrsize + 4))
    fi
  elif [[ "$line" =~ $shift_cl_pattern ]]; then
    text_bytes_len=$((text_bytes_len + 3))
  elif [[ "$line" =~ $setcc_mem_pattern ]]; then
    local scc_mem="${BASH_REMATCH[3]}"
    local scc_size=$(calc_mem_operand_size "$scc_mem")
    # setcc is 2-byte opcode (0f 9x) + modrm + [sib] + [disp]
    # calc_mem_operand_size counts REX+opcode+modrm+sib+disp, but we want just modrm+sib+disp
    # Substract REX(1) + opcode(1); add setcc 2-byte opcode
    text_bytes_len=$((text_bytes_len + scc_size + 1))
  elif [[ "$line" =~ $imul_ri_pattern ]]; then
    local iri_imm="${BASH_REMATCH[2]}"
    local iri_val=0
    [[ "$iri_imm" =~ ^-?[0-9]+$ ]] && iri_val=$((iri_imm))
    [[ "$iri_imm" =~ ^0x([0-9a-fA-F]+)$ ]] && iri_val=$((16#${BASH_REMATCH[1]}))
    if ((iri_val >= -128 && iri_val <= 127)); then
      text_bytes_len=$((text_bytes_len + 4))
    else
      text_bytes_len=$((text_bytes_len + 7))
    fi
  elif [[ "$line" =~ $movzx_word_mem_pattern ]]; then
    # movzx reg, word [mem]
    local zw_reg="${BASH_REMATCH[2]}"
    local zw_mem="${BASH_REMATCH[4]}"
    local zw_rex=$(get_rex_for_reg "$zw_reg")
    local zw_rex_flag=$([[ -n "$zw_rex" ]] && echo 1 || echo 0)
    local zw_size=$(calc_mem_operand_size "$zw_mem" $zw_rex_flag)
    text_bytes_len=$((text_bytes_len + zw_size + 1))
  elif [[ "$line" =~ $movsx_word_mem_pattern ]]; then
    # movsx reg, word [mem]
    local sw_reg="${BASH_REMATCH[2]}"
    local sw_mem="${BASH_REMATCH[4]}"
    local sw_rex=$(get_rex_for_reg "$sw_reg")
    local sw_rex_flag=$([[ -n "$sw_rex" ]] && echo 1 || echo 0)
    local sw_size=$(calc_mem_operand_size "$sw_mem" $sw_rex_flag)
    text_bytes_len=$((text_bytes_len + sw_size + 1))
  elif [[ "$line" =~ $movzx_mem_pattern ]]; then
    # movzx reg, [mem]
    local mmem="${BASH_REMATCH[4]}"
    local msize=$(calc_mem_operand_size "$mmem")
    # movzx is 3-byte opcode (48 0f b6) + modrm + [sib] + [disp]
    # calc_mem_operand_size counts REX(1) + opcode(1) + modrm + sib + disp
    # We need REX(1) + 2-byte opcode(0f b6) + modrm + sib + disp
    text_bytes_len=$((text_bytes_len + msize + 1))
  elif [[ "$line" =~ $movsx_mem_pattern ]]; then
    local mmem="${BASH_REMATCH[4]}"
    local msize=$(calc_mem_operand_size "$mmem")
    text_bytes_len=$((text_bytes_len + msize + 1))
  elif [[ "$line" =~ $movsxd_mem_pattern ]]; then
    local mmem="${BASH_REMATCH[3]}"
    local msize=$(calc_mem_operand_size "$mmem")
    # movsxd is 2-byte opcode (48 63) + modrm + [sib] + [disp]
    text_bytes_len=$((text_bytes_len + msize))
  else
    error_msg "unsupported instruction: '$line'"
    return 1
  fi
    return 0
}
