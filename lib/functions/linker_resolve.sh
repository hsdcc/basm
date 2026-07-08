#!/usr/bin/env bash

# Phase 3: resolve
linker_resolve() {
  local -n ctx="$1"
  local n="${ctx[num_objects]:-0}"
  (( n > 0 )) || { ctx[error]="no objects"; return 1; }

  local vaddr_t="${ctx[text_vaddr]:-0}"
  local vaddr_d="${ctx[data_vaddr]:-0}"
  local vaddr_r="${ctx[rodata_vaddr]:-0}"
  local vaddr_b="${ctx[bss_vaddr]:-0}"

  # pass 1: collect all definitions and references
  local -A defs=()        # sym -> "obj_idx:shndx:st_value"
  local -A undefs=()      # sym -> 1 if seen as undefined
  local -A def_objs=()    # sym -> obj_idx (for error message)

  local i
  for ((i = 0; i < n; i++)); do
    local symtab="${ctx[obj_${i}_symtab]:-}"
    [[ -z "$symtab" ]] && continue

    IFS=' ' read -ra entries <<< "$symtab"
    local entry
    for entry in "${entries[@]}"; do
      local sym_name="${entry%%:*}"
      local rest="${entry#*:}"
      local shndx="${rest%%:*}"
      local sym_val="${rest#*:}"

      [[ -z "$sym_name" ]] && continue
      # skip purely numeric names
      [[ "$sym_name" =~ ^[0-9]+$ ]] && continue

      if (( shndx > 0 )); then
        # defined — check duplicate
        if [[ -n "${defs[$sym_name]:-}" ]]; then
          ctx[error]="duplicate symbol '$sym_name'"
          return 1
        fi
        defs["$sym_name"]="${i}:${shndx}:${sym_val}"
        def_objs["$sym_name"]=$i
      else
        # undefined reference
        undefs["$sym_name"]=1
      fi
    done
  done

  # pass 2: compute final addresses and check unresolved
  local undef_list=""
  for sym in "${!undefs[@]}"; do
    if [[ -z "${defs[$sym]:-}" ]]; then
      undef_list+=" $sym"
    fi
  done
  undef_list="${undef_list# }"

  if [[ -n "$undef_list" ]]; then
    ctx[undefined_syms]="$undef_list"
    ctx[error]="undefined symbols: $undef_list"
    return 1
  fi

  # pass 3: resolve defined symbols to final addresses
  for sym in "${!defs[@]}"; do
    local val="${defs[$sym]}"
    IFS=':' read -r obj_idx shndx st_val <<< "$val"

    local base_v=0
    local per_obj_off=0

    case $shndx in
      1) base_v=$vaddr_t; per_obj_off="${ctx[obj_${obj_idx}_text_off]:-0}" ;;
      2) base_v=$vaddr_d; per_obj_off="${ctx[obj_${obj_idx}_data_off]:-0}" ;;
      3) base_v=$vaddr_r; per_obj_off="${ctx[obj_${obj_idx}_rodata_off]:-0}" ;;
      4) base_v=$vaddr_b ;;
      *)  ctx[error]="unknown section index $shndx for symbol '$sym'"; return 1 ;;
    esac

    local final_addr=$((base_v + per_obj_off + st_val))
    ctx["sym_final_addr_${sym}"]=$final_addr

    if [[ "$sym" == "_start" ]]; then
      ctx[entry_vaddr]=$final_addr
    fi
  done

  return 0
}
