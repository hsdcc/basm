#!/usr/bin/env bash

error_msg() {
    echo "error: $1" >&2
    return 1
}