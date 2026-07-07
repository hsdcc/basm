#!/usr/bin/env bash

# Phase 5: write final executable with two PT_LOAD segments
#   segment 1: text (r-x, PF_R|PF_X=5)
#   segment 2: data+rodata+bss (rw-, PF_R|PF_W=6)
# Since base_vaddr=0x400000 is page-aligned and all vaddrs are
# base + file_offset, congruence holds automatically.
linker_emit() {
  local -n ctx="$1"
  local out="${ctx[output]:-a.out}"

  local texth="${ctx[section_text_combined_hex]:-}"
  local datah="${ctx[section_data_combined_hex]:-}"
  local rh="${ctx[section_rodata_combined_hex]:-}"
  local bss_sz="${ctx[total_bss_size]:-0}"

  local text_sz=$(( ${#texth} / 2 ))
  local data_sz=$(( ${#datah} / 2 ))
  local ro_sz=$(( ${#rh} / 2 ))

  local a_t="${ctx[aligned_text_size]:-$text_sz}"
  local a_d="${ctx[aligned_data_size]:-$data_sz}"
  local a_r="${ctx[aligned_rodata_size]:-$ro_sz}"

  local f_off_t="${ctx[file_text_off]:-0x200}"
  local f_off_d="${ctx[file_data_off]:-0}"

  local vaddr_t="${ctx[text_vaddr]:-0}"
  local vaddr_d="${ctx[data_vaddr]:-0}"
  local entry="${ctx[entry_vaddr]:-$vaddr_t}"

  # segment sizes
  local text_filesz=$a_t
  local data_filesz=$((a_d + a_r))
  local data_memsz=$((data_filesz + bss_sz))

  # build ELF header with two PT_LOAD segments
  local hdr
  hdr=$(build_elf_header_multi "$entry" \
        "$f_off_t" "$vaddr_t" "$text_filesz" \
        "$f_off_d" "$vaddr_d" "$data_filesz" "$data_memsz")

  # create temp file
  local tmpf
  tmpf="$(mktemp)" || { ctx[error]="failed to create temp file"; return 1; }

  # write header
  hex_to_bin "$hdr" > "$tmpf" || { rm -f "$tmpf"; ctx[error]="header write failed"; return 1; }

  # pad to text file offset
  local hdr_sz=$(( ${#hdr} / 2 ))
  if (( hdr_sz > f_off_t )); then
    rm -f "$tmpf"; ctx[error]="header too big ($hdr_sz > $f_off_t)"; return 1
  fi
  generate_zeros $((f_off_t - hdr_sz)) >> "$tmpf"

  # write .text (text segment)
  [[ -n "$texth" ]] && hex_to_bin "$texth" >> "$tmpf"
  local tpad=$((a_t - text_sz))
  (( tpad > 0 )) && generate_zeros "$tpad" >> "$tmpf"

  # pad to data segment file offset
  local after_text=$((f_off_t + a_t))
  if (( f_off_d > after_text )); then
    generate_zeros $((f_off_d - after_text)) >> "$tmpf"
  fi

  # write .data + .rodata (data segment)
  [[ -n "$datah" ]] && hex_to_bin "$datah" >> "$tmpf"
  local dpad=$((a_d - data_sz))
  (( dpad > 0 )) && generate_zeros "$dpad" >> "$tmpf"

  [[ -n "$rh" ]] && hex_to_bin "$rh" >> "$tmpf"
  local rpad=$((a_r - ro_sz))
  (( rpad > 0 )) && generate_zeros "$rpad" >> "$tmpf"

  # write BSS (zeros)
  (( bss_sz > 0 )) && generate_zeros "$bss_sz" >> "$tmpf"

  chmod +x "$tmpf" && mv -f "$tmpf" "$out" || {
    rm -f "$tmpf"; ctx[error]="failed to write $out"; return 1
  }

  return 0
}
