#!/usr/bin/env bash

# Helper function to trim leading and trailing whitespace from a string
trim_string() {
  local str="$1"
  # Remove leading whitespace
  str="${str#"${str%%[![:space:]]*}"}"
  # Remove trailing whitespace
  str="${str%"${str##*[![:space:]]}"}"
  echo "$str"
}

# Helper function to convert hex string to binary data
hex_to_bin() {
  local hex="$1"
  local -a bytes
  local i
  
  # Ensure even length hex string
  if (( ${#hex} % 2 != 0 )); then
    hex="0$hex"
  fi
  
  # Split hex string into byte pairs and convert to binary
  for ((i = 0; i < ${#hex}; i += 2)); do
    local byte="${hex:$i:2}"
    printf "\\x$byte"
  done
}

# Helper function to generate padding zeros
generate_zeros() {
  local count="$1"
  local i
  for ((i = 0; i < count; i++)); do
    printf "\\x00"
  done
}

# Helper function to write data at specific offset in a file
write_at_offset() {
  local src_file="$1"    # Source file containing data to write
  local dest_file="$2"   # Destination file to write to
  local offset="$3"      # Byte offset to write at
  
  # Read the source file content
  local src_content
  src_content=$(< "$src_file")
  
  # Read the destination file content
  local dest_content
  if [[ -f "$dest_file" ]]; then
    dest_content=$(< "$dest_file")
  else
    dest_content=""
  fi
  
  # Ensure destination is at least 'offset' bytes long by padding with nulls if necessary
  local current_len=${#dest_content}
  local padded_content="$dest_content"
  if (( current_len < offset )); then
    local padding_len=$((offset - current_len))
    local i
    for ((i = 0; i < padding_len; i++)); do
      padded_content+=$'\0'
    done
  fi
  
  # Calculate where to place the source content
  local prefix="${padded_content:0:offset}"
  local suffix="${padded_content:offset}"
  
  # Combine: prefix + src_content + suffix
  local result="$prefix$src_content$suffix"
  
  # Write the combined content back to the destination file
  printf '%s' "$result" > "$dest_file"
}

basm_assemble() {
  local code_str="${1:-""]}"
  local outfile="${2:-a.out}"

  # No longer loading instruction definitions from external file
  # All instruction encodings are hardcoded directly in this file

  u32le() {
    local n=$1
    printf "%02x%02x%02x%02x" $((n & 0xff)) $(((n >> 8) & 0xff)) $(((n >> 16) & 0xff)) $(((n >> 24) & 0xff))
  }
  u64le() {
    local n=$1
    local b0=$((n & 0xff))
    local b1=$(((n >> 8) & 0xff))
    local b2=$(((n >> 16) & 0xff))
    local b3=$(((n >> 24) & 0xff))
    local b4=$(((n >> 32) & 0xff))
    local b5=$(((n >> 40) & 0xff))
    local b6=$(((n >> 48) & 0xff))
    local b7=$(((n >> 56) & 0xff))
    printf "%02x%02x%02x%02x%02x%02x%02x%02x" $b0 $b1 $b2 $b3 $b4 $b5 $b6 $b7
  }

  mapfile -t lines <<<"$code_str"

  declare -A labels
  declare -A data_label_off
  declare -A equs
  declare -A regs
  regs["rax"]=0
  regs["rcx"]=1
  regs["rdx"]=2
  regs["rbx"]=3
  regs["rsp"]=4
  regs["rbp"]=5
  regs["rsi"]=6
  regs["rdi"]=7

  # Helper to get register number from any register name (al, rax, eax, etc)
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

  data_bytes=""
  text_ins=()
  text_bytes_len=0
  in_section=""

  for raw in "${lines[@]}"; do
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
      if [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]+equ[[:space:]]+\$[[:space:]]*-[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*$ ]]; then
        name="${BASH_REMATCH[1]}"
        ref="${BASH_REMATCH[2]}"
        if [[ -z "${data_label_off[$ref]:-}" ]]; then
          echo "unknown equ ref $ref" >&2
          return 1
        fi
        cur_off=$((${#data_bytes} / 2))
        val=$((cur_off - data_label_off[$ref]))
        equs["$name"]=$val
        continue
      fi

      if [[ "$line" =~ ^([a-zA-Z0-9_]+):?[[:space:]]+db[[:space:]]+\"(.*)\"([[:space:]]*,[[:space:]]*([0-9]+))?[[:space:]]*$ ]]; then
        name="${BASH_REMATCH[1]}"
        txt="${BASH_REMATCH[2]}"
        extra="${BASH_REMATCH[4]}"
        # Process escape sequences using pure bash
        txt="${txt//\\/\\\\x5c}"  # Replace \ with \\x5c
        txt="${txt//
/\\n}"      # Replace newlines with \n
        txt="${txt//\"/\\\"}"     # Replace " with \"
        hex=""
        i=0
        while [ $i -lt ${#txt} ]; do
          ch="${txt:i:1}"
          oc=$(printf "%d" "'$ch")
          hex+="$(printf "%02x" $oc)"
          i=$((i + 1))
        done
        if [ -n "$extra" ]; then
          hex+="$(printf "%02x" $extra)"
        fi
        data_label_off["$name"]=$((${#data_bytes} / 2))
        data_bytes+="$hex"
        continue
      fi

      echo "unsupported data line: $line" >&2
      return 1
    elif [[ "$in_section" == "text" ]]; then
      if [[ "$line" =~ ^([.a-zA-Z0-9_]+):$ ]]; then
        lbl="${BASH_REMATCH[1]}"
        labels["$lbl"]="$text_bytes_len"
        continue
      fi
      text_ins+=("$line")
      if [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$ ]]; then
        arg="${BASH_REMATCH[2]}"
        if [[ "$arg" =~ ^\[(r[a-z]{2})([\+\-][0-9]+)?\]$ ]]; then
          base="${BASH_REMATCH[1]}"
          disp="${BASH_REMATCH[2]:-}"
          size=4
          if [[ "$base" == "rsp" || "$base" == "r12" ]]; then
            if [[ -z "$disp" ]]; then
              size=4
            else
              val=$disp
              if (( val >= -128 && val <= 127 )); then
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
              val=$disp
              if (( val >= -128 && val <= 127 )); then
                size=4
              else
                size=7
              fi
            fi
          fi
          text_bytes_len=$((text_bytes_len + size))
        elif [[ "$arg" =~ ^\[(r[a-z]{2})([\+\-][0-9]+)?\],[[:space:]]+(r[a-z]{2})$ ]]; then
          base="${BASH_REMATCH[1]}"
          disp="${BASH_REMATCH[2]:-}"
          size=4
          if [[ "$base" == "rsp" || "$base" == "r12" ]]; then
            if [[ -z "$disp" ]]; then
              size=4
            else
              val=$disp
              if (( val >= -128 && val <= 127 )); then
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
              val=$disp
              if (( val >= -128 && val <= 127 )); then
                size=4
              else
                size=7
              fi
            fi
          fi
          text_bytes_len=$((text_bytes_len + size))
        elif [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^-?[0-9]+$ ]] || [[ "$arg" =~ ^0x[0-9a-fA-F]+$ ]] || [[ -n "${equs[$arg]:-}" ]]; then
          text_bytes_len=$((text_bytes_len + 7))
        else
          text_bytes_len=$((text_bytes_len + 10))
        fi
      elif [[ "$line" == "syscall" ]]; then
        text_bytes_len=$((text_bytes_len + 2))
      elif [[ "$line" == "nop" ]]; then
        text_bytes_len=$((text_bytes_len + 1))
elif [[ "$line" == "ret" ]]; then
  text_bytes_len=$((text_bytes_len + 1))
elif [[ "$line" == "leave" ]]; then
  text_bytes_len=$((text_bytes_len + 1))
elif [[ "$line" == "cqo" ]]; then
  text_bytes_len=$((text_bytes_len + 2))
elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^(push|pop)[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 1))
      elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]*(.*)$ ]]; then
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
      elif [[ "$line" =~ ^(j|J) ]]; then
        text_bytes_len=$((text_bytes_len + 2))
      elif [[ "$line" =~ ^loop ]]; then
        text_bytes_len=$((text_bytes_len + 2))
      elif [[ "$line" =~ ^loope ]]; then
        text_bytes_len=$((text_bytes_len + 2))
      elif [[ "$line" =~ ^loopne ]]; then
        text_bytes_len=$((text_bytes_len + 2))
elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+(r[a-z]{2})$ ]]; then
  text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
        text_bytes_len=$((text_bytes_len + 5))
      elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^(imul)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 4))
      elif [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
        text_bytes_len=$((text_bytes_len + 7))
      elif [[ "$line" =~ ^(shl|shr)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
        text_bytes_len=$((text_bytes_len + 4))
      elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
        text_bytes_len=$((text_bytes_len + 7))
      elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh])$ ]]; then
        text_bytes_len=$((text_bytes_len + 4))
      elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 4))
      elif [[ "$line" =~ ^movsxd[[:space:]]+(r[a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      else
        echo "unsupported instruction: $line" >&2
        return 1
      fi
    else
      echo "no section for: $line" >&2
      return 1
    fi
  done

  base_vaddr=0x400000
  file_text_off=0x200 # increased to avoid header overflow
  code_size=$text_bytes_len
  data_size=$((${#data_bytes} / 2))
  file_data_off=$((file_text_off + code_size))
  text_vaddr=$((base_vaddr + file_text_off))
  data_vaddr=$((base_vaddr + file_data_off))
  entry_vaddr=$text_vaddr
  if [[ -n "${labels[_start]:-}" ]]; then
    entry_vaddr=$((text_vaddr + labels[_start]))
  fi


  text_hex=""
  current_address=0
  for line in "${text_ins[@]}"; do
    if [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
      dst="${BASH_REMATCH[1]}"
      src="${BASH_REMATCH[2]}"
      modrm=$((0xc0 + regs[$src] * 8 + regs[$dst]))
      text_hex+=$(printf "4889%02x" $modrm)
      current_address=$((current_address + 3))
    elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+\[(r[a-z]{2})([\+\-][0-9]+)?\]$ ]]; then
      dst="${BASH_REMATCH[1]}"
      base="${BASH_REMATCH[2]}"
      disp="${BASH_REMATCH[3]:-}"
      mod=0
      need_sib=0
      if [[ "$base" == "rsp" || "$base" == "r12" ]]; then
        need_sib=1
      fi
      if [[ -z "$disp" ]]; then
        if [[ "$base" == "rbp" || "$base" == "r13" ]]; then
          mod=1
          disp="0"
        fi
      else
        if [[ "$disp" =~ ^[\+\-]?[0-9]+$ ]]; then
          val=$disp
          if (( val >= -128 && val <= 127 )); then
            mod=1
          else
            mod=2
          fi
        fi
      fi
      if [[ $need_sib -eq 1 ]]; then
        rm=4
      else
        rm=${regs[$base]}
      fi
      modrm=$((mod * 64 + ${regs[$dst]} * 8 + rm))
      text_hex+="488b"
      text_hex+=$(printf "%02x" $modrm)
      if [[ $need_sib -eq 1 ]]; then
        sib=$((0 * 64 + 4 * 8 + ${regs[$base]}))
        text_hex+=$(printf "%02x" $sib)
      fi
      if [[ -n "$disp" && "$disp" != "0" ]]; then
        if [[ $mod -eq 1 ]]; then
          text_hex+=$(printf "%02x" $((disp & 0xff)))
        else
          text_hex+=$(u32le $disp)
        fi
      fi
      if [[ $mod -eq 0 && ($base == "rbp" || $base == "r13") ]]; then
        text_hex+="00"
      fi
      current_address=$((current_address + 4))
    elif [[ "$line" =~ ^mov[[:space:]]+\[(r[a-z]{2})([\+\-][0-9]+)?\],[[:space:]]+(r[a-z]{2})$ ]]; then
      base="${BASH_REMATCH[1]}"
      disp="${BASH_REMATCH[2]:-}"
      dst="${BASH_REMATCH[3]}"
      mod=0
      need_sib=0
      if [[ "$base" == "rsp" || "$base" == "r12" ]]; then
        need_sib=1
      fi
      if [[ -z "$disp" ]]; then
        if [[ "$base" == "rbp" || "$base" == "r13" ]]; then
          mod=1
          disp="0"
        fi
      else
        if [[ "$disp" =~ ^[\+\-]?[0-9]+$ ]]; then
          val=$disp
          if (( val >= -128 && val <= 127 )); then
            mod=1
          else
            mod=2
          fi
        fi
      fi
      if [[ $need_sib -eq 1 ]]; then
        rm=4
      else
        rm=${regs[$base]}
      fi
      modrm=$((mod * 64 + regs[$dst] * 8 + rm))
      text_hex+="4889"
      text_hex+=$(printf "%02x" $modrm)
      if [[ $need_sib -eq 1 ]]; then
        sib=$((0 * 64 + 4 * 8 + ${regs[$base]}))
        text_hex+=$(printf "%02x" $sib)
      fi
      if [[ -n "$disp" && "$disp" != "0" ]]; then
        if [[ $mod -eq 1 ]]; then
          text_hex+=$(printf "%02x" $((disp & 0xff)))
        else
          text_hex+=$(u32le $disp)
        fi
      fi
      if [[ $mod -eq 0 && ($base == "rbp" || $base == "r13") ]]; then
        text_hex+="00"
      fi
      current_address=$((current_address + 4))
    elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$ ]]; then
      reg="${BASH_REMATCH[1]}"
      arg="${BASH_REMATCH[2]}"
      local val_is_immediate=0
      local val # Declare val as local to avoid issues
      if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
        val=$((16#${BASH_REMATCH[1]}))
        val_is_immediate=1
      elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
        val=$((arg))
        val_is_immediate=1
      elif [[ -n "${equs[$arg]:-}" ]]; then
        val=${equs[$arg]}
        val_is_immediate=1
      fi

      if [[ "$val_is_immediate" -eq 1 ]]; then
        opcode=$((0xc0 + regs[$reg]))
        text_hex+=$(printf "48c7%02x" $opcode)$(u32le $val)
        current_address=$((current_address + 7))
      else
        op=$((0xb8 + regs[$reg]))
        if [[ -n "${data_label_off[$arg]:-}" ]]; then
          addr=$((data_vaddr + data_label_off[$arg]))
        elif [[ -n "${labels[$arg]:-}" ]]; then
          addr=$((text_vaddr + labels[$arg]))
        else
          echo "unknown label $arg" >&2
          return 1
        fi
        text_hex+=$(printf "48%02x" $op)$(u64le $addr)
        current_address=$((current_address + 10))
      fi
    elif [[ "$line" == "syscall" ]]; then
      text_hex+="0f05"
      current_address=$((current_address + 2))
    elif [[ "$line" == "nop" ]]; then
      text_hex+="90"
      current_address=$((current_address + 1))
elif [[ "$line" == "ret" ]]; then
  text_hex+="c3"
  current_address=$((current_address + 1))
elif [[ "$line" == "leave" ]]; then
  text_hex+="c9"
  current_address=$((current_address + 1))
elif [[ "$line" == "cqo" ]]; then
  text_hex+="4899"
  current_address=$((current_address + 2))
elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
      reg="${BASH_REMATCH[1]}"
      modrm=$((0xc0 + regs[$reg] * 8 + regs[$reg]))
      text_hex+=$(printf "4831%02x" $modrm)
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
    elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
      op="${BASH_REMATCH[1]}"
      reg1="${BASH_REMATCH[2]}"
      reg2="${BASH_REMATCH[3]}"
      modrm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
      case "$op" in
      add) text_hex+=$(printf "4801%02x" $modrm) ;;
      sub) text_hex+=$(printf "4829%02x" $modrm) ;;
      and) text_hex+=$(printf "4821%02x" $modrm) ;;
      or) text_hex+=$(printf "4809%02x" $modrm) ;;
      cmp) text_hex+=$(printf "4839%02x" $modrm) ;;
      esac
      current_address=$((current_address + 3))
    elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]*(.*)$ ]]; then
      op="${BASH_REMATCH[1]}"
      reg="${BASH_REMATCH[2]}"
      arg="${BASH_REMATCH[3]}"

      if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
        val=$((16#${BASH_REMATCH[1]}))
      elif [[ "$arg" =~ ^[0-9]+$ ]]; then
        val=$((arg))
      else
        echo "unknown immediate $arg" >&2
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
        modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
        text_hex+=$(printf "4883%02x%02x" $modrm $val)
        current_address=$((current_address + 4))
      fi
    elif [[ "$line" =~ ^(je|jne|jg|jl|jge|jle|jmp)[[:space:]]+(.*)$ ]]; then
      op="${BASH_REMATCH[1]}"
      lbl="${BASH_REMATCH[2]}"
      if [[ -z "${labels[$lbl]:-}" ]]; then
        echo "unknown label $lbl" >&2
        return 1
      fi
      target_address=${labels[$lbl]}
      offset=$((target_address - (current_address + 2)))
      if [ $offset -lt -128 ] || [ $offset -gt 127 ]; then
        echo "short jump out of range: $offset" >&2
        return 1
      fi
      offset_hex=$(printf "%02x" $((offset & 0xff)))
      case "$op" in
      je) text_hex+="74$offset_hex" ;;
      jne) text_hex+="75$offset_hex" ;;
      jg) text_hex+="7f$offset_hex" ;;
      jl) text_hex+="7c$offset_hex" ;;
      jge) text_hex+="7d$offset_hex" ;;
      jle) text_hex+="7e$offset_hex" ;;
      jmp) text_hex+="eb$offset_hex" ;;
      esac
      current_address=$((current_address + 2))
    elif [[ "$line" =~ ^(loop|loope|loopne)[[:space:]]+(.*)$ ]]; then
      op="${BASH_REMATCH[1]}"
      lbl="${BASH_REMATCH[2]}"
      if [[ -z "${labels[$lbl]:-}" ]]; then
        echo "unknown label $lbl" >&2
        return 1
      fi
      target_address=${labels[$lbl]}
      offset=$((target_address - (current_address + 2)))
      if [ $offset -lt -128 ] || [ $offset -gt 127 ]; then
        echo "short jump out of range: $offset" >&2
        return 1
      fi
      offset_hex=$(printf "%02x" $((offset & 0xff)))
      case "$op" in
      loop) text_hex+="e2$offset_hex" ;;
      loope) text_hex+="e1$offset_hex" ;;
      loopne) text_hex+="e0$offset_hex" ;;
      esac
      current_address=$((current_address + 2))
elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+(r[a-z]{2})$ ]]; then
  op="${BASH_REMATCH[1]}"
  reg="${BASH_REMATCH[2]}"
  op_ext=0
  if [[ "$op" == "inc" ]]; then
    modrm=$((0xc0 + regs[$reg]))
    text_hex+=$(printf "48ff%02x" $modrm)
  elif [[ "$op" == "dec" ]]; then
    modrm=$((0xc8 + regs[$reg]))
    text_hex+=$(printf "48ff%02x" $modrm)
  elif [[ "$op" == "neg" ]]; then
    op_ext=3
    modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
    text_hex+=$(printf "48f7%02x" $modrm)
  elif [[ "$op" == "not" ]]; then
    op_ext=2
    modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
    text_hex+=$(printf "48f7%02x" $modrm)
  fi
      current_address=$((current_address + 3))
    elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
      lbl="${BASH_REMATCH[1]}"
      if [[ -z "${labels[$lbl]:-}" ]]; then
        echo "unknown label $lbl" >&2
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
      modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
      text_hex+=$(printf "48f7%02x" $modrm)
      current_address=$((current_address + 3))
    elif [[ "$line" =~ ^imul[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
      reg1="${BASH_REMATCH[1]}"
      reg2="${BASH_REMATCH[2]}"
      modrm=$((0xc0 | (regs[$reg1] << 3) | regs[$reg2]))
      text_hex+=$(printf "480faf%02x" $modrm)
      current_address=$((current_address + 4))
    elif [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
      reg="${BASH_REMATCH[1]}"
      lbl="${BASH_REMATCH[2]}"
      if [[ -z "${data_label_off[$lbl]:-}" ]]; then
        echo "unknown label $lbl" >&2
        return 1
      fi
      addr=$((data_vaddr + data_label_off[$lbl]))
      modrm=$(((regs[$reg] << 3) | 5))
      text_hex+=$(printf "488d%02x" $modrm)
      # RIP-relative addressing, offset is from the *next* instruction
      offset=$((addr - (text_vaddr + current_address + 7)))
      text_hex+=$(u32le $offset)
      current_address=$((current_address + 7))
    elif [[ "$line" =~ ^(shl|shr)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
      op="${BASH_REMATCH[1]}"
      reg="${BASH_REMATCH[2]}"
      val="${BASH_REMATCH[3]}"
      op_ext=0
      if [[ "$op" == "shl" ]]; then
        op_ext=4
      else
        op_ext=5
      fi
      modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
      text_hex+=$(printf "48c1%02x%02x" $modrm $val)
      current_address=$((current_address + 4))
    elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
      reg1="${BASH_REMATCH[1]}"
      reg2="${BASH_REMATCH[2]}"
      modrm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
      text_hex+=$(printf "4885%02x" $modrm)
      current_address=$((current_address + 3))
    elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
      reg="${BASH_REMATCH[1]}"
      arg="${BASH_REMATCH[2]}"
      if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
        val=$((16#${BASH_REMATCH[1]}))
      else
        val=$((arg))
      fi
      modrm=$((0xc0 | regs[$reg]))
      text_hex+=$(printf "48f7%02x" $modrm)$(u32le $val)
      current_address=$((current_address + 7))
    elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
      op="${BASH_REMATCH[1]}"
      dst="${BASH_REMATCH[2]}"
      src="${BASH_REMATCH[3]}"
      dst_reg=$(get_reg_num "$dst")
      src_reg=$(get_reg_num "$src")
      modrm=$((0xc0 | (dst_reg << 3) | src_reg))
      if [[ "$op" == "movzx" ]]; then
        text_hex+=$(printf "480fb6%02x" $modrm)
      else
        text_hex+=$(printf "480fbe%02x" $modrm)
      fi
      current_address=$((current_address + 4))
    elif [[ "$line" =~ ^movsxd[[:space:]]+(r[a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
      dst="${BASH_REMATCH[1]}"
      src="${BASH_REMATCH[2]}"
      dst_reg=$(get_reg_num "$dst")
      src_reg=$(get_reg_num "$src")
      modrm=$((0xc0 | (dst_reg << 3) | src_reg))
      text_hex+=$(printf "4863%02x" $modrm)
      current_address=$((current_address + 3))
    elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
      cond="${BASH_REMATCH[1]}"
      dst="${BASH_REMATCH[2]}"
      dst_reg=$(get_reg_num "$dst")
      modrm=$((0xc0 | dst_reg))
      
      case "$cond" in
      e|z) text_hex+=$(printf "0f94%02x" $modrm) ;;
      ne|nz) text_hex+=$(printf "0f95%02x" $modrm) ;;
      a) text_hex+=$(printf "0f97%02x" $modrm) ;;
      ae) text_hex+=$(printf "0f93%02x" $modrm) ;;
      b) text_hex+=$(printf "0f92%02x" $modrm) ;;
      be) text_hex+=$(printf "0f96%02x" $modrm) ;;
      g) text_hex+=$(printf "0f9f%02x" $modrm) ;;
      ge) text_hex+=$(printf "0f9d%02x" $modrm) ;;
      l) text_hex+=$(printf "0f9c%02x" $modrm) ;;
      le) text_hex+=$(printf "0f9e%02x" $modrm) ;;
      o) text_hex+=$(printf "0f90%02x" $modrm) ;;
      no) text_hex+=$(printf "0f91%02x" $modrm) ;;
      s) text_hex+=$(printf "0f98%02x" $modrm) ;;
      ns) text_hex+=$(printf "0f99%02x" $modrm) ;;
      esac
      current_address=$((current_address + 3))
    else
      echo "internal error assembling: $line" >&2
      return 1
    fi
  done

  tmpf="$(mktemp)"

  header_hex=""
  header_hex+="7f454c46"
  header_hex+="02"
  header_hex+="01"
  header_hex+="01"
  header_hex+="00"
  header_hex+="0000000000000000"
  header_hex+="0200"
  header_hex+="3e00"
  header_hex+="01000000"
  header_hex+="$(u64le $entry_vaddr)"
  header_hex+="$(u64le 0x40)"
  header_hex+="$(u64le 0)"
  header_hex+="00000000"
  header_hex+="4000"
  header_hex+="3800"
  header_hex+="0100"
  header_hex+="0000"
  header_hex+="0000"
  header_hex+="0000"

  header_hex+="$(u32le 1)"
  header_hex+="$(u32le 5)"
  header_hex+="$(u64le $file_text_off)"
  header_hex+="$(u64le $text_vaddr)"
  header_hex+="$(u64le $text_vaddr)"
  filesz=$((file_data_off + data_size))
  header_hex+="$(u64le $filesz)"
  header_hex+="$(u64le $filesz)"
  header_hex+="$(u64le 0x200000)"

  hex_to_bin "$header_hex" >"$tmpf"

  # Calculate expected header size from hex string length (each 2 hex chars = 1 byte)
  cur_size=$((${#header_hex} / 2))
  if ((cur_size > file_text_off)); then
    echo "header too big" >&2
    return 1
  fi
  pad=$((file_text_off - cur_size))
  generate_zeros "$pad" >>"$tmpf"

  hex_to_bin "$text_hex" >>"$tmpf"
  hex_to_bin "$data_bytes" >>"$tmpf"

  # Calculate expected total size: header + padding + text + data
  text_size=$((${#text_hex} / 2))
  data_size=$((${#data_bytes} / 2))
  actual_size=$((file_text_off + text_size + data_size))
  
  if [ "$actual_size" -ne "$filesz" ]; then
    filesz=$actual_size
    seek=$((0x38))
    pf="$(u64le $filesz)$(u64le $filesz)"
    # Create a temporary file with the binary data, then write at specific offset using pure bash
    local temp_bin
    temp_bin=$(mktemp)
    hex_to_bin "$pf" > "$temp_bin"
    write_at_offset "$temp_bin" "$tmpf" "$seek"
    rm -f "$temp_bin"
  fi

  chmod +x "$tmpf"
  mv -f "$tmpf" "$outfile"
  return 0
}

