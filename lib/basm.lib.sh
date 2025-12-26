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

# Load instruction definitions from file
load_instruction_defs() {
  local defs_file="$1"
  declare -gA instruction_defs  # Global associative array for instruction definitions
  declare -gA instruction_sizes # Global associative array for instruction sizes

  if [[ ! -f "$defs_file" ]]; then
    echo "instruction definitions file not found: $defs_file" >&2
    return 1
  fi

  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Parse line: instruction,operands,opcode,size,encoding_rule
    IFS=',' read -r instruction operands opcode size encoding_rule <<<"$line"

    # Remove leading/trailing whitespace using pure bash
    instruction=$(trim_string "$instruction")
    operands=$(trim_string "$operands")
    opcode=$(trim_string "$opcode")
    size=$(trim_string "$size")
    encoding_rule=$(trim_string "$encoding_rule")

    # Store in associative arrays
    instruction_defs["$instruction,$operands"]="$opcode $encoding_rule"
    instruction_sizes["$instruction,$operands"]="$size"
  done <"$defs_file"
}

basm_assemble() {
  local code_str="${1:-""]}"
  local outfile="${2:-a.out}"

  # Load instruction definitions
  local defs_file="${BASH_SOURCE%/*}/../chipsets/x86_64_comprehensive.def"
  if ! load_instruction_defs "$defs_file"; then
    echo "failed to load instruction definitions" >&2
    return 1
  fi

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

  # Function to get instruction size from definitions
  get_instruction_size() {
    local line="$1"
    local instruction
    local operands

    # Extract the instruction name
    if [[ "$line" =~ ^([a-zA-Z]+)[[:space:]] ]]; then
      instruction="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^([a-zA-Z]+)$ ]]; then
      instruction="${BASH_REMATCH[1]}"
    else
      echo "0" # Unknown instruction
      return 1
    fi

    # Determine operands pattern based on the line
    case "$instruction" in
    mov)
      if [[ "$line" =~ ^mov[[:space:]]+r([a-z]{2}),[[:space:]]+r([a-z]{2})$ ]]; then
        echo "${instruction_sizes[mov, r64, r64]:-3}"
      elif [[ "$line" =~ ^mov[[:space:]]+r([a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+|-?[0-9]+|[a-zA-Z0-9_]+)$ ]]; then
        arg="${BASH_REMATCH[2]}"
        if [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^-?[0-9]+$ ]] || [[ "$arg" =~ ^0x[0-9a-fA-F]+$ ]] || [[ -n "${equs[$arg]:-}" ]]; then
          echo "${instruction_sizes[mov, r64, imm32]:-7}"
        else
          echo "${instruction_sizes[mov, r64, imm64]:-10}"
        fi
      else
        echo "3" # Default size
      fi
      ;;
    add | sub | cmp | or | and)
      reg_pattern="r([a-z]{2})"
      if [[ "$line" =~ ^($instruction)[[:space:]]+r([a-z]{2}),[[:space:]]*([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
        reg="${BASH_REMATCH[2]}"
        if [[ "$reg" == "rax" ]]; then
          if [[ "$instruction" == "cmp" ]]; then
            echo "${instruction_sizes[cmp, rax, imm32]:-6}"
          else
            echo "${instruction_sizes[add, rax, imm32]:-7}" # Using add as template for similar ops
          fi
        else
          echo "${instruction_sizes[$instruction, r64, imm8]:-4}"
        fi
      elif [[ "$line" =~ ^($instruction)[[:space:]]+r([a-z]{2}),[[:space:]]+r([a-z]{2})$ ]]; then
        echo "${instruction_sizes[$instruction, r64, r64]:-4}"
      else
        echo "4" # Default size
      fi
      ;;
    push | pop)
      if [[ "$line" =~ ^($instruction)[[:space:]]+r([a-z]{2})$ ]]; then
        echo "${instruction_sizes[$instruction, r64]:-1}"
      else
        echo "1" # Default size
      fi
      ;;
    call)
      if [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
        echo "${instruction_sizes[call, imm32]:-5}"
      else
        echo "5" # Default size
      fi
      ;;

    jmp | je | jne | jg | jl | jge | jle | loop)
      if [[ "$line" =~ ^(j[a-z]*|loop)[[:space:]]+(.*)$ ]]; then
        echo "${instruction_sizes[jmp, imm8]:-2}" # Using jmp as template for all jumps
      else
        echo "2" # Default size
      fi
      ;;
    inc | dec | neg | mul | div | idiv)
      if [[ "$line" =~ ^($instruction)[[:space:]]+r([a-z]{2})$ ]]; then
        echo "${instruction_sizes[$instruction, r64]:-3}"
      else
        echo "3" # Default size
      fi
      ;;
    imul)
      if [[ "$line" =~ ^imul[[:space:]]+r([a-z]{2}),[[:space:]]+r([a-z]{2})$ ]]; then
        echo "${instruction_sizes[imul, r64, r64]:-4}"
      else
        echo "4" # Default size
      fi
      ;;
    lea)
      if [[ "$line" =~ ^lea[[:space:]]+r([a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
        echo "${instruction_sizes[lea, r64, mem]:-7}"
      else
        echo "7" # Default size
      fi
      ;;
    shl | shr)
      if [[ "$line" =~ ^($instruction)[[:space:]]+r([a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
        echo "${instruction_sizes[shl, r64, imm8]:-4}" # Using shl as template for both
      else
        echo "4" # Default size
      fi
      ;;
    test)
      if [[ "$line" =~ ^test[[:space:]]+r([a-z]{2}),[[:space:]]+r([a-z]{2})$ ]]; then
        echo "${instruction_sizes[test, r64, r64]:-3}"
      elif [[ "$line" =~ ^test[[:space:]]+r([a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
        echo "${instruction_sizes[test, r64, imm32]:-7}"
      else
        echo "3" # Default size
      fi
      ;;
    xor)
      if [[ "$line" =~ ^xor[[:space:]]+r([a-z]{2}),[[:space:]]+r([a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
        echo "${instruction_sizes[xor, r64, r64]:-3}"
      else
        echo "3" # Default size
      fi
      ;;
    syscall)
      echo "${instruction_sizes[syscall]:-2}"
      ;;
    nop)
      echo "${instruction_sizes[nop]:-1}"
      ;;
    ret)
      echo "${instruction_sizes[ret]:-1}"
      ;;
    *)
      echo "0" # Unknown instruction
      return 1
      ;;
    esac
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
      elif [[ "$line" =~ ^loop ]]; then
        text_bytes_len=$((text_bytes_len + 2))
      elif [[ "$line" =~ ^(inc|dec|neg)[[:space:]]+(r[a-z]{2})$ ]]; then
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

  # Function to look up instruction in definitions and encode it
  lookup_and_encode_instruction() {
    local line="$1"
    local current_addr="$2"
    local data_vaddr="$3"
    local text_vaddr="$4"
    local instruction
    local operands
    local arg
    local reg
    local dst
    local src
    local val
    local val_is_immediate=0
    local addr
    local modrm
    local op

    # Extract the instruction name
    if [[ "$line" =~ ^([a-zA-Z]+)[[:space:]] ]]; then
      instruction="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^([a-zA-Z]+)$ ]]; then
      instruction="${BASH_REMATCH[1]}"
    else
      return 1 # Not handled by definitions
    fi

    # Create operand pattern based on the line
    case "$instruction" in
    nop)
      if [[ "$line" == "nop" ]]; then
        printf "90"
        return 0 # Successfully encoded using definition
      fi
      ;;
    ret)
      if [[ "$line" == "ret" ]]; then
        printf "c3"
        return 0 # Successfully encoded using definition
      fi
      ;;
    syscall)
      if [[ "$line" == "syscall" ]]; then
        printf "0f05"
        return 0 # Successfully encoded using definition
      fi
      ;;
    mov)
      # Handle mov r64, r64
      if [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        dst="${BASH_REMATCH[1]}"
        src="${BASH_REMATCH[2]}"
        modrm=$((0xc0 + regs[$src] * 8 + regs[$dst]))
        printf "4889%02x" $modrm
        return 0
      # Handle mov r64, imm32
      elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+|-?[0-9]+)$ ]]; then
        reg="${BASH_REMATCH[1]}"
        arg="${BASH_REMATCH[2]}"
        val_is_immediate=0
        if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
          val=$((16#${BASH_REMATCH[1]}))
          val_is_immediate=1
        elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
          val=$((arg))
          val_is_immediate=1
        fi

        if [[ "$val_is_immediate" -eq 1 ]]; then
          opcode=$((0xc0 + regs[$reg]))
          printf "48c7%02x" $opcode
          u32le $val
          return 0
        fi
      # Handle mov r64, imm64 (memory address)
      elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+([a-zA-Z0-9_]+)$ ]]; then
        reg="${BASH_REMATCH[1]}"
        arg="${BASH_REMATCH[2]}"

        op=$((0xb8 + regs[$reg]))
        if [[ -n "${data_label_off[$arg]:-}" ]]; then
          addr=$((data_vaddr + data_label_off[$arg]))
        elif [[ -n "${labels[$arg]:-}" ]]; then
          addr=$((text_vaddr + labels[$arg]))
        else
          return 1 # Unknown label, let fallback handle it
        fi
        printf "48%02x" $op
        u64le $addr
        return 0
      fi
      ;;
    add | sub | and | or | cmp)
      op="${instruction}"
      if [[ "$line" =~ ^($op)[[:space:]]+(r[a-z]{2}),[[:space:]]*([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
        reg="${BASH_REMATCH[2]}"
        arg="${BASH_REMATCH[3]}"

        if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
          val=$((16#${BASH_REMATCH[1]}))
        elif [[ "$arg" =~ ^[0-9]+$ ]]; then
          val=$((arg))
        else
          return 1 # Not handled
        fi

        if [[ "$reg" == "rax" ]]; then
          case "$op" in
          add)
            printf "4881c0"
            u32le $val
            return 0
            ;;
          sub)
            printf "4881e8"
            u32le $val
            return 0
            ;;
          or)
            printf "4881c8"
            u32le $val
            return 0
            ;;
          and)
            printf "4881e0"
            u32le $val
            return 0
            ;;
          cmp)
            printf "483d"
            u32le $val
            return 0
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
          printf "4883%02x%02x" $modrm $val
          return 0
        fi
      elif [[ "$line" =~ ^($op)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        reg1="${BASH_REMATCH[2]}"
        reg2="${BASH_REMATCH[3]}"
        # For register-to-register operations
        modrm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
        case "$op" in
        add) printf "4801%02x" $modrm ;;
        sub) printf "4829%02x" $modrm ;;
        and) printf "4821%02x" $modrm ;;
        or) printf "4809%02x" $modrm ;;
        cmp) printf "4839%02x" $modrm ;;
        esac
        return 0
      fi
      ;;
    xor)
      # Handle xor r64, r64 (when same register - for zeroing)
      if [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
        reg="${BASH_REMATCH[1]}"
        modrm=$((0xc0 + regs[$reg] * 8 + regs[$reg]))
        printf "4831%02x" $modrm
        return 0
      # Handle xor r64, r64 (different registers)
      elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        reg1="${BASH_REMATCH[1]}"
        reg2="${BASH_REMATCH[2]}"
        modrm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
        printf "4831%02x" $modrm
        return 0
      fi
      ;;
    push | pop)
      if [[ "$line" =~ ^(push|pop)[[:space:]]+(r[a-z]{2})$ ]]; then
        reg="${BASH_REMATCH[2]}"
        op=$((0x50 + regs[$reg]))
        if [[ "${BASH_REMATCH[1]}" == "pop" ]]; then
          op=$((0x58 + regs[$reg]))
        fi
        printf "%02x" $op
        return 0
      fi
      ;;
    call)
      if [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
        lbl="${BASH_REMATCH[1]}"
        if [[ -z "${labels[$lbl]:-}" ]]; then
          return 1 # Unknown label, let fallback handle it
        fi
        target_address=${labels[$lbl]}
        offset=$((target_address - (current_addr + 5)))
        printf "e8"
        u32le $offset
        return 0
      fi
      ;;
    inc | dec | neg)
      if [[ "$line" =~ ^(inc|dec|neg)[[:space:]]+(r[a-z]{2})$ ]]; then
        op="${BASH_REMATCH[1]}"
        reg="${BASH_REMATCH[2]}"
        op_ext=0
        if [[ "$op" == "inc" ]]; then
          modrm=$((0xc0 + regs[$reg]))
        elif [[ "$op" == "dec" ]]; then
          modrm=$((0xc8 + regs[$reg]))
        elif [[ "$op" == "neg" ]]; then
          op_ext=3
          modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
        fi
        printf "48ff%02x" $modrm
        return 0
      fi
      ;;
    mul | div | idiv)
      if [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
        op="${BASH_REMATCH[1]}"
        reg="${BASH_REMATCH[2]}"
        op_ext=0
        case "$op" in
        mul) op_ext=4 ;;
        div) op_ext=6 ;;
        idiv) op_ext=7 ;;
        esac
        modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
        printf "48f7%02x" $modrm
        return 0
      fi
      ;;
    imul)
      if [[ "$line" =~ ^imul[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        reg1="${BASH_REMATCH[1]}"
        reg2="${BASH_REMATCH[2]}"
        modrm=$((0xc0 | (regs[$reg1] << 3) | regs[$reg2]))
        printf "480faf%02x" $modrm
        return 0
      fi
      ;;
    lea)
      if [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
        reg="${BASH_REMATCH[1]}"
        lbl="${BASH_REMATCH[2]}"
        if [[ -z "${data_label_off[$lbl]:-}" ]]; then
          return 1 # Unknown label, let fallback handle it
        fi
        addr=$((data_vaddr + data_label_off[$lbl]))
        modrm=$(((regs[$reg] << 3) | 5))
        printf "488d%02x" $modrm
        # RIP-relative addressing, offset is from the *next* instruction
        offset=$((addr - (text_vaddr + current_addr + 7)))
        u32le $offset
        return 0
      fi
      ;;
    shl | shr)
      if [[ "$line" =~ ^(shl|shr)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
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
        printf "48c1%02x%02x" $modrm $val
        return 0
      fi
      ;;
    test)
      if [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        reg1="${BASH_REMATCH[1]}"
        reg2="${BASH_REMATCH[2]}"
        modrm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
        printf "4885%02x" $modrm
        return 0
      elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
        reg="${BASH_REMATCH[1]}"
        arg="${BASH_REMATCH[2]}"
        if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
          val=$((16#${BASH_REMATCH[1]}))
        else
          val=$((arg))
        fi
        modrm=$((0xc0 | regs[$reg]))
        printf "48f7%02x" $modrm
        u32le $val
        return 0
      fi
      ;;
    jmp | je | jne | jg | jl | jge | jle | loop)
      if [[ "$line" =~ ^(j[a-z]*|loop)[[:space:]]+(.*)$ ]]; then
        op="${BASH_REMATCH[1]}"
        lbl="${BASH_REMATCH[2]}"
        if [[ -z "${labels[$lbl]:-}" ]]; then
          return 1 # Unknown label, let fallback handle it
        fi
        target_address=${labels[$lbl]}
        offset=$((target_address - (current_addr + 2)))
        if [ $offset -lt -128 ] || [ $offset -gt 127 ]; then
          return 1 # Jump out of range, let fallback handle error
        fi
        offset_hex=$(printf "%02x" $((offset & 0xff)))
        case "$op" in
        je) printf "74$offset_hex" ;;
        jne) printf "75$offset_hex" ;;
        jg) printf "7f$offset_hex" ;;
        jl) printf "7c$offset_hex" ;;
        jge) printf "7d$offset_hex" ;;
        jle) printf "7e$offset_hex" ;;
        jmp) printf "eb$offset_hex" ;;
        loop) printf "e2$offset_hex" ;;
        esac
        return 0
      fi
      ;;
      # Add more defined instructions as needed
    esac

    return 1 # Not handled by definitions
  }

  # Helper function for encoding instructions based on patterns (migrating to use definitions)
  encode_instruction() {
    local line="$1"
    local current_addr="$2"
    local data_vaddr="$3"
    local text_vaddr="$4"
    local label_val
    local op_ext=0
    local modrm=0
    local val=0

    # Try to encode using instruction definitions first
    if lookup_and_encode_instruction "$line" "$current_addr" "$data_vaddr" "$text_vaddr"; then
      return 0 # Successfully encoded using definitions
    fi

    # Extract the instruction name
    if [[ "$line" =~ ^([a-zA-Z]+)[[:space:]] ]]; then
      instruction="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^([a-zA-Z]+)$ ]]; then
      instruction="${BASH_REMATCH[1]}"
    else
      echo "invalid instruction format: $line" >&2
      return 1
    fi

    # Process different instructions based on patterns
    case "$instruction" in
    mov)
      if [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        # mov r64, r64
        dst="${BASH_REMATCH[1]}"
        src="${BASH_REMATCH[2]}"
        modrm=$((0xc0 + regs[$src] * 8 + regs[$dst]))
        printf "4889%02x" $modrm
        return 0
      elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$ ]]; then
        # mov r64, immediate or memory
        reg="${BASH_REMATCH[1]}"
        arg="${BASH_REMATCH[2]}"
        local val_is_immediate=0
        local val
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
          # mov r64, imm32
          opcode=$((0xc0 + regs[$reg]))
          printf "48c7%02x" $opcode
          u32le $val
          return 0
        else
          # mov r64, imm64 (memory access)
          op=$((0xb8 + regs[$reg]))
          if [[ -n "${data_label_off[$arg]:-}" ]]; then
            addr=$((data_vaddr + data_label_off[$arg]))
          elif [[ -n "${labels[$arg]:-}" ]]; then
            addr=$((text_vaddr + labels[$arg]))
          else
            echo "unknown label $arg" >&2
            return 1
          fi
          printf "48%02x" $op
          u64le $addr
          return 0
        fi
      fi
      ;;
    add | sub | cmp | or | and)
      if [[ "$line" =~ ^($instruction)[[:space:]]+(r[a-z]{2}),[[:space:]]*(.*)$ ]]; then
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
            printf "4881c0"
            u32le $val
            ;;
          sub)
            printf "4881e8"
            u32le $val
            ;;
          or)
            printf "4881c8"
            u32le $val
            ;;
          and)
            printf "4881e0"
            u32le $val
            ;;
          cmp)
            printf "483d"
            u32le $val
            ;;
          esac
          return 0
        else
          case "$op" in
          add) op_ext=0 ;;
          sub) op_ext=5 ;;
          cmp) op_ext=7 ;;
          or) op_ext=1 ;;
          and) op_ext=4 ;;
          esac
          modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
          printf "4883%02x%02x" $modrm $val
          return 0
        fi
      fi
      ;;
    push)
      if [[ "$line" =~ ^push[[:space:]]+(r[a-z]{2})$ ]]; then
        reg="${BASH_REMATCH[1]}"
        op=$((0x50 + regs[$reg]))
        printf "%02x" $op
        return 0
      fi
      ;;
    pop)
      if [[ "$line" =~ ^pop[[:space:]]+(r[a-z]{2})$ ]]; then
        reg="${BASH_REMATCH[1]}"
        op=$((0x58 + regs[$reg]))
        printf "%02x" $op
        return 0
      fi
      ;;
    jmp | je | jne | jg | jl | jge | jle)
      if [[ "$line" =~ ^(j[a-z]*)[[:space:]]+(.*)$ ]]; then
        op="${BASH_REMATCH[1]}"
        lbl="${BASH_REMATCH[2]}"
        if [[ -z "${labels[$lbl]:-}" ]]; then
          echo "unknown label $lbl" >&2
          return 1
        fi
        target_address=${labels[$lbl]}
        offset=$((target_address - (current_addr + 2)))
        if [ $offset -lt -128 ] || [ $offset -gt 127 ]; then
          echo "short jump out of range: $offset" >&2
          return 1
        fi
        offset_hex=$(printf "%02x" $((offset & 0xff)))
        case "$op" in
        je) printf "74$offset_hex" ;;
        jne) printf "75$offset_hex" ;;
        jg) printf "7f$offset_hex" ;;
        jl) printf "7c$offset_hex" ;;
        jge) printf "7d$offset_hex" ;;
        jle) printf "7e$offset_hex" ;;
        jmp) printf "eb$offset_hex" ;;
        esac
        return 0
      fi
      ;;
    inc | dec | neg)
      if [[ "$line" =~ ^(inc|dec|neg)[[:space:]]+(r[a-z]{2})$ ]]; then
        op="${BASH_REMATCH[1]}"
        reg="${BASH_REMATCH[2]}"
        if [[ "$op" == "inc" ]]; then
          modrm=$((0xc0 + regs[$reg]))
          printf "48ff%02x" $modrm
        elif [[ "$op" == "dec" ]]; then
          modrm=$((0xc8 + regs[$reg]))
          printf "48ff%02x" $modrm
        elif [[ "$op" == "neg" ]]; then
          op_ext=3
          modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
          printf "48f7%02x" $modrm
        fi
        return 0
      fi
      ;;
    call)
      if [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
        lbl="${BASH_REMATCH[1]}"
        if [[ -z "${labels[$lbl]:-}" ]]; then
          echo "unknown label $lbl" >&2
          return 1
        fi
        target_address=${labels[$lbl]}
        offset=$((target_address - (current_addr + 5)))
        printf "e8"
        u32le $offset
        return 0
      fi
      ;;
    mul | div | idiv)
      if [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
        op="${BASH_REMATCH[1]}"
        reg="${BASH_REMATCH[2]}"
        case "$op" in
        mul) op_ext=4 ;;
        div) op_ext=6 ;;
        idiv) op_ext=7 ;;
        esac
        modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
        printf "48f7%02x" $modrm
        return 0
      fi
      ;;
    imul)
      if [[ "$line" =~ ^imul[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        reg1="${BASH_REMATCH[1]}"
        reg2="${BASH_REMATCH[2]}"
        modrm=$((0xc0 | (regs[$reg1] << 3) | regs[$reg2]))
        printf "480faf%02x" $modrm
        return 0
      fi
      ;;
    lea)
      if [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
        reg="${BASH_REMATCH[1]}"
        lbl="${BASH_REMATCH[2]}"
        if [[ -z "${data_label_off[$lbl]:-}" ]]; then
          echo "unknown label $lbl" >&2
          return 1
        fi
        addr=$((data_vaddr + data_label_off[$lbl]))
        modrm=$(((regs[$reg] << 3) | 5))
        printf "488d%02x" $modrm
        # RIP-relative addressing, offset is from the *next* instruction
        offset=$((addr - (text_vaddr + current_addr + 7)))
        u32le $offset
        return 0
      fi
      ;;
    shl | shr)
      if [[ "$line" =~ ^(shl|shr)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
        op="${BASH_REMATCH[1]}"
        reg="${BASH_REMATCH[2]}"
        val="${BASH_REMATCH[3]}"
        if [[ "$op" == "shl" ]]; then
          op_ext=4
        else
          op_ext=5
        fi
        modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
        printf "48c1%02x%02x" $modrm $val
        return 0
      fi
      ;;
    test)
      if [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
        reg1="${BASH_REMATCH[1]}"
        reg2="${BASH_REMATCH[2]}"
        modrm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
        printf "4885%02x" $modrm
        return 0
      elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
        reg="${BASH_REMATCH[1]}"
        arg="${BASH_REMATCH[2]}"
        if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
          val=$((16#${BASH_REMATCH[1]}))
        else
          val=$((arg))
        fi
        modrm=$((0xc0 | regs[$reg]))
        printf "48f7%02x" $modrm
        u32le $val
        return 0
      fi
      ;;
    xor)
      if [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
        reg="${BASH_REMATCH[1]}"
        modrm=$((0xc0 + regs[$reg] * 8 + regs[$reg]))
        printf "4831%02x" $modrm
        return 0
      fi
      ;;
    syscall)
      if [[ "$line" == "syscall" ]]; then
        printf "0f05"
        return 0
      fi
      ;;
    nop)
      if [[ "$line" == "nop" ]]; then
        printf "90"
        return 0
      fi
      ;;
    ret)
      if [[ "$line" == "ret" ]]; then
        printf "c3"
        return 0
      fi
      ;;
    *)
      echo "unknown instruction: $line" >&2
      return 1
      ;;
    esac
    echo "internal error encoding instruction: $line" >&2
    return 1
  }

  text_hex=""
  current_address=0
  for line in "${text_ins[@]}"; do
    if [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
      dst="${BASH_REMATCH[1]}"
      src="${BASH_REMATCH[2]}"
      modrm=$((0xc0 + regs[$src] * 8 + regs[$dst]))
      text_hex+=$(printf "4889%02x" $modrm)
      current_address=$((current_address + 3))
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
    elif [[ "$line" =~ ^loop[[:space:]]+(.*)$ ]]; then
      lbl="${BASH_REMATCH[1]}"
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
      text_hex+="e2$offset_hex"
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

