#!/usr/bin/env bash

_READELF_HEX=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _READELF_DIR="$(cd "$(_basm_dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null)"
  _READELF_HEX="$_READELF_DIR/tools/readelf_hex"
  unset _READELF_DIR
fi

read_file_hex() {
  local file_path="$1"
  local skip_bytes="$2"
  local count_bytes="$3"
  local -n _rfh_output="$4"
  _rfh_output=""
  if [[ ! -f "$file_path" ]]; then
    error_msg "file not found: $file_path"
    return 1
  fi
  if [[ $count_bytes -eq 0 ]]; then
    return 0
  fi
  if [[ ! -x "$_READELF_HEX" ]]; then
    error_msg "readelf_hex tool not found at $_READELF_HEX"
    return 1
  fi
  _rfh_output=$("$_READELF_HEX" "$file_path" "$skip_bytes" "$count_bytes") || return $?
}

read_string_at() {
  local file_path="$1"
  local offset="$2"
  local output_ref="$3"
  local -n _rsa_output="$3"
  local hex_data
  read_file_hex "$file_path" "$offset" 256 "hex_data"
  local result=""
  local pos=0
  while ((pos + 1 < ${#hex_data})); do
    local byte_hex="${hex_data:$pos:2}"
    [[ "$byte_hex" == "00" ]] && break
    local byte_val=$((16#$byte_hex))
    ((byte_val >= 32 && byte_val < 127)) && result+=$(printf "\\$(printf '%03o' "$byte_val")")
    pos=$((pos + 2))
  done
  _rsa_output="$result"
  return 0
}

hex_to_dec() {
  local hex="$1"
  local result=0
  local pos=0
  for ((pos = 0; pos < ${#hex}; pos++)); do
    local digit="${hex:$pos:1}"
    case "$digit" in
      a | A) digit=10 ;;
      b | B) digit=11 ;;
      c | C) digit=12 ;;
      d | D) digit=13 ;;
      e | E) digit=14 ;;
      f | F) digit=15 ;;
    esac
    result=$((result * 16 + digit))
  done
  echo "$result"
}

read_u32le() {
  local file_path="$1"
  local offset="$2"
  local output_ref="$3"
  local -n _ru_output="$3"
  local hex_data
  read_file_hex "$file_path" "$offset" 4 "hex_data"
  local reversed="${hex_data:6:2}${hex_data:4:2}${hex_data:2:2}${hex_data:0:2}"
  _ru_output=$(hex_to_dec "$reversed")
  return 0
}

read_u64le() {
  local file_path="$1"
  local offset="$2"
  local output_ref="$3"
  local -n _ru64_output="$3"
  local hex_data
  read_file_hex "$file_path" "$offset" 8 "hex_data"
  local reversed=""
  for ((i = 14; i >= 0; i -= 2)); do
    reversed+="${hex_data:$i:2}"
  done
  _ru64_output=$(hex_to_dec "$reversed")
  return 0
}

read_u16le() {
  local file_path="$1"
  local offset="$2"
  local output_ref="$3"
  local -n _ru16_output="$3"
  local hex_data
  read_file_hex "$file_path" "$offset" 2 "hex_data"
  local reversed="${hex_data:2:2}${hex_data:0:2}"
  _ru16_output=$(hex_to_dec "$reversed")
  return 0
}
