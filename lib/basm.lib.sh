#!/usr/bin/env bash

# Import modularized functions
source "$(dirname "${BASH_SOURCE[0]}")/functions/trim_string.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/hex_to_bin.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/u32le.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/u64le.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/error_msg.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/write_at_offset.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/generate_zeros.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/patterns.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/opcodes.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/operand_parsers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/helper_functions.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/assembler_functions.sh"
source "$(dirname "${BASH_SOURCE[0]}")/functions/basm_assemble.sh"