#!/usr/bin/env bash

# Global variable to hold current assembly mode
declare -g assembly_mode="exe"

set_assembly_mode() {
    assembly_mode="$1"
}

get_assembly_mode() {
    echo "$assembly_mode"
}