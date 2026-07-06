#!/usr/bin/env bash

# Phase 1: parse all object files into linker_ctx
linker_collect() {
  local -n ctx="$1"
  local objects_s="${ctx[objects]}"
  [[ -z "$objects_s" ]] && { ctx[error]="no objects to collect"; return 1; }

  local obj_arr=()
  IFS=' ' read -ra obj_arr <<< "$objects_s"
  ctx[num_objects]=${#obj_arr[@]}

  local idx
  for ((idx = 0; idx < ${#obj_arr[@]}; idx++)); do
    local f="${obj_arr[$idx]}"
    ctx["obj_${idx}_path"]="$f"

    [[ -f "$f" ]] || { ctx[error]="object file not found: $f"; return 1; }
    is_elf_object "$f" || { ctx[error]="not a valid ELF object: $f"; return 1; }

    # parse ELF header
    local pfx="l${idx}"
    parse_elf_header "$f" "$pfx" || { ctx[error]="failed ELF header: $f"; return 1; }

    local shoff sec_cnt shstrndx
    eval "shoff=\${${pfx}_shoff}"
    eval "sec_cnt=\${${pfx}_num_sections}"
    eval "shstrndx=\${${pfx}_shstrndx}"

    # parse section headers
    local -a seclist
    parse_section_headers "$f" "$shoff" "$sec_cnt" "seclist" || { ctx[error]="failed section headers: $f"; return 1; }

    # read shstrtab
    local shst_off=0 shst_sz=0
    local si
    for ((si = 0; si < sec_cnt; si++)); do
      local -a sf
      IFS=',' read -ra sf <<< "${seclist[$si]}"
      if (( si == shstrndx )); then
        shst_off=${sf[2]}
        shst_sz=${sf[3]}
        break
      fi
    done

    local shst_hex=""
    read_file_hex "$f" "$shst_off" "$shst_sz" "shst_hex"

    # read symtab/strtab/rela info
    local text_hex="" data_hex="" rodata_hex=""
    local text_sz=0 data_sz=0 rodata_sz=0 bss_sz=0
    local sym_off=0 sym_sz=0 str_off=0 str_sz=0 rela_off=0 rela_sz=0

    for ((si = 0; si < sec_cnt; si++)); do
      local -a sf
      IFS=',' read -ra sf <<< "${seclist[$si]}"
      local sn=${sf[0]} st=${sf[1]} so=${sf[2]} ss=${sf[3]}

      # read section name from shstrtab
      local sname=""
      if (( sn >= 0 && sn * 2 + 1 < ${#shst_hex} )); then
        local spos=$((sn * 2))
        while ((spos + 1 < ${#shst_hex})); do
          local sb="${shst_hex:$spos:2}"
          [[ "$sb" == "00" ]] && break
          local sv=$((16#$sb))
          ((sv >= 32 && sv < 127)) && sname+=$(printf "\\$(printf '%03o' "$sv")")
          spos=$((spos + 2))
        done
      fi

      # match by name first, then by type for relocations (which may have no name)
      case "$sname" in
        .text)    read_file_hex "$f" "$so" "$ss" "text_hex"; text_sz=$ss ;;
        .data)    read_file_hex "$f" "$so" "$ss" "data_hex"; data_sz=$ss ;;
        .rodata)  read_file_hex "$f" "$so" "$ss" "rodata_hex"; rodata_sz=$ss ;;
        .bss)     bss_sz=$ss ;;
        .symtab)  sym_off=$so; sym_sz=$ss ;;
        .strtab)  str_off=$so; str_sz=$ss ;;
        .rela.text) rela_off=$so; rela_sz=$ss ;;
      esac

      # also match by section type for sections without names
      if [[ -z "$sname" ]]; then
        case $st in
          2) sym_off=$so; sym_sz=$ss ;;
          4) rela_off=$so; rela_sz=$ss ;;
        esac
      fi
    done

    ctx["obj_${idx}_text_hex"]="$text_hex"
    ctx["obj_${idx}_data_hex"]="$data_hex"
    ctx["obj_${idx}_rodata_hex"]="$rodata_hex"
    ctx["obj_${idx}_text_size"]=$text_sz
    ctx["obj_${idx}_data_size"]=$data_sz
    ctx["obj_${idx}_rodata_size"]=$rodata_sz
    ctx["obj_${idx}_bss_size"]=$bss_sz
    ctx["obj_${idx}_text_off"]=0
    ctx["obj_${idx}_data_off"]=0
    ctx["obj_${idx}_rodata_off"]=0

    # parse symbol table
    ctx["obj_${idx}_symtab"]=""
    if (( sym_sz > 0 && str_sz > 0 )); then
      local sym_hex="" str_hex=""
      read_file_hex "$f" "$sym_off" "$sym_sz" "sym_hex"
      read_file_hex "$f" "$str_off" "$str_sz" "str_hex"

      local ec=$((sym_sz / 24))
      local slist=""
      local ei
      for ((ei = 0; ei < ec; ei++)); do
        local eo=$((ei * 48))

        local stn_h="${sym_hex:$eo:8}"
        local stn=""
        for ((ri = 6; ri >= 0; ri -= 2)); do stn+="${stn_h:$ri:2}"; done
        local stn_v=$(hex_to_dec "$stn")
        (( stn_v == 0 )) && continue

        local shx_h="${sym_hex:$((eo + 12)):4}"
        local shx=""
        for ((ri = 2; ri >= 0; ri -= 2)); do shx+="${shx_h:$ri:2}"; done
        local shx_v=$(hex_to_dec "$shx")

        local val_h="${sym_hex:$((eo + 16)):16}"
        local val=""
        for ((ri = 14; ri >= 0; ri -= 2)); do val+="${val_h:$ri:2}"; done
        local val_v=$(hex_to_dec "$val")

        local nm="" pos=$((stn_v * 2))
        while ((pos + 1 < ${#str_hex})); do
          local nb="${str_hex:$pos:2}"
          [[ "$nb" == "00" ]] && break
          local nv=$((16#$nb))
          ((nv >= 32 && nv < 127)) && nm+=$(printf "\\$(printf '%03o' "$nv")")
          pos=$((pos + 2))
        done

        [[ -n "$nm" ]] && slist+="${nm}:${shx_v}:${val_v} "
      done
      ctx["obj_${idx}_symtab"]="${slist%% }"
    fi

    # parse relocations
    ctx["obj_${idx}_relocs"]=""
    if (( rela_sz > 0 && sym_sz > 0 && str_sz > 0 )); then
      local rla_h="" rsym_h="" rstr_h=""
      read_file_hex "$f" "$rela_off" "$rela_sz" "rla_h"
      read_file_hex "$f" "$sym_off" "$sym_sz" "rsym_h"
      read_file_hex "$f" "$str_off" "$str_sz" "rstr_h"

      local ec=$((rela_sz / 24))
      local rlist=""
      local ei
      for ((ei = 0; ei < ec; ei++)); do
        local eo=$((ei * 48))

        local ro_h="${rla_h:$eo:16}"
        local ro=""
        for ((ri = 14; ri >= 0; ri -= 2)); do ro+="${ro_h:$ri:2}"; done
        local ro_v=$(hex_to_dec "$ro")

        local ri_h="${rla_h:$((eo + 16)):16}"
        local ri=""
        for ((ri2 = 14; ri2 >= 0; ri2 -= 2)); do ri+="${ri_h:$ri2:2}"; done
        local ri_v=$(hex_to_dec "$ri")
        local sym_idx=$((ri_v >> 32))
        local rtype=$((ri_v & 0xFFFFFFFF))

        local ra_h="${rla_h:$((eo + 32)):16}"
        local ra=""
        for ((ri2 = 14; ri2 >= 0; ri2 -= 2)); do ra+="${ra_h:$ri2:2}"; done
        local ra_v=$(hex_to_dec "$ra")

        # symbol name from symtab
        local nm=""
        if (( sym_idx > 0 )); then
          local seo=$((sym_idx * 48))
          local stn_h2="${rsym_h:$seo:8}"
          local stn2=""
          for ((ri2 = 6; ri2 >= 0; ri2 -= 2)); do stn2+="${stn_h2:$ri2:2}"; done
          local stn_v2=$(hex_to_dec "$stn2")
          local pos=$((stn_v2 * 2))
          while ((pos + 1 < ${#rstr_h})); do
            local nb="${rstr_h:$pos:2}"
            [[ "$nb" == "00" ]] && break
            local nv=$((16#$nb))
            ((nv >= 32 && nv < 127)) && nm+=$(printf "\\$(printf '%03o' "$nv")")
            pos=$((pos + 2))
          done
        fi
        [[ -n "$nm" ]] && rlist+="${ro_v}:${nm}:${rtype}:${ra_v} "
      done
      ctx["obj_${idx}_relocs"]="${rlist%% }"
    fi
  done

  return 0
}
