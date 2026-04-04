#!/usr/bin/env bash
trim_string() {
    local str="$1"
    
    str="${str#"${str%%[![:space:]]*}"}"
    
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}