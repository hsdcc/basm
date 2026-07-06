#!/usr/bin/env bash

# link_objects — linker orchestrator
# Delegates to 5 phases: collect → layout → resolve → relocate → emit
link_objects() {
  local objects=("$@")
  local output_file="${objects[-1]}"
  unset 'objects[-1]'

  if [[ ${#objects[@]} -lt 1 ]]; then
    error_msg "need at least one object file to link"
    return 1
  fi

  # validate inputs
  local obj
  for obj in "${objects[@]}"; do
    if [[ ! -f "$obj" ]]; then
      error_msg "object file does not exist: $obj"
      return 1
    fi
    if ! is_elf_object "$obj"; then
      error_msg "not a valid ELF object: $obj"
      return 1
    fi
  done

  # initialize linker context
  declare -gA linker_ctx=()
  linker_ctx[objects]="${objects[*]}"
  linker_ctx[output]="$output_file"
  linker_ctx[error]=""
  linker_ctx[warnings]=""

  # Phase 1: collect
  linker_collect linker_ctx || {
    error_msg "${linker_ctx[error]:-collect failed}"
    unset linker_ctx
    return 1
  }

  # Phase 2: layout
  linker_layout linker_ctx || {
    error_msg "${linker_ctx[error]:-layout failed}"
    unset linker_ctx
    return 1
  }

  # Phase 3: resolve
  linker_resolve linker_ctx || {
    error_msg "${linker_ctx[error]:-resolve failed}"
    unset linker_ctx
    return 1
  }

  # Phase 4: relocate
  linker_relocate linker_ctx || {
    error_msg "${linker_ctx[error]:-relocate failed}"
    unset linker_ctx
    return 1
  }

  # report warnings
  if [[ -n "${linker_ctx[warnings]:-}" ]]; then
    echo "linker warnings: ${linker_ctx[warnings]}" >&2
  fi

  # Phase 5: emit
  linker_emit linker_ctx || {
    error_msg "${linker_ctx[error]:-emit failed}"
    unset linker_ctx
    return 1
  }

  unset linker_ctx
  return 0
}
