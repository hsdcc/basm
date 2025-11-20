#!/usr/bin/env bash

basm_assemble() {
  local code_str="${1:-""}"
  local outfile="${2:-a.out}"

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

  mapfile -t lines <<< "$code_str"

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

  data_bytes=""
  text_ins=()
  text_bytes_len=0
  in_section=""

  for raw in "${lines[@]}"; do
    line="${raw%%;*}"
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
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

      if [[ "$line" =~ ^([a-zA-Z0-9_]+):?[[:space:]]+(db|dq)[[:space:]]+(.*)$ ]]; then
        name="${BASH_REMATCH[1]}"
        directive="${BASH_REMATCH[2]}"
        values_str="${BASH_REMATCH[3]}"
        hex=""
        IFS=',' read -ra values <<< "$values_str"
        for val_item in "${values[@]}"; do
          val_item="$(echo "$val_item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          if [[ "$val_item" =~ ^\"(.*)\"$ ]]; then
            txt="${BASH_REMATCH[1]}"
            txt="$(echo -n "$txt" | sed -e 's/\\/\\\\x5c/g' -e 's/\n/\
/g' -e 's/"/"/g')"
            i=0
            while [ $i -lt ${#txt} ]; do
              ch="${txt:i:1}"
              oc=$(printf "%d" "'$ch")
              hex+="$(printf "%02x" $oc)"
              i=$((i + 1))
            done
          elif [[ "$val_item" =~ ^-?[0-9]+$ ]]; then
            if [[ "$directive" == "db" ]]; then
              hex+="$(printf "%02x" "$val_item")"
            elif [[ "$directive" == "dq" ]]; then
              hex+="$(u64le "$val_item")"
            fi
          else
            echo "unsupported data value: $val_item" >&2
            return 1
          fi
        done
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
      if [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+\[(r[a-z]{2})\+([0-9]+)\]$ ]]; then
        text_bytes_len=$((text_bytes_len + 4)) # 48 8B ModR/M disp8
      elif [[ "$line" =~ ^mov[[:space:]]+\[(r[a-z]{2})\+([0-9]+)\],[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 4)) # 48 89 ModR/M disp8
      elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ && ! "${BASH_REMATCH[2]}" =~ \+ ]]; then
        text_bytes_len=$((text_bytes_len + 7)) # 48 8B ModR/M disp32 (RIP-relative)
      elif [[ "$line" =~ ^mov[[:space:]]+\[([a-zA-Z0-9_]+)\],[[:space:]]+(r[a-z]{2})$ && ! "${BASH_REMATCH[1]}" =~ \+ ]]; then
        text_bytes_len=$((text_bytes_len + 7)) # 48 89 ModR/M disp32 (RIP-relative)
      elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+\[(r[a-z]{2})\]$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^mov[[:space:]]+\[(r[a-z]{2})\],[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$ ]]; then
        arg="${BASH_REMATCH[2]}"
        if [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^-?[0-9]+$ ]] || [[ "$arg" =~ ^0x[0-9a-fA-F]+$ ]] || [[ -n "${equs[$arg]:-}" ]]; then
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
      elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^(push|pop)[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 1))
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
      elif [[ "$line" =~ ^(inc|dec|neg)[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
        text_bytes_len=$((text_bytes_len + 5))
      elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^(imul)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 4))
      elif [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+[[:space:]]*\[([a-zA-Z0-9_]+)\]$ ]]; then
        text_bytes_len=$((text_bytes_len + 7))
      elif [[ "$line" =~ ^(shl|shr)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
        text_bytes_len=$((text_bytes_len + 4))
      elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        text_bytes_len=$((text_bytes_len + 3))
      elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
        text_bytes_len=$((text_bytes_len + 7))
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
    elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+\[(r[a-z]{2})\]$ ]]; then
      dst="${BASH_REMATCH[1]}"
      src="${BASH_REMATCH[2]}"
      modrm=$((0x00 + regs[$dst] * 8 + regs[$src]))
      text_hex+=$(printf "488b%02x" $modrm)
      current_address=$((current_address + 3))
    elif [[ "$line" =~ ^mov[[:space:]]+\[(r[a-z]{2})\],[[:space:]]+(r[a-z]{2})$ ]]; then
      dst="${BASH_REMATCH[1]}"
      src="${BASH_REMATCH[2]}"
      modrm=$((0x00 + regs[$src] * 8 + regs[$dst]))
      text_hex+=$(printf "4889%02x" $modrm)
      current_address=$((current_address + 3))
    elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+\[(r[a-z]{2})[[:space:]]*\+\s*([0-9]+)\]$ ]]; then
      dst="${BASH_REMATCH[1]}"
      base="${BASH_REMATCH[2]}"
      offset="${BASH_REMATCH[3]}"
      modrm=$((0x40 + regs[$dst] * 8 + regs[$base]))
      text_hex+=$(printf "488b%02x%02x" $modrm $offset)
      current_address=$((current_address + 4))
    elif [[ "$line" =~ ^mov[[:space:]]+\[(r[a-z]{2})[[:space:]]*\+\s*([0-9]+)\],[[:space:]]+(r[a-z]{2})$ ]]; then
      base="${BASH_REMATCH[1]}"
      offset="${BASH_REMATCH[2]}"
      src="${BASH_REMATCH[3]}"
      modrm=$((0x40 + regs[$src] * 8 + regs[$base]))
      text_hex+=$(printf "4889%02x%02x" $modrm $offset)
      current_address=$((current_address + 4))
    elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
      reg="${BASH_REMATCH[1]}"
      lbl="${BASH_REMATCH[2]}"
      if [[ -z "${data_label_off[$lbl]:-}" ]]; then
        echo "unknown label $lbl" >&2
        return 1
      fi
      addr=$((data_vaddr + data_label_off[$lbl]))
      modrm=$(( (regs[$reg] << 3) | 5 ))
      text_hex+=$(printf "488b%02x" $modrm)
      offset=$((addr - (text_vaddr + current_address + 7)))
      text_hex+=$(u32le $offset)
      current_address=$((current_address + 7))
    elif [[ "$line" =~ ^mov[[:space:]]+\[([a-zA-Z0-9_]+)\],[[:space:]]+(r[a-z]{2})$ ]]; then
      lbl="${BASH_REMATCH[1]}"
      reg="${BASH_REMATCH[2]}"
      if [[ -z "${data_label_off[$lbl]:-}" ]]; then
        echo "unknown label $lbl" >&2
        return 1
      fi
      addr=$((data_vaddr + data_label_off[$lbl]))
      modrm=$(( (regs[$reg] << 3) | 5 ))
      text_hex+=$(printf "4889%02x" $modrm)
      offset=$((addr - (text_vaddr + current_address + 7)))
      text_hex+=$(u32le $offset)
      current_address=$((current_address + 7))
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
            add) text_hex+="4881c0$(u32le $val)"; current_address=$((current_address + 7)) ;; 
            sub) text_hex+="4881e8$(u32le $val)"; current_address=$((current_address + 7)) ;; 
            or) text_hex+="4881c8$(u32le $val)"; current_address=$((current_address + 7)) ;; 
            and) text_hex+="4881e0$(u32le $val)"; current_address=$((current_address + 7)) ;; 
            cmp) text_hex+="483d$(u32le $val)"; current_address=$((current_address + 6)) ;; 
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
            modrm=$(( 0xc0 | (op_ext << 3) | regs[$reg] ))
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
    elif [[ "$line" =~ ^(inc|dec|neg)[[:space:]]+(r[a-z]{2})$ ]]; then
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
    elif [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+[[:space:]]*\[([a-zA-Z0-9_]+)\]$ ]]; then
      reg="${BASH_REMATCH[1]}"
      lbl="${BASH_REMATCH[2]}"
      if [[ -z "${data_label_off[$lbl]:-}" ]]; then
        echo "unknown label $lbl" >&2
        return 1
      fi
      addr=$((data_vaddr + data_label_off[$lbl]))
      modrm=$(( (regs[$reg] << 3) | 5 ))
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

  echo -n "$header_hex" | xxd -r -p >"$tmpf"

  cur_size=$(stat -c%s "$tmpf")
  if ((cur_size > file_text_off)); then
    echo "header too big" >&2
    return 1
  fi
  pad=$((file_text_off - cur_size))
  dd if=/dev/zero bs=1 count=$pad 2>/dev/null >>"$tmpf"

  echo -n "$text_hex" | xxd -r -p >>"$tmpf"
  echo -n "$data_bytes" | xxd -r -p >>"$tmpf"

  actual_size=$(stat -c%s "$tmpf")
  if [ "$actual_size" -ne "$filesz" ]; then
    filesz=$actual_size
    seek=$((0x38))
    pf="$(u64le $filesz)$(u64le $filesz)"
    echo -n "$pf" | xxd -r -p | dd of="$tmpf" bs=1 seek=$seek conv=notrunc 2>/dev/null
  fi

  chmod +x "$tmpf"
  mv -f "$tmpf" "$outfile"
  return 0
}
