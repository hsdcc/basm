#!/usr/bin/env bash

trim_string() {
    local str="$1"
    # remove leading whitespace
    str="${str#"${str%%[![:space:]]*}"}"
    # remove trailing whitespace
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}