#!/usr/bin/env bash

# Phase 4: apply relocations by type into combined text hex
linker_relocate() {
  local -n ctx="$1"
  local n="${ctx[num_objects]:-0}"
  (( n > 0 )) || { ctx[error]="no objects"; return 1; }

  local texth="${ctx[section_text_combined_hex]:-}"
  local vaddr_t="${ctx[text_vaddr]:-0}"
  local patches=0 errors=0 warns=""

  local i
  for ((i = 0; i < n; i++)); do
    local rels="${ctx[obj_${i}_relocs]:-}"
    [[ -z "$rels" ]] && continue

    local per_off="${ctx[obj_${i}_text_off]:-0}"

    IFS=' ' read -ra entries <<< "$rels"
    local entry
    for entry in "${entries[@]}"; do
      local r_off="${entry%%:*}"
      local rest="${entry#*:}"
      local sym="${rest%%:*}"
      rest="${rest#*:}"
      local rtype="${rest%%:*}"
      local addend="${rest#*:}"

      # look up final address
      local faddr="${ctx[sym_final_addr_${sym}]:-}"
      [[ -n "$faddr" ]] || { warns+="unresolved '$sym'; "; errors=$((errors + 1)); continue; }

      local coff=$((per_off + r_off))

      case $rtype in
        1)  # R_X86_64_64: 8-byte absolute LE
            local val=$((faddr + addend))
            local ph=$(printf "%016x" "$val")
            local le=""
            for ((ri = 14; ri >= 0; ri -= 2)); do le+="${ph:$ri:2}"; done
            local hexpos=$((coff * 2))
            if (( hexpos + 16 > ${#texth} )); then
              warns+="OOB at $coff; "; errors=$((errors + 1)); continue
            fi
            texth="${texth:0:$hexpos}${le}${texth:$((hexpos + 16))}"
            patches=$((patches + 1))
            ;;
        2)  # R_X86_64_PC32: 4-byte PC-relative LE
            # S + A - P where P = address of the displacement field.
            # CPU adds displacement to RIP (address after instruction).
            # RIP = vaddr_t + coff + 4 (4-byte field ends at next insn).
            local val=$((faddr + addend - (vaddr_t + coff + 4)))
            # clamp to uint32
            local clamped=$(( (1 << 32) + (val % (1 << 32)) ))
            (( clamped = clamped % (1 << 32) ))
            local ph=$(printf "%08x" "$clamped")
            local le=""
            for ((ri = 6; ri >= 0; ri -= 2)); do le+="${ph:$ri:2}"; done
            local hexpos=$((coff * 2))
            if (( hexpos + 8 > ${#texth} )); then
              warns+="OOB at $coff; "; errors=$((errors + 1)); continue
            fi
            texth="${texth:0:$hexpos}${le}${texth:$((hexpos + 8))}"
            patches=$((patches + 1))
            ;;
        *) warns+="unknown type $rtype; "; errors=$((errors + 1)) ;;
      esac
    done
  done

  ctx[section_text_combined_hex]="$texth"
  ctx[patch_count]=$patches
  ctx[patch_errors]=$errors
  ctx[warnings]="$warns"

  return 0
}
