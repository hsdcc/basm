#!/usr/bin/env bash
rr_operands='^(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
ri_operands='^(r[a-z]{2}),[[:space:]]*(.*)$'
mem_operands='^\[(r[a-z]{2})([\+\-][0-9]+)?\]$'
mem_dest_operands='^\[(r[a-z]{2})([\+\-][0-9]+)?\],[[:space:]]+(r[a-z]{2})$'
imm_operands='^([0-9]+|-?[0-9]+|0x[0-9a-fA-F]+)$'
push_pop_operands='^(r[a-z]{2})$'
arith_rr_operands='^(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
arith_ri_operands='^(r[a-z]{2}),[[:space:]]*(.*)$'
jump_operands='^([.a-zA-Z0-9_]+)$'
loop_operands='^([.a-zA-Z0-9_]+)$'
unary_operands='^(r[a-z]{2})$'
call_operands='^([.a-zA-Z0-9_]+)$'
mul_operands='^(r[a-z]{2})$'
imul_operands='^(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
lea_operands='^(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$'
shift_operands='^(r[a-z]{2}),[[:space:]]+([0-9]+)$'
test_rr_operands='^(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
test_ri_operands='^(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$'
movzx_operands='^(r[a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$'
movsxd_operands='^(r[a-z]{2}),[[:space:]]+([er][a-z]{2})$'
setcc_operands='^([ab][lh]|[cd][lh]|r[a-z]{2})$'
cmov_operands='^(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
movss_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
movsd_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
addss_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
addsd_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
mulss_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
mulsd_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
subss_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
subsd_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
divss_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
divsd_rr_operands='^(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
movsd_mem_operands='^(xmm[0-9]+),[[:space:]]+\[(r[a-z]+)\]$'
cvtsd2si_operands='^(r[a-z]{2}),[[:space:]]+(xmm[0-9]+)$'
parse_rr_operands() {
    local operands="$1"
    if [[ "$operands" =~ $rr_operands ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
        return 0
    else
        return 1
    fi
}
parse_ri_operands() {
    local operands="$1"
    if [[ "$operands" =~ $ri_operands ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
        return 0
    else
        return 1
    fi
}
parse_mem_operands() {
    local operands="$1"
    if [[ "$operands" =~ $mem_operands ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
        return 0
    else
        return 1
    fi
}
parse_unary_operands() {
    local operands="$1"
    if [[ "$operands" =~ $unary_operands ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    else
        return 1
    fi
}