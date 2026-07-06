#!/usr/bin/env bash

# link_objects — linker-descriptor orchestrator
# Calls phases 1-5 in sequence using linker_ctx
link_objects() {
    local objects=("$@")
    local output_file="${objects[-1]}"
    unset 'objects[-1]'

    [[ ${#objects[@]} -lt 1 ]] && { error_msg "need at least one object file"; return 1; }

    # validate all inputs up front
    local obj
    for obj in "${objects[@]}"; do
        [[ -f "$obj" ]] || { error_msg "object file does not exist: $obj"; return 1; }
        is_elf_object "$obj" || { error_msg "not a proper ELF object: $obj"; return 1; }
    done

    # initialize linker context
    declare -A linker_ctx=()
    linker_ctx[objects]="${objects[*]}"
    linker_ctx[output]="$output_file"
    linker_ctx[error]=""
    linker_ctx[warnings]=""

    # Phase 1: collect — parse all object files
    linker_collect linker_ctx || {
        local err="${linker_ctx[error]:-unknown error}"
        error_msg "linker phase 1 (collect) failed: $err"
        return 1
    }

    # Phase 2: layout — assign offsets and addresses with alignment
    linker_layout linker_ctx || {
        local err="${linker_ctx[error]:-unknown error}"
        error_msg "linker phase 2 (layout) failed: $err"
        return 1
    }

    # Phase 3: resolve symbols — detect duplicates and undefined
    linker_resolve linker_ctx || {
        local err="${linker_ctx[error]:-unknown error}"
        error_msg "linker phase 3 (resolve) failed: $err"
        return 1
    }

    # Phase 4: apply relocations
    linker_relocate linker_ctx || {
        local err="${linker_ctx[error]:-unknown error}"
        error_msg "linker phase 4 (relocate) failed: $err"
        return 1
    }

    # Phase 5: emit executable
    linker_emit linker_ctx || {
        local err="${linker_ctx[error]:-unknown error}"
        error_msg "linker phase 5 (emit) failed: $err"
        return 1
    }

    return 0
}
