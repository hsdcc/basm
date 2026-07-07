#!/usr/bin/env bash
get_reg_num() {
  local reg="$1"
  local num=${regs[$reg]:--1}
  echo "$num"
}

get_reg_size() {
  local reg="$1"
  case "$reg" in
    al | cl | dl | bl | ah | ch | dh | bh | spl | bpl | sil | dil | r8b | r9b | r10b | r11b | r12b | r13b | r14b | r15b) echo 1 ;;
    ax | cx | dx | bx | sp | bp | si | di) echo 2 ;;
    eax | ecx | edx | ebx | esp | ebp | esi | edi | r8d | r9d | r10d | r11d | r12d | r13d | r14d | r15d) echo 4 ;;
    *) echo 8 ;;
  esac
}
# Return REX prefix for a register, empty for no prefix
get_rex_for_reg() {
  local reg="$1"
  local num=${regs[$reg]:--1}
  ((num < 0)) && {
    echo ""
    return
  }
  local size=$(get_reg_size "$reg")
  local w_flag=$((size == 8 ? 1 : 0))
  local b_bit=$(((num >> 3) & 1))
  local w_bit=$((w_flag & 1))
  local rex=$((0x40 | (w_bit << 3) | b_bit))
  if ((rex == 0x40)); then
    # spl/bpl/sil/dil still need REX prefix to access as low byte
    case "$reg" in
      spl | bpl | sil | dil) echo "40" ;;
      *) echo "" ;;
    esac
  else
    printf "%02x" "$rex"
  fi
}
# Compute REX prefix byte from register numbers
# $1: register number in ModRM.reg field (determines REX.R)
# $2: register number in ModRM.rm field (determines REX.B)
# $3: 1 if 64-bit operand (sets REX.W), 0 if 32-bit or smaller
# Returns two-char hex like "48", "4b", "41", or "" if no REX needed
get_rex_bits() {
  local r_num=$1 b_num=$2 w_flag=$3
  local r_bit=$(((r_num >> 3) & 1))
  local b_bit=$(((b_num >> 3) & 1))
  local w_bit=$((w_flag & 1))
  local rex=$((0x40 | (w_bit << 3) | (r_bit << 2) | b_bit))
  if ((rex == 0x40)); then
    echo ""
  else
    printf "%02x" "$rex"
  fi
}

# Compute REX for memory-operand instr: reg field vs base register
# $1: register name in ModRM.reg field
# $2: base register name from memory operand
get_rex_for_mem_operand() {
  local reg_name="$1"
  local base_name="$2"
  local reg_num=${regs[$reg_name]:--1}
  ((reg_num < 0)) && { echo ""; return; }
  local base_num=${regs[$base_name]:--1}
  ((base_num < 0)) && { echo ""; return; }
  local size=$(get_reg_size "$reg_name")
  local w_flag=$((size == 8 ? 1 : 0))
  local r_bit=$(((reg_num >> 3) & 1))
  local b_bit=$(((base_num >> 3) & 1))
  local w_bit=$((w_flag & 1))
  local rex=$((0x40 | (w_bit << 3) | (r_bit << 2) | b_bit))
  if ((rex == 0x40)); then
    echo ""
  else
    printf "%02x" "$rex"
  fi
}

build_mod_rm() {
  local mod=$1 reg=$2 rm=$3
  echo $(((mod & 3) * 64 + (reg & 7) * 8 + (rm & 7)))
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
      if ((disp >= -128 && disp <= 127)); then
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
      if ((disp >= -128 && disp <= 127)); then
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
  elif [[ "$arg" =~ ^\[([^]]+)\],[[:space:]]+([er][a-z]{2}|r[89]|r1[0-5])$ ]]; then
    # [mem], reg
    local mem="${BASH_REMATCH[1]}"
    local cm2_reg="${BASH_REMATCH[2]}"
    local cm2_size=$(calc_mem_operand_size "$mem")
    local cm2_rex=$(get_rex_for_reg "$cm2_reg")
    [[ -z "$cm2_rex" ]] && cm2_size=$((cm2_size - 1))
    text_bytes_len=$((text_bytes_len + cm2_size))
  elif [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^-?[0-9]+$ ]] || [[ "$arg" =~ ^0x[0-9a-fA-F]+$ ]] || [[ -n "${equs[$arg]:-}" ]]; then
    if ((dreg_num >= 0 && $(get_reg_size "$dest_reg") == 1)); then
      text_bytes_len=$((text_bytes_len + 2))
    elif ((dreg_num >= 0 && $(get_reg_size "$dest_reg") == 4)); then
      text_bytes_len=$((text_bytes_len + 5))
    else
      if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
        val=$((16#${BASH_REMATCH[1]}))
      elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
        val=$((arg))
      elif [[ -n "${equs[$arg]:-}" ]]; then
        val=${equs[$arg]}
      fi
      if ((val >= -2147483648 && val <= 2147483647)); then
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
    # rax has dedicated opcode (25/3d) + imm32, no imm8 form
    text_bytes_len=$((text_bytes_len + 5 + ${#ar_rex} / 2))
  else
    # Check if imm8 is sufficient
    local arv=0
    if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
      arv=$((16#${BASH_REMATCH[1]}))
    elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
      arv=$((arg))
    fi
    if ((arv >= -128 && arv <= 127)); then
      # 83 /0 ib (3 bytes) + REX
      text_bytes_len=$((text_bytes_len + 3 + ${#ar_rex} / 2))
    else
      # 81 /0 id (6 bytes) + REX
      text_bytes_len=$((text_bytes_len + 6 + ${#ar_rex} / 2))
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

  IFS=' ' read -r mnemonic op1 op2 op3 <<<"$line"

  mnemonic=$(trim_string "$mnemonic")
  op1=$(trim_string "$op1")
  op2=$(trim_string "$op2")
  op3=$(trim_string "$op3")
  echo "$mnemonic|$op1|$op2|$op3"
}
