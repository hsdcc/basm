#!/usr/bin/env bash
# Parse memory operand content between [ and ], extract base, index, scale, disp
# Output: "base|index|scale|disp|has_sib"
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
  for ((i = 0; i < ${#content}; i++)); do
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
      term="$tok" # keep the - sign embedded
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
  content="${content// /}"   # Remove spaces
  local rex_prefix="${2:-1}" # 1 = include REX.W

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

  # Determine if REX prefix is needed: W (from parameter) + B (base >= 8) + X (index >= 8)
  local needs_rex=$rex_prefix
  if [[ -n "$base" && -n "${regs[$base]:-}" ]]; then
    local base_num=${regs[$base]}
    ((base_num >= 8)) && needs_rex=1
  fi
  if [[ -n "$index" && -n "${regs[$index]:-}" ]]; then
    local index_num=${regs[$index]}
    ((index_num >= 8)) && needs_rex=1
  fi

  local size=0
  [[ "$needs_rex" == "1" ]] && size=$((size + 1)) # REX byte
  size=$((size + 1))                              # opcode
  size=$((size + 1))                              # ModRM

  # SIB byte: needed when has_sib is set, OR when base is rsp/r12/esp (always use rm=4)
  local needs_sib=0
  [[ "$has_sib" == "1" ]] && needs_sib=1
  if [[ "$base" == "rsp" || "$base" == "esp" || "$base" == "r12" ]]; then
    needs_sib=1
  fi
  [[ "$needs_sib" == "1" ]] && size=$((size + 1))

  # Displacement
  if [[ -z "$base" && "$has_sib" == "1" ]]; then
    # index*scale+disp (no base): always need disp32
    size=$((size + 4))
  elif [[ "$base" == "rbp" || "$base" == "ebp" || "$base" == "r13" ]]; then
    if [[ -z "$index" && "$disp" == "0" ]]; then
      # disp=0 with rbp and no index: need mod=01, disp8=00 to avoid RIP-relative
      size=$((size + 1))
    elif ((disp >= -128 && disp <= 127)); then
      size=$((size + 1))
    else
      size=$((size + 4))
    fi
  elif [[ "$needs_sib" == "1" ]]; then
    if [[ "$disp" == "0" ]]; then
      : # mod=00, no disp (SIB has index=4)
    elif ((disp >= -128 && disp <= 127)); then
      size=$((size + 1))
    else
      size=$((size + 4))
    fi
  else
    if [[ "$disp" == "0" ]]; then
      : # mod=00, no disp
    elif ((disp >= -128 && disp <= 127)); then
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
    local index_num=4 # "no index"
    if [[ -n "$index" ]]; then
      index_num=${regs[$index]}
      if ((index_num == 4)); then
        error_msg "rsp/r12 cannot be used as index register"
        return 1
      fi
    fi

    if [[ -n "$base" ]]; then
      local base_num=${regs[$base]}
      if ((disp_val == 0)); then
        if [[ "$base" == "rbp" || "$base" == "ebp" || "$base" == "r13" ]]; then
          mod=1
          disp_hex="00"
        else
          mod=0
        fi
      elif ((disp_val >= -128 && disp_val <= 127)); then
        mod=1
        disp_hex=$(printf "%02x" $((disp_val & 0xff)))
      else
        mod=2
        disp_hex=$(u32le "$disp_val")
      fi
      rm=4 # SIB follows
      # SIB byte: scale|index|base, mask to 3 bits
      local sib_val=$((scale_bits << 6 | (index_num & 7) << 3 | (base_num & 7)))
      sib_byte=$(printf "%02x" $sib_val)
    else
      # No base: mod=00, rm=4, SIB base=5 (requires disp32)
      mod=0
      rm=4
      local sib_val=$((scale_bits << 6 | (index_num & 7) << 3 | 5))
      sib_byte=$(printf "%02x" $sib_val)
      if [[ "$disp_val" == "0" ]]; then
        disp_hex="00000000" # still need disp32 for [index*scale]
      elif ((disp_val >= -128 && disp_val <= 127)); then
        disp_hex=$(u32le "$disp_val")
      else
        disp_hex=$(u32le "$disp_val")
      fi
    fi
  else
    # Simple [base+disp] form, no SIB
    [[ -z "$base" ]] && {
      error_msg "empty memory operand"
      return 1
    }
    local base_num=${regs[$base]}

    if ((disp_val == 0)); then
      if [[ "$base" == "rbp" || "$base" == "ebp" || "$base" == "r13" ]]; then
        mod=1
        disp_hex="00"
      else
        mod=0
      fi
    elif ((disp_val >= -128 && disp_val <= 127)); then
      mod=1
      disp_hex=$(printf "%02x" $((disp_val & 0xff)))
    else
      mod=2
      disp_hex=$(u32le "$disp_val")
    fi

    if [[ "$base" == "rsp" || "$base" == "esp" || "$base" == "r12" ]]; then
      rm=4
      sib_byte="24" # scale=00, index=4 (none), base=rsp(4)
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
  local rex
  if [[ "$dst" =~ ^\[.*\]$ ]]; then
    rex=$(get_rex_for_reg "$src")
  else
    rex=$(get_rex_for_reg "$dst")
  fi
  local opcode_reg_mem
  local opcode_mem_reg
  case "$op" in
    add)
      opcode_reg_mem="${rex}03"
      opcode_mem_reg="${rex}01"
      ;;
    sub)
      opcode_reg_mem="${rex}2b"
      opcode_mem_reg="${rex}29"
      ;;
    and)
      opcode_reg_mem="${rex}23"
      opcode_mem_reg="${rex}21"
      ;;
    or)
      opcode_reg_mem="${rex}0b"
      opcode_mem_reg="${rex}09"
      ;;
    cmp)
      opcode_reg_mem="${rex}3b"
      opcode_mem_reg="${rex}39"
      ;;
    *)
      echo "unsupported arith op" >&2
      return 1
      ;;
  esac
  if [[ "$dst" =~ ^\[.*\]$ ]]; then
    hex_code=$(assemble_mem_operand "$dst" "${regs[$src]}" "$opcode_mem_reg")
    text_hex+=$hex_code
    current_address=$((current_address + ${#hex_code} / 2))
  elif [[ "$src" =~ ^\[.*\]$ ]]; then
    hex_code=$(assemble_mem_operand "$src" "${regs[$dst]}" "$opcode_reg_mem")
    text_hex+=$hex_code
    current_address=$((current_address + ${#hex_code} / 2))
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
    *)
      echo "unsupported jump/loop op" >&2
      return 1
      ;;
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
