#!/usr/bin/env bash
# basm.sh
# tiny assembler+linker for intel x86_64 linux
set -eu

prog="$0"
infile="${1:-}"
outfile="${2:-a.out}"

if [ "$infile" = "test" ]; then
  echo "running tests"
  test_dir="tests"
  failed_tests=0
  for test_file in "$test_dir"/*.asm; do
    if [ ! -f "$test_file" ]; then
      continue
    fi
    test_name=$(basename "$test_file" .asm)
    executable="$test_dir/$test_name"
    echo "  testing $test_name"

    expected_exit_code=0
    if grep -q '; expect:' "$test_file"; then
      expected_exit_code=$(grep '; expect:' "$test_file" | head -n 1 | awk '{print $3}')
    fi

    # Assemble the test file
    if ! bash "$prog" "$test_file" "$executable"; then
      echo "  [FAIL] $test_name: asm failed."
      failed_tests=$((failed_tests + 1))
      continue
    fi

    # Run the executable
    set +e
    "$executable"
    actual_exit_code=$?
    set -e
    if [ "$actual_exit_code" -ne "$expected_exit_code" ]; then
      echo "  [FAIL] $test_name: Exited with status code $actual_exit_code, expected $expected_exit_code."
      failed_tests=$((failed_tests + 1))
      echo "         executable kept at $executable"
      continue
    fi

    echo "  [PASS] $test_name"
    rm -f "$executable"
  done

  if [ "$failed_tests" -gt 0 ]; then
    echo
    echo "$failed_tests test(s) failed."
    exit 1
  else
    echo
    echo "all tests passed. good job."
    exit 0
  fi
fi

if [ -z "$infile" ]; then
  echo "usage: $prog input.asm output" >&2
  exit 1
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

mapfile -t lines < <(sed 's/\r$//' "$infile")

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
        exit 1
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
      txt="$(echo -n "$txt" | sed -e 's/\\/\\\x5c/g' -e 's/\n/\
/g' -e 's/\"/"/g')"
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
    exit 1
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
      if [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^0x[0-9a-fA-F]+$ ]] || [[ -n "${equs[$arg]:-}" ]]; then
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
    elif [[ "$line" =~ ^push[[:space:]]+rax$ ]]; then
      text_bytes_len=$((text_bytes_len + 1))
    elif [[ "$line" =~ ^pop[[:space:]]+rdi$ ]]; then
      text_bytes_len=$((text_bytes_len + 1))
    elif [[ "$line" =~ ^(add|sub|cmp)[[:space:]]+rax,.*$ ]]; then
      if [[ "$line" =~ ^cmp.*$ ]]; then
        text_bytes_len=$((text_bytes_len + 6))
      else
        text_bytes_len=$((text_bytes_len + 7))
      fi
    elif [[ "$line" =~ ^(j|J) ]]; then
      text_bytes_len=$((text_bytes_len + 2))
    else
      echo "unsupported instruction: $line" >&2
      exit 1
    fi
  else
    echo "no section for: $line" >&2
    exit 1
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
  elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$ ]]; then
    reg="${BASH_REMATCH[1]}"
    arg="${BASH_REMATCH[2]}"
    if [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^0x[0-9a-fA-F]+$ ]] || [[ -n "${equs[$arg]:-}" ]]; then
      if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
        val=$((16#${BASH_REMATCH[1]}))
      elif [[ "$arg" =~ ^[0-9]+$ ]]; then
        val=$((arg))
      elif [[ -n "${equs[$arg]:-}" ]]; then
        val=${equs[$arg]}
      fi
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
        exit 1
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
  elif [[ "$line" =~ ^push[[:space:]]+rax$ ]]; then
    text_hex+="50"
    current_address=$((current_address + 1))
  elif [[ "$line" =~ ^pop[[:space:]]+rdi$ ]]; then
    text_hex+="5f"
    current_address=$((current_address + 1))
  elif [[ "$line" =~ ^(add|sub|cmp)[[:space:]]+rax,[[:space:]]*(.*)$ ]]; then
    op="${BASH_REMATCH[1]}"
    arg="${BASH_REMATCH[2]}"
    if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
      val=$((16#${BASH_REMATCH[1]}))
    elif [[ "$arg" =~ ^[0-9]+$ ]]; then
      val=$((arg))
    else
      echo "unknown immediate $arg" >&2
      exit 1
    fi
    case "$op" in
      add) text_hex+="4881c0$(u32le $val)"; current_address=$((current_address + 7)) ;; 
      sub) text_hex+="4881e8$(u32le $val)"; current_address=$((current_address + 7)) ;; 
      cmp) text_hex+="483d$(u32le $val)"; current_address=$((current_address + 6)) ;; 
    esac
  elif [[ "$line" =~ ^(je|jne|jg|jl|jge|jle|jmp)[[:space:]]+(.*)$ ]]; then
    op="${BASH_REMATCH[1]}"
    lbl="${BASH_REMATCH[2]}"
    if [[ -z "${labels[$lbl]:-}" ]]; then
      echo "unknown label $lbl" >&2
      exit 1
    fi
    target_address=${labels[$lbl]}
    offset=$((target_address - (current_address + 2)))
    if [ $offset -lt -128 ] || [ $offset -gt 127 ]; then
      echo "short jump out of range: $offset" >&2
      exit 1
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
  else
    echo "internal error assembling: $line" >&2
    exit 1
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
  exit 1
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
echo "wrote $outfile"