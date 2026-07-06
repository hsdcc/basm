#!/usr/bin/env bash

# Phase 5: write final executable
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
  local f_off_r="${ctx[file_rodata_off]:-0}"
  local f_off_b="${ctx[file_bss_off]:-0}"

  local vaddr_t="${ctx[text_vaddr]:-0}"
  local entry="${ctx[entry_vaddr]:-$vaddr_t}"

  # build ELF header
  local hdr
  hdr=$(build_elf_header "$entry" "$f_off_t" "$vaddr_t" "$a_d" "$f_off_d")

  # create temp file
  local tmpf
  tmpf="$(mktemp)" || { ctx[error]="failed to create temp file"; return 1; }

  # write header
  hex_to_bin "$hdr" > "$tmpf" || { rm -f "$tmpf"; ctx[error]="header write failed"; return 1; }

  # pad to text offset
  local hdr_sz=$(( ${#hdr} / 2 ))
  if (( hdr_sz > f_off_t )); then
    rm -f "$tmpf"; ctx[error]="header too big ($hdr_sz > $f_off_t)"; return 1
  fi
  generate_zeros $((f_off_t - hdr_sz)) >> "$tmpf"

  # write .text + alignment pad
  [[ -n "$texth" ]] && hex_to_bin "$texth" >> "$tmpf"
  local tpad=$((a_t - text_sz))
  (( tpad > 0 )) && generate_zeros "$tpad" >> "$tmpf"

  # write .data + alignment pad
  [[ -n "$datah" ]] && hex_to_bin "$datah" >> "$tmpf"
  local dpad=$((a_d - data_sz))
  (( dpad > 0 )) && generate_zeros "$dpad" >> "$tmpf"

  # write .rodata + alignment pad
  [[ -n "$rh" ]] && hex_to_bin "$rh" >> "$tmpf"
  local rpad=$((a_r - ro_sz))
  (( rpad > 0 )) && generate_zeros "$rpad" >> "$tmpf"

  # write BSS (zeros)
  (( bss_sz > 0 )) && generate_zeros "$bss_sz" >> "$tmpf"

  # patch p_filesz/p_memsz if the header doesn't match actual written size
  local actual_filesz=$((f_off_r + ro_sz))
  local actual_memsz=$((actual_filesz + bss_sz))
  local hdr_filesz=$((f_off_d + a_d))

  if (( actual_filesz != hdr_filesz )); then
    local seek=$((0x38))
    local pd="$(u64le "$actual_filesz")$(u64le "$actual_memsz")"
    local tb
    tb="$(mktemp)" || { rm -f "$tmpf"; ctx[error]="temp patch failed"; return 1; }
    hex_to_bin "$pd" > "$tb"
    write_at_offset "$tb" "$tmpf" "$seek"
    rm -f "$tb"
  fi

  chmod +x "$tmpf" && mv -f "$tmpf" "$out" || {
    rm -f "$tmpf"; ctx[error]="failed to write $out"; return 1
  }

  return 0
}
