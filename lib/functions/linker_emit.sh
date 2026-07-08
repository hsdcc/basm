#!/usr/bin/env bash

# Phase 5: write final executable with three PT_LOAD segments
#   segment 1: text (r-x, PF_R|PF_X=5)
#   segment 2: rodata (r--, PF_R=4)
#   segment 3: data+bss (rw-, PF_R|PF_W=6)
# Since base_vaddr=0x400000 is page-aligned and all vaddrs are
# base + file_offset, congruence holds automatically.
linker_emit() {
  local -n ctx="$1"
  local out="${ctx[output]:-a.out}"

  local texth="${ctx[section_text_combined_hex]:-}"
  local datah="${ctx[section_data_combined_hex]:-}"
  local rh="${ctx[section_rodata_combined_hex]:-}"
  local bss_sz="${ctx[total_bss_size]:-0}"

  local text_sz=$((${#texth} / 2))
  local data_sz=$((${#datah} / 2))
  local ro_sz=$((${#rh} / 2))

  local a_t="${ctx[aligned_text_size]:-$text_sz}"
  local a_d="${ctx[aligned_data_size]:-$data_sz}"
  local a_r="${ctx[aligned_rodata_size]:-$ro_sz}"

  local f_off_t="${ctx[file_text_off]:-0x200}"
  local f_off_d="${ctx[file_data_off]:-0}"

  local vaddr_t="${ctx[text_vaddr]:-0}"
  local vaddr_d="${ctx[data_vaddr]:-0}"
  local entry="${ctx[entry_vaddr]:-$vaddr_t}"

  local rodata_vaddr="${ctx[rodata_vaddr]:-0}"
  local file_rodata_off="${ctx[file_rodata_off]:-0}"
  local rodata_filesz=$a_r

  # segment sizes
  local text_filesz=$a_t
  local data_filesz=$a_d
  local data_memsz=$((data_filesz + bss_sz))

  # build ELF header with three PT_LOAD segments
  local hdr
  hdr=$(build_elf_header "$entry" \
    "$f_off_t" "$vaddr_t" "$a_t" \
    "$vaddr_d" "$f_off_d" "$data_filesz" "$data_memsz" \
    "$rodata_vaddr" "$file_rodata_off" "$rodata_filesz")

  local tmpf
  tmpf="$(_basm_tempfile "" "$(dirname "$out")")" || {
    ctx[error]="failed to create temp file"
    return 1
  }

  hex_to_bin "$hdr" >"$tmpf" || {
    "$_BASM_TOOLS/unlink" "$tmpf" 2>/dev/null
    ctx[error]="header write failed"
    return 1
  }

  local hdr_sz=$((${#hdr} / 2))
  if ((hdr_sz > f_off_t)); then
    "$_BASM_TOOLS/unlink" "$tmpf" 2>/dev/null
    ctx[error]="header too big ($hdr_sz > $f_off_t)"
    return 1
  fi
  generate_zeros $((f_off_t - hdr_sz)) >>"$tmpf"

  [[ -n "$texth" ]] && hex_to_bin "$texth" >>"$tmpf"
  local tpad=$((a_t - text_sz))
  ((tpad > 0)) && generate_zeros "$tpad" >>"$tmpf"

  local after_text=$((f_off_t + a_t))
  if ((f_off_d > after_text)); then
    generate_zeros $((f_off_d - after_text)) >>"$tmpf"
  fi

  [[ -n "$datah" ]] && hex_to_bin "$datah" >>"$tmpf"
  local dpad=$((a_d - data_sz))
  ((dpad > 0)) && generate_zeros "$dpad" >>"$tmpf"

  [[ -n "$rh" ]] && hex_to_bin "$rh" >>"$tmpf"
  local rpad=$((a_r - ro_sz))
  ((rpad > 0)) && generate_zeros "$rpad" >>"$tmpf"

  "$_BASM_TOOLS/chmod" "$tmpf" 493 2>/dev/null
  "$_BASM_TOOLS/rename" "$tmpf" "$out" 2>/dev/null || {
    "$_BASM_TOOLS/unlink" "$tmpf" 2>/dev/null
    ctx[error]="failed to write $out"
    return 1
  }

  return 0
}
