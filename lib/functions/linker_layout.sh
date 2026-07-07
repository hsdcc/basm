#!/usr/bin/env bash

# Phase 2: assign file offsets and virtual addresses with alignment
linker_layout() {
  local -n ctx="$1"
  local n="${ctx[num_objects]:-0}"
  (( n > 0 )) || { ctx[error]="no objects"; return 1; }

  # align helper
  _ll_align() { echo $(( (($1) + ($2) - 1) / ($2) * ($2) )); }

  # combine sections and track per-object offsets
  local comb_t="" comb_d="" comb_r=""
  local total_t=0 total_d=0 total_r=0 total_b=0
  local cur_to=0 cur_do=0 cur_ro=0 cur_bo=0

  local i
  for ((i = 0; i < n; i++)); do
    ctx["obj_${i}_text_off"]=$cur_to
    ctx["obj_${i}_data_off"]=$cur_do
    ctx["obj_${i}_rodata_off"]=$cur_ro

    local th="${ctx[obj_${i}_text_hex]:-}"
    local dh="${ctx[obj_${i}_data_hex]:-}"
    local rh="${ctx[obj_${i}_rodata_hex]:-}"
    local bs="${ctx[obj_${i}_bss_size]:-0}"

    local ts=$(( ${#th} / 2 ))
    local ds=$(( ${#dh} / 2 ))
    local rs=$(( ${#rh} / 2 ))

    comb_t+="$th"
    comb_d+="$dh"
    comb_r+="$rh"

    cur_to=$((cur_to + ts))
    cur_do=$((cur_do + ds))
    cur_ro=$((cur_ro + rs))
    cur_bo=$((cur_bo + bs))

    total_t=$((total_t + ts))
    total_d=$((total_d + ds))
    total_r=$((total_r + rs))
    total_b=$((total_b + bs))
  done

  # align
  local a_t=$(_ll_align "$total_t" 16)
  local a_d=$(_ll_align "$total_d" 8)
  local a_r=$(_ll_align "$total_r" 8)
  local a_b=$(_ll_align "$total_b" 16)

  # file offsets (data segment page-aligned to avoid page overlap with text)
  local page=4096
  local f_off_t=$((0x200))
  local f_off_d=$(( (f_off_t + a_t + page - 1) / page * page ))
  local f_off_r=$((f_off_d + a_d))
  local f_off_b=$((f_off_r + a_r))

  # virtual addresses
  local base=$((0x400000))
  local vaddr_t=$((base + f_off_t))
  local vaddr_d=$((base + f_off_d))
  local vaddr_r=$((base + f_off_r))
  local vaddr_b=$((base + f_off_b))

  ctx[section_text_combined_hex]="$comb_t"
  ctx[section_data_combined_hex]="$comb_d"
  ctx[section_rodata_combined_hex]="$comb_r"
  ctx[total_bss_size]=$total_b

  ctx[total_text_size]=$total_t
  ctx[total_data_size]=$total_d
  ctx[total_rodata_size]=$total_r

  ctx[aligned_text_size]=$a_t
  ctx[aligned_data_size]=$a_d
  ctx[aligned_rodata_size]=$a_r
  ctx[aligned_bss_size]=$a_b

  ctx[file_text_off]=$f_off_t
  ctx[file_data_off]=$f_off_d
  ctx[file_rodata_off]=$f_off_r
  ctx[file_bss_off]=$f_off_b

  ctx[text_vaddr]=$vaddr_t
  ctx[data_vaddr]=$vaddr_d
  ctx[rodata_vaddr]=$vaddr_r
  ctx[bss_vaddr]=$vaddr_b
  ctx[entry_vaddr]=$vaddr_t

  return 0
}
