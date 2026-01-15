#!/usr/bin/env bash

# source all function files
for func_file in "$(dirname "${BASH_SOURCE[0]}")/functions/"*.sh; do
    if [[ -f "$func_file" ]]; then
        source "$func_file"
    fi
done
