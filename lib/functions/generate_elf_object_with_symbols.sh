#!/usr/bin/env bash

# reverse hex string
reverse_endian() {
  local hex="$1"
  local len=${#hex}
  local reversed=""
  ((len % 2 != 0)) && {
    hex="0$hex"
    len=$((len + 1))
  }
  for ((i = len - 2; i >= 0; i -= 2)); do
    reversed+="${hex:$i:2}"
  done
  echo "$reversed"
}

generate_elf_object_with_symbols() {
  local text_hex="$1"
  local data_bytes="$2"
  local labels_ref="$3"
  local equs_ref="$4"
  local outfile="$5"
  local data_labels_ref="$6"
  local relocations_ref="$7"
  local externals_ref="$8"
  local mode="${9:-obj}"
  local rodata_hex="${10:-}"
  local rodata_labels_ref="${11:-}"
  local bss_size="${12:-0}"
  local bss_labels_ref="${13:-}"
  local -n labels_n="$3"
  local -n equs_n="$4"
  local -n data_labels_n="$6"
  local -n relocations_n="$7"
  local -n externals_n="$8"
  local -A _empty_rodata_labels
  local -n rodata_labels_n="${11:-_empty_rodata_labels}"
  local -A _empty_bss_labels
  local -n bss_labels_n="${13:-_empty_bss_labels}"
  local text_size=$((${#text_hex} / 2))
  local data_size=$((${#data_bytes} / 2))
  local rodata_size=$((${#rodata_hex} / 2))
  local total_sections=7
  local header_size=64
  local text_section_off=$header_size
  local data_section_off=$((text_section_off + text_size))
  local rela_hex=""
  if [[ ${#relocations_n[@]} -gt 0 ]]; then
    generate_relocation_section "relocations_n" "labels_n" "data_labels_n" "rodata_labels_n" "externals_n" "bss_labels_n" "rela_hex"
  fi
  local rela_size=$((${#rela_hex} / 2))
  local total_sections=8
  [[ $rela_size -gt 0 ]] && total_sections=9
  # build strtab with ordered iteration for deterministic offsets
  local -a _sym_names=()
  local -a _sym_shndx=()
  local -a _sym_vals=()
  for label_name in "${!labels_n[@]}"; do
    _sym_names+=("$label_name")
    _sym_shndx+=(1)
    _sym_vals+=("${labels_n[$label_name]}")
  done
  for label_name in "${!data_labels_n[@]}"; do
    _sym_names+=("$label_name")
    _sym_shndx+=(2)
    _sym_vals+=("${data_labels_n[$label_name]}")
  done
  for label_name in "${!rodata_labels_n[@]}"; do
    _sym_names+=("$label_name")
    _sym_shndx+=(3)
    _sym_vals+=("${rodata_labels_n[$label_name]}")
  done
  for label_name in "${!bss_labels_n[@]}"; do
    _sym_names+=("$label_name")
    _sym_shndx+=(4)
    _sym_vals+=("${bss_labels_n[$label_name]}")
  done
  for ext_name in "${!externals_n[@]}"; do
    _sym_names+=("$ext_name")
    _sym_shndx+=(0)
    _sym_vals+=(0)
  done
  local -A _str_offsets=()
  local symstrtab_hex="00"
  local current_str_offset=1
  local _si
  for ((_si = 0; _si < ${#_sym_names[@]}; _si++)); do
    local _nm="${_sym_names[$_si]}"
    _str_offsets["$_nm"]=$current_str_offset
    for ((ci = 0; ci < ${#_nm}; ci++)); do
      local ch="${_nm:$ci:1}"
      symstrtab_hex+=$(printf "%02x" "'$ch")
    done
    symstrtab_hex+="00"
    current_str_offset=$((current_str_offset + ${#_nm} + 1))
  done
  local symstrtab_size=$((${#symstrtab_hex} / 2))
  local num_symbols=$((1 + ${#_sym_names[@]}))
  local symtab_size=$((num_symbols * 24))
  local shstrtab_hex="002e74657874002e64617461002e726f64617461002e627373002e7368737472746162002e73796d746162002e737472746162002e72656c612e7465787400"
  local shstrtab_size=$((${#shstrtab_hex} / 2))
  local rodata_off=$((data_section_off + data_size))
  local strtab_off=$((rodata_off + rodata_size))
  local symtab_off=$((strtab_off + symstrtab_size))
  local rela_off=$((symtab_off + symtab_size))
  local sec_header_table_off=$((rela_off + rela_size))
  local elf_header=""
  elf_header="7f454c46"
  elf_header+="02"
  elf_header+="01"
  elf_header+="01"
  elf_header+="00"
  elf_header+="00"
  elf_header+="00000000000000"
  case "$mode" in
    obj) elf_header+="0100" ;;
    *) elf_header+="0200" ;;
  esac
  elf_header+="3e00"
  elf_header+="01000000"
  elf_header+="0000000000000000"
  elf_header+="0000000000000000"
  local shoff_hex=$(printf "%016x" $sec_header_table_off)
  elf_header+=$(reverse_endian "$shoff_hex")
  elf_header+="00000000"
  elf_header+="4000"
  elf_header+="0000"
  elf_header+="0000"
  elf_header+="4000"
  local shnum_hex=$(printf "%04x" $total_sections)
  elf_header+=$(reverse_endian "$shnum_hex")
  local shstrndx_hex=$(printf "%04x" 5)
  elf_header+=$(reverse_endian "$shstrndx_hex")
  # build symtab using ordered _sym_names arrays
  local symtab_content=""
  for ((i = 0; i < 24; i++)); do
    symtab_content+="00"
  done
  local _si2
  for ((_si2 = 0; _si2 < ${#_sym_names[@]}; _si2++)); do
    local nm="${_sym_names[$_si2]}"
    local shndx="${_sym_shndx[$_si2]}"
    local val="${_sym_vals[$_si2]}"
    local stroff=${_str_offsets["$nm"]}
    local st_name_hex=$(printf "%08x" $stroff)
    symtab_content+=$(reverse_endian "$st_name_hex")
    symtab_content+="10"
    symtab_content+="00"
    local shndx_hex=$(printf "%04x" $shndx)
    symtab_content+=$(reverse_endian "$shndx_hex")
    if ((shndx > 0)); then
      local value_hex=$(printf "%016x" $val)
      symtab_content+=$(reverse_endian "$value_hex")
    else
      symtab_content+="0000000000000000"
    fi
    symtab_content+="0000000000000000"
  done
  # build section headers
  local section_headers=""
  for ((i = 0; i < 64; i++)); do
    section_headers+="00"
  done
  local sh_name_hex=$(printf "%08x" 1)
  section_headers+=$(reverse_endian "$sh_name_hex")
  section_headers+="01000000"
  local sh_flags_hex=$(printf "%016x" $((0x6)))
  section_headers+=$(reverse_endian "$sh_flags_hex")
  section_headers+="0000000000000000"
  local sh_offset_hex=$(printf "%016x" $text_section_off)
  section_headers+=$(reverse_endian "$sh_offset_hex")
  local sh_size_hex=$(printf "%016x" $text_size)
  section_headers+=$(reverse_endian "$sh_size_hex")
  section_headers+="00000000"
  section_headers+="00000000"
  local sh_addralign_hex=$(printf "%016x" 16)
  section_headers+=$(reverse_endian "$sh_addralign_hex")
  section_headers+="0000000000000000"
  sh_name_hex=$(printf "%08x" 7)
  section_headers+=$(reverse_endian "$sh_name_hex")
  section_headers+="01000000"
  sh_flags_hex=$(printf "%016x" $((0x3)))
  section_headers+=$(reverse_endian "$sh_flags_hex")
  section_headers+="0000000000000000"
  sh_offset_hex=$(printf "%016x" $data_section_off)
  section_headers+=$(reverse_endian "$sh_offset_hex")
  sh_size_hex=$(printf "%016x" $data_size)
  section_headers+=$(reverse_endian "$sh_size_hex")
  section_headers+="00000000"
  section_headers+="00000000"
  sh_addralign_hex=$(printf "%016x" 8)
  section_headers+=$(reverse_endian "$sh_addralign_hex")
  section_headers+="0000000000000000"
  # Section 3: .rodata
  sh_name_hex=$(printf "%08x" 13)
  section_headers+=$(reverse_endian "$sh_name_hex")
  section_headers+="01000000"
  sh_flags_hex=$(printf "%016x" $((0x2)))
  section_headers+=$(reverse_endian "$sh_flags_hex")
  section_headers+="0000000000000000"
  local rodata_file_off=$rodata_off
  if ((rodata_size == 0)); then rodata_file_off=0; fi
  sh_offset_hex=$(printf "%016x" $rodata_file_off)
  section_headers+=$(reverse_endian "$sh_offset_hex")
  sh_size_hex=$(printf "%016x" $rodata_size)
  section_headers+=$(reverse_endian "$sh_size_hex")
  section_headers+="00000000"
  section_headers+="00000000"
  sh_addralign_hex=$(printf "%016x" 8)
  section_headers+=$(reverse_endian "$sh_addralign_hex")
  section_headers+="0000000000000000"
  # Section 4: .bss
  sh_name_hex=$(printf "%08x" 21)
  section_headers+=$(reverse_endian "$sh_name_hex")
  section_headers+="08000000"
  sh_flags_hex=$(printf "%016x" $((0x3)))
  section_headers+=$(reverse_endian "$sh_flags_hex")
  section_headers+="0000000000000000"
  sh_offset_hex=$(printf "%016x" 0)
  section_headers+=$(reverse_endian "$sh_offset_hex")
  sh_size_hex=$(printf "%016x" $bss_size)
  section_headers+=$(reverse_endian "$sh_size_hex")
  section_headers+="00000000"
  section_headers+="00000000"
  sh_addralign_hex=$(printf "%016x" 16)
  section_headers+=$(reverse_endian "$sh_addralign_hex")
  section_headers+="0000000000000000"
  # Section 5: .shstrtab
  sh_name_hex=$(printf "%08x" 26)
  section_headers+=$(reverse_endian "$sh_name_hex")
  section_headers+="03000000"
  sh_flags_hex=$(printf "%016x" 0)
  section_headers+=$(reverse_endian "$sh_flags_hex")
  section_headers+="0000000000000000"
  local shstrtab_actual_off=$((sec_header_table_off + (total_sections * 64)))
  sh_offset_hex=$(printf "%016x" $shstrtab_actual_off)
  section_headers+=$(reverse_endian "$sh_offset_hex")
  sh_size_hex=$(printf "%016x" $shstrtab_size)
  section_headers+=$(reverse_endian "$sh_size_hex")
  section_headers+="00000000"
  section_headers+="00000000"
  sh_addralign_hex=$(printf "%016x" 1)
  section_headers+=$(reverse_endian "$sh_addralign_hex")
  section_headers+="0000000000000000"
  # Section 6: .symtab
  sh_name_hex=$(printf "%08x" 36)
  section_headers+=$(reverse_endian "$sh_name_hex")
  section_headers+="02000000"
  sh_flags_hex=$(printf "%016x" 0)
  section_headers+=$(reverse_endian "$sh_flags_hex")
  section_headers+="0000000000000000"
  sh_offset_hex=$(printf "%016x" $symtab_off)
  section_headers+=$(reverse_endian "$sh_offset_hex")
  sh_size_hex=$(printf "%016x" $symtab_size)
  section_headers+=$(reverse_endian "$sh_size_hex")
  local link_idx_hex=$(printf "%08x" 7)
  section_headers+=$(reverse_endian "$link_idx_hex")
  local sh_info_hex=$(printf "%08x" 1)
  section_headers+=$(reverse_endian "$sh_info_hex")
  sh_addralign_hex=$(printf "%016x" 8)
  section_headers+=$(reverse_endian "$sh_addralign_hex")
  local entsize_hex=$(printf "%016x" 24)
  section_headers+=$(reverse_endian "$entsize_hex")
  # Section 7: .strtab
  sh_name_hex=$(printf "%08x" 44)
  section_headers+=$(reverse_endian "$sh_name_hex")
  section_headers+="03000000"
  sh_flags_hex=$(printf "%016x" 0)
  section_headers+=$(reverse_endian "$sh_flags_hex")
  section_headers+="0000000000000000"
  sh_offset_hex=$(printf "%016x" $strtab_off)
  section_headers+=$(reverse_endian "$sh_offset_hex")
  sh_size_hex=$(printf "%016x" $symstrtab_size)
  section_headers+=$(reverse_endian "$sh_size_hex")
  section_headers+="00000000"
  section_headers+="00000000"
  sh_addralign_hex=$(printf "%016x" 1)
  section_headers+=$(reverse_endian "$sh_addralign_hex")
  section_headers+="0000000000000000"
  if [[ $rela_size -gt 0 ]]; then
    # Section 8: .rela.text
    sh_name_hex=$(printf "%08x" 52)
    section_headers+=$(reverse_endian "$sh_name_hex")
    section_headers+="04000000"
    sh_flags_hex=$(printf "%016x" 0)
    section_headers+=$(reverse_endian "$sh_flags_hex")
    section_headers+="0000000000000000"
    sh_offset_hex=$(printf "%016x" $rela_off)
    section_headers+=$(reverse_endian "$sh_offset_hex")
    sh_size_hex=$(printf "%016x" $rela_size)
    section_headers+=$(reverse_endian "$sh_size_hex")
    local rela_link_hex=$(printf "%08x" 6)
    section_headers+=$(reverse_endian "$rela_link_hex")
    local rela_info_hex=$(printf "%08x" 1)
    section_headers+=$(reverse_endian "$rela_info_hex")
    sh_addralign_hex=$(printf "%016x" 8)
    section_headers+=$(reverse_endian "$sh_addralign_hex")
    local rela_entsize_hex=$(printf "%016x" 24)
    section_headers+=$(reverse_endian "$rela_entsize_hex")
  fi
  local tmpf
  tmpf="$(_basm_tempfile "" "$(dirname "$outfile")")" || {
    error_msg "failed to create temporary file"
    return 1
  }
  hex_to_bin "$elf_header" >"$tmpf"
  hex_to_bin "$text_hex" >>"$tmpf"
  hex_to_bin "$data_bytes" >>"$tmpf"
  [[ -n "$rodata_hex" ]] && hex_to_bin "$rodata_hex" >>"$tmpf"
  hex_to_bin "$symstrtab_hex" >>"$tmpf"
  hex_to_bin "$symtab_content" >>"$tmpf"
  [[ $rela_size -gt 0 ]] && hex_to_bin "$rela_hex" >>"$tmpf"
  hex_to_bin "$section_headers" >>"$tmpf"
  hex_to_bin "$shstrtab_hex" >>"$tmpf"
  "$_BASM_TOOLS/chmod" "$tmpf" 420 2>/dev/null
  "$_BASM_TOOLS/rename" "$tmpf" "$outfile" 2>/dev/null || {
    "$_BASM_TOOLS/unlink" "$tmpf" 2>/dev/null
    error_msg "failed to write $outfile"
    return 1
  }
  return 0
}
