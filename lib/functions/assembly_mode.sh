#!/usr/bin/env bash
declare -g assembly_mode="exe"
set_assembly_mode() {
    assembly_mode="$1"
}
get_assembly_mode() {
    echo "$assembly_mode"
}