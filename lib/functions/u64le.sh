#!/usr/bin/env bash
u64le() {
    local n=$1
    local b0=$((n & 0xff))
    local b1=$(((n >> 8) & 0xff))
    local b2=$(((n >> 16) & 0xff))
    local b3=$(((n >> 24) & 0xff))
    local b4=$(((n >> 32) & 0xff))
    local b5=$(((n >> 40) & 0xff))
    local b6=$(((n >> 48) & 0xff))
    local b7=$(((n >> 56) & 0xff))
    printf "%02x%02x%02x%02x%02x%02x%02x%02x" $b0 $b1 $b2 $b3 $b4 $b5 $b6 $b7
}