#!/usr/bin/env bash

# build ELF header with one PT_LOAD segment (legacy, 5 args)
# or three PT_LOAD segments (11 args):
#   args (5):  entry_vaddr file_text_off text_vaddr data_size file_data_off
#   args (11): entry_vaddr file_text_off text_vaddr text_size \
#              data_vaddr data_file_off data_filesz data_memsz \
#              rodata_vaddr rodata_file_off rodata_size
build_elf_header() {
    if (( $# == 5 )); then
        # legacy: 1 PT_LOAD segment
        local entry_vaddr="$1"
        local file_text_off="$2"
        local text_vaddr="$3"
        local data_size="$4"
        local file_data_off="$5"
        local header_hex=""
        header_hex+="7f454c46"
        header_hex+="02"
        header_hex+="01"
        header_hex+="01"
        header_hex+="00"
        header_hex+="0000000000000000"
        header_hex+="0200"
        header_hex+="3e00"
        header_hex+="01000000"
        header_hex+="$(u64le $entry_vaddr)"
        header_hex+="$(u64le 0x40)"
        header_hex+="$(u64le 0)"
        header_hex+="00000000"
        header_hex+="4000"
        header_hex+="3800"
        header_hex+="0100"
        header_hex+="0000"
        header_hex+="0000"
        header_hex+="0000"
        header_hex+="$(u32le 1)"
        header_hex+="$(u32le 5)"
        header_hex+="$(u64le $file_text_off)"
        header_hex+="$(u64le $text_vaddr)"
        header_hex+="$(u64le $text_vaddr)"
        local filesz=$((file_data_off + data_size))
        header_hex+="$(u64le $filesz)"
        header_hex+="$(u64le $filesz)"
        header_hex+="$(u64le 0x200000)"
        echo "$header_hex"
    elif (( $# == 11 )); then
        # 3 PT_LOAD segments: text RE, rodata R, data RW
        local entry_vaddr="$1"
        local file_text_off="$2"
        local text_vaddr="$3"
        local text_size="$4"
        local data_vaddr="$5"
        local file_data_off="$6"
        local data_filesz="$7"
        local data_memsz="$8"
        local rodata_vaddr="$9"
        local file_rodata_off="${10}"
        local rodata_size="${11}"

        local phdr_off=0x40
        local phnum=3

        local h=""
        h+="7f454c46"
        h+="02"
        h+="01"
        h+="01"
        h+="00"
        h+="0000000000000000"
        h+="0200"
        h+="3e00"
        h+="01000000"
        h+="$(u64le $entry_vaddr)"
        h+="$(u64le $phdr_off)"
        h+="$(u64le 0)"
        h+="00000000"
        h+="4000"
        h+="3800"
        # e_phnum = 3
        h+="0300"
        h+="0000"
        h+="0000"
        h+="0000"

        # PHDR 0: text segment (r-x)
        h+="$(u32le 1)"
        h+="$(u32le 5)"
        h+="$(u64le $file_text_off)"
        h+="$(u64le $text_vaddr)"
        h+="$(u64le $text_vaddr)"
        h+="$(u64le $text_size)"
        h+="$(u64le $text_size)"
        h+="$(u64le 0x1000)"

        # PHDR 1: rodata segment (r--)
        h+="$(u32le 1)"
        h+="$(u32le 4)"
        h+="$(u64le $file_rodata_off)"
        h+="$(u64le $rodata_vaddr)"
        h+="$(u64le $rodata_vaddr)"
        h+="$(u64le $rodata_size)"
        h+="$(u64le $rodata_size)"
        h+="$(u64le 0x1000)"

        # PHDR 2: data segment (rw-)
        h+="$(u32le 1)"
        h+="$(u32le 6)"
        h+="$(u64le $file_data_off)"
        h+="$(u64le $data_vaddr)"
        h+="$(u64le $data_vaddr)"
        h+="$(u64le $data_filesz)"
        h+="$(u64le $data_memsz)"
        h+="$(u64le 0x1000)"

        echo "$h"
    fi
}

# build ELF header with TWO PT_LOAD segments:
#   segment 1: text (PF_R|PF_X = 5)
#   segment 2: data+rodata+bss (PF_R|PF_W = 6)
# args: entry_vaddr \
#       file_text_off text_vaddr text_filesz \
#       file_data_off data_vaddr data_filesz data_memsz
build_elf_header_multi() {
    local entry_vaddr="$1"
    local file_text_off="$2" text_vaddr="$3" text_filesz="$4"
    local file_data_off="$5" data_vaddr="$6" data_filesz="$7" data_memsz="$8"

    local phdr_off=0x40        # program header starts right after ELF header
    local phdr_entsize=56      # ELF64 program header entry size
    local phnum=2

    local h=""
    # e_ident (16 bytes)
    h+="7f454c46"
    h+="02"
    h+="01"
    h+="01"
    h+="00"
    h+="0000000000000000"
    # e_type, e_machine, e_version
    h+="0200"
    h+="3e00"
    h+="01000000"
    # e_entry
    h+="$(u64le $entry_vaddr)"
    # e_phoff = 0x40
    h+="$(u64le $phdr_off)"
    # e_shoff = 0
    h+="$(u64le 0)"
    # e_flags
    h+="00000000"
    # e_ehsize = 64 (0x40)
    h+="4000"
    # e_phentsize = 56 (0x38)
    h+="3800"
    # e_phnum = 2
    h+="0200"
    # e_shentsize, e_shnum, e_shstrndx = 0
    h+="0000"
    h+="0000"
    h+="0000"

    # PHDR 1: text segment (r-x)
    h+="$(u32le 1)"           # p_type = PT_LOAD
    h+="$(u32le 5)"           # p_flags = PF_R | PF_X
    h+="$(u64le $file_text_off)"
    h+="$(u64le $text_vaddr)"
    h+="$(u64le $text_vaddr)"
    h+="$(u64le $text_filesz)"
    h+="$(u64le $text_filesz)"
    h+="$(u64le 0x1000)"      # p_align = 4K page

    # PHDR 2: data segment (rw-)
    h+="$(u32le 1)"           # p_type = PT_LOAD
    h+="$(u32le 6)"           # p_flags = PF_R | PF_W
    h+="$(u64le $file_data_off)"
    h+="$(u64le $data_vaddr)"
    h+="$(u64le $data_vaddr)"
    h+="$(u64le $data_filesz)"
    h+="$(u64le $data_memsz)"
    h+="$(u64le 0x1000)"      # p_align = 4K page

    echo "$h"
}
