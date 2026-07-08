#!/usr/bin/env bash

basm_assemble() {
  local code_str="${1:-""]}"
  local outfile="${2:-a.out}"
  local mode="${3:-exe}"
  local preprocessed_code
  if command -v preprocess_macros >/dev/null 2>&1; then
    preprocessed_code=$(preprocess_macros "$code_str" 2>/dev/null)
    if [[ $? -eq 0 && -n "$preprocessed_code" ]]; then
      code_str="$preprocessed_code"
    fi
  fi
  set_assembly_mode "$mode"
  if [[ "$mode" == "obj" ]]; then
    base_vaddr=0
    file_text_off=0
    text_vaddr=0
    data_vaddr=0
    entry_vaddr=0
  else
    base_vaddr=0x400000
    file_text_off=0x200
    text_vaddr=$((base_vaddr + file_text_off))
    entry_vaddr=$text_vaddr
  fi
  local lines
  if ! first_pass lines "$code_str"; then
    return 1
  fi
  code_size=$text_bytes_len
  data_size=$((${#data_bytes} / 2))
  rodata_size=$((${#rodata_bytes} / 2))
  bss_size=$bss_bytes_len
  file_data_off=$((file_text_off + code_size))
  file_rodata_off=$((file_data_off + data_size))
  file_bss_off=$((file_rodata_off + rodata_size))
  if [[ "$mode" != "obj" ]]; then
    data_vaddr=$((base_vaddr + file_text_off + code_size))
    if [[ -n "${labels[_start]:-}" ]]; then
      entry_vaddr=$((text_vaddr + labels[_start]))
    fi
  fi
  if ! second_pass text_ins; then
    return 1
  fi

  # always generate ELF object first, then link for executable mode
  if [[ "$mode" == "obj" ]]; then
    generate_elf_object_with_symbols "$text_hex" "$data_bytes" "labels" "equs" "$outfile" "data_label_off" "relocations" "externals" "$mode" "$rodata_bytes" "rodata_label_off"
  else
    local tmp_obj
    tmp_obj="$(_basm_tempfile .o .)" || {
      error_msg "failed to create temp object"
      return 1
    }
    generate_elf_object_with_symbols "$text_hex" "$data_bytes" "labels" "equs" "$tmp_obj" "data_label_off" "relocations" "externals" "obj" "$rodata_bytes" "rodata_label_off" "$bss_bytes_len" "bss_label_off"

    # Build runtime objects if needed
    local lib_o="$_BASM_LIB/libc.o"
    local crt_o="$_BASM_LIB/crt.o"
    if [[ ! -f "$lib_o" ]]; then
      bash "$_BASM_LIB/../src/basm.sh" "$_BASM_LIB/libc.asm" "$lib_o" obj 2>/dev/null
    fi
    if [[ ! -f "$crt_o" ]]; then
      bash "$_BASM_LIB/../src/basm.sh" "$_BASM_LIB/crt.asm" "$crt_o" obj 2>/dev/null
    fi

    # Link with runtime objects
    local has_start=0
    [[ -n "${labels[_start]:-}" ]] && has_start=1

    if ((has_start)); then
      link_objects "$tmp_obj" "$lib_o" "$outfile"
    else
      link_objects "$crt_o" "$tmp_obj" "$lib_o" "$outfile"
    fi
    local rc=$?
    "$_BASM_TOOLS/unlink" "$tmp_obj" 2>/dev/null
    return $rc
  fi
  return 0
}
