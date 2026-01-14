#!/usr/bin/env bash

# Helper function to trim leading and trailing whitespace from a string
trim_string() {
	local str="$1"
	# Remove leading whitespace
	str="${str#"${str%%[![:space:]]*}"}"
	# Remove trailing whitespace
	str="${str%"${str##*[![:space:]]}"}"
	echo "$str"
}

# Helper function to convert hex string to binary data
hex_to_bin() {
	local hex="$1"
	local -a bytes
	local i
	
	# Ensure even length hex string
	if (( ${#hex} % 2 != 0 )); then
		hex="0$hex"
	fi
	
	# Split hex string into byte pairs and convert to binary
	for ((i = 0; i < ${#hex}; i += 2)); do
		local byte="${hex:$i:2}"
		printf "\\x$byte"
	done
}

# Helper function to generate padding zeros
generate_zeros() {
	local count="$1"
	local i
	for ((i = 0; i < count; i++)); do
		printf "\\x00"
	done
}

# Helper function to write data at specific offset in a file
write_at_offset() {
	local src_file="$1"		 # Source file containing data to write
	local dest_file="$2"	 # Destination file to write to
	local offset="$3"			 # Byte offset to write at write at
	
	# Read the source file content
	local src_content
	src_content=$(< "$src_file")
	
	# Read the destination file content
	local dest_content
	if [[ -f "$dest_file" ]]; then
		dest_content=$(< "$dest_file")
	else
		dest_content=""
	fi
	
	# Ensure destination is at least 'offset' bytes long by padding with nulls if necessary
	local current_len=${#dest_content}
	local padded_content="$dest_content"
	if (( current_len < offset )); then
		local padding_len=$((offset - current_len))
		local i
		for ((i = 0; i < padding_len; i++)); do
			padded_content+=$'\0'
		done
	fi
	
	# Calculate where to place the source content
	local prefix="${padded_content:0:offset}"
	local suffix="${padded_content:offset}"
	
	# Combine: prefix + src_content + suffix
	local result="$prefix$src_content$suffix"
	
	# Write the combined content back to the destination file
	printf '%s' "$result" > "$dest_file"
}

# convert number to little-endian 32-bit hex
u32le() {
	local n=$1
	printf "%02x%02x%02x%02x" $((n & 0xff)) $(((n >> 8) & 0xff)) $(((n >> 16) & 0xff)) $(((n >> 24) & 0xff))
}

# convert number to little-endian 64-bit hex
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

basm_assemble() {
	local code_str="${1:-""]}"
	local outfile="${2:-a.out}"

	local equ_pattern='^([A-Za-z0-9_]+)[[:space:]]+equ[[:space:]]+\$[[:space:]]*-[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*$'
	local db_pattern='^([a-zA-Z0-9_]+):?[[:space:]]+db[[:space:]]+\"(.*)\"([[:space:]]*,[[:space:]]*([0-9]+))?[[:space:]]*$'
	local dq_pattern='^([a-zA-Z0-9_]+):?[[:space:]]+dq[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$'
	local label_pattern='^([.a-zA-Z0-9_]+):$'
	local mov_rr_pattern='^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
	local mov_ri_pattern='^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$'
	local mem_pattern='^\[(r[a-z]{2})([\+\-][0-9]+)?\]$'
	local mem_dest_pattern='^\[(r[a-z]{2})([\+\-][0-9]+)?\],[[:space:]]+(r[a-z]{2})$'
	local imm_patterns='^([0-9]+|-?[0-9]+|0x[0-9a-fA-F]+)$'
	local xor_self_pattern='^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
	local push_pop_pattern='^(push|pop)[[:space:]]+(r[a-z]{2})$'
	local arith_rr_pattern='^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
	local arith_ri_pattern='^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]*(.*)$'
	local jump_pattern='^(je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jo|jno|js|jns|jmp)[[:space:]]+(.*)$'
	local loop_pattern='^(loop|loope|loopne)[[:space:]]+(.*)$'
	local unary_pattern='^(inc|dec|neg|not)[[:space:]]+(r[a-z]{2})$'
	local call_pattern='^call[[:space:]]+([.a-zA-Z0-9_]+)$'
	local mul_pattern='^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$'
	local imul_pattern='^imul[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
	local lea_pattern='^lea[[:space:]]+(r[a-z]+),[[:space:]]+\[([a-zA-Z0-9_]+)\]$'
	local shift_pattern='^(shl|shr|sar)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$'
	local test_rr_pattern='^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'
	local test_ri_pattern='^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$'
	local movzx_pattern='^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$'
	local movsxd_pattern='^movsxd[[:space:]]+(r[a-z]{2}),[[:space:]]+([er][a-z]{2})$'
	local setcc_pattern='^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$'
	local cmov_pattern='^cmov(e|ne|a|ae|b|be|g|ge|l|le|o|no|s|ns|p|np)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$'

	# floating point patterns
	local movss_rr_pattern='^movss[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local movsd_rr_pattern='^movsd[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local addss_rr_pattern='^addss[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local addsd_rr_pattern='^addsd[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local mulss_rr_pattern='^mulss[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local mulsd_rr_pattern='^mulsd[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local subss_rr_pattern='^subss[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local subsd_rr_pattern='^subsd[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local divss_rr_pattern='^divss[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local divsd_rr_pattern='^divsd[[:space:]]+(xmm[0-9]+),[[:space:]]+(xmm[0-9]+)$'
	local movsd_mem_pattern='^movsd[[:space:]]+(xmm[0-9]+),[[:space:]]+\[(r[a-z]+)\]$'
	local cvtsd2si_pattern='^cvtsd2si[[:space:]]+(r[a-z]{2}),[[:space:]]+(xmm[0-9]+)$'

	# Floating point operation lookup tables
	declare -A fp_opcodes
	fp_opcodes["movss_rr"]="f30f10"
	fp_opcodes["movsd_rr"]="f20f10"
	fp_opcodes["addss_rr"]="f30f58"
	fp_opcodes["addsd_rr"]="f20f58"
	fp_opcodes["mulss_rr"]="f30f59"
	fp_opcodes["mulsd_rr"]="f20f59"
	fp_opcodes["subss_rr"]="f30f5c"
	fp_opcodes["subsd_rr"]="f20f5c"
	fp_opcodes["divss_rr"]="f30f5e"
	fp_opcodes["divsd_rr"]="f20f5e"
	fp_opcodes["movsd_mem"]="f20f10"
	fp_opcodes["cvtsd2si"]="f20f2d"

	# Operand patterns for dispatch
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
	# fp operands
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

	# No longer loading instruction definitions from external file
	# All instruction encodings are hardcoded directly in this file

	mapfile -t lines <<<"$code_str"

	declare -A labels
	declare -A data_label_off
	declare -A equs
	# register encoding map for modrm byte
	declare -A regs
	regs["rax"]=0
	regs["rcx"]=1
	regs["rdx"]=2
	regs["rbx"]=3
	regs["rsp"]=4
	regs["rbp"]=5
	regs["rsi"]=6
	regs["rdi"]=7

	# xmm registers for floating point
	declare -A xmm_regs
	xmm_regs["xmm0"]=0
	xmm_regs["xmm1"]=1
	xmm_regs["xmm2"]=2
	xmm_regs["xmm3"]=3
	xmm_regs["xmm4"]=4
	xmm_regs["xmm5"]=5
	xmm_regs["xmm6"]=6
	xmm_regs["xmm7"]=7
	xmm_regs["xmm8"]=8
	xmm_regs["xmm9"]=9
	xmm_regs["xmm10"]=10
	xmm_regs["xmm11"]=11
	xmm_regs["xmm12"]=12
	xmm_regs["xmm13"]=13
	xmm_regs["xmm14"]=14
	xmm_regs["xmm15"]=15

	# opcode arrays for cleaner dispatch
	declare -A arith_opcodes
	arith_opcodes["add"]="4801%02x"
	arith_opcodes["sub"]="4829%02x"
	arith_opcodes["or"]="4809%02x"
	arith_opcodes["and"]="4821%02x"
	arith_opcodes["cmp"]="4839%02x"

	declare -A jump_opcodes
	jump_opcodes["je"]="74"
	jump_opcodes["jne"]="75"
	jump_opcodes["jg"]="7f"
	jump_opcodes["jl"]="7c"
	jump_opcodes["jge"]="7d"
	jump_opcodes["jle"]="7e"
	jump_opcodes["ja"]="77"
	jump_opcodes["jb"]="72"
	jump_opcodes["jae"]="73"
	jump_opcodes["jbe"]="76"
	jump_opcodes["jo"]="70"
	jump_opcodes["jno"]="71"
	jump_opcodes["js"]="78"
	jump_opcodes["jns"]="79"
	jump_opcodes["jmp"]="eb"

	declare -A loop_opcodes
	loop_opcodes["loop"]="e2"
	loop_opcodes["loope"]="e1"
	loop_opcodes["loopne"]="e0"

	declare -A unary_op_ext
	unary_op_ext["inc"]=0
	unary_op_ext["dec"]=1
	unary_op_ext["neg"]=3
	unary_op_ext["not"]=2

	declare -A shift_op_ext
	shift_op_ext["shl"]=4
	shift_op_ext["shr"]=5
	shift_op_ext["sar"]=7

	declare -A mul_op_ext
	mul_op_ext["mul"]=4
	mul_op_ext["div"]=6
	mul_op_ext["idiv"]=7

	declare -A cmov_codes
	cmov_codes["e"]=0x44
	cmov_codes["ne"]=0x45
	cmov_codes["a"]=0x47
	cmov_codes["ae"]=0x43
	cmov_codes["b"]=0x42
	cmov_codes["be"]=0x46
	cmov_codes["g"]=0x4f
	cmov_codes["ge"]=0x4d
	cmov_codes["l"]=0x4c
	cmov_codes["le"]=0x4e
	cmov_codes["o"]=0x40
	cmov_codes["no"]=0x41
	cmov_codes["s"]=0x48
	cmov_codes["ns"]=0x49
	cmov_codes["p"]=0x4a
	cmov_codes["np"]=0x4b

	# helper to get register number for byte registers too
	get_reg_num() {
		local reg="$1"
		case "$reg" in
			al|rax|eax) echo 0 ;;
			cl|rcx|ecx) echo 1 ;;
			dl|rdx|edx) echo 2 ;;
			bl|rbx|ebx) echo 3 ;;
			spl|rsp|esp) echo 4 ;;
			bpl|rbp|ebp) echo 5 ;;
			sil|rsi|esi) echo 6 ;;
			dil|rdi|edi) echo 7 ;;
			ah) echo 4 ;;
			ch) echo 5 ;;
			dh) echo 6 ;;
			bh) echo 7 ;;
			*) echo -1 ;;
		esac
	}

	# helper functions for assembling
	build_modrm() {
		local mod=$1 reg=$2 rm=$3
		echo $((mod * 64 + reg * 8 + rm))
	}

	parse_immediate() {
		local arg=$1
		if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
			echo $((16#${BASH_REMATCH[1]}))
		elif [[ "$arg" =~ ^[0-9]+$ ]]; then
			echo $((arg))
		elif [[ -n "${equs[$arg]:-}" ]]; then
			echo ${equs[$arg]}
		else
			echo "error: unknown immediate '$arg'" >&2
			return 1
		fi
	}

	# Calculate MOV memory operand size based on addressing mode
	# Used by both first pass (sizing) and second pass (code generation)
	calc_mem_addr_size() {
		local base="$1"
		local disp="$2"
		
		local size=4
		if [[ "$base" == "rsp" || "$base" == "r12" ]]; then
			if [[ -z "$disp" ]]; then
				size=4
			else
				if (( disp >= -128 && disp <= 127 )); then
					size=5
				else
					size=8
				fi
			fi
		else
			if [[ -z "$disp" ]]; then
				size=3
			elif [[ "$base" == "rbp" || "$base" == "r13" ]]; then
				size=4
			else
				if (( disp >= -128 && disp <= 127 )); then
					size=4
				else
					size=7
				fi
			fi
		fi
		echo $size
	}

	# Helper function to calculate MOV instruction size based on addressing mode
	calculate_mov_size() {
		arg="${BASH_REMATCH[2]}"
		if [[ "$arg" =~ ^\[(r[a-z]{2})([\+\-][0-9]+)?\]$ ]]; then
			base="${BASH_REMATCH[1]}"
			disp="${BASH_REMATCH[2]:-}"
			size=$(calc_mem_addr_size "$base" "$disp")
			text_bytes_len=$((text_bytes_len + size))
		elif [[ "$arg" =~ ^\[(r[a-z]{2})([\+\-][0-9]+)?\],[[:space:]]+(r[a-z]{2})$ ]]; then
			base="${BASH_REMATCH[1]}"
			disp="${BASH_REMATCH[2]:-}"
			size=$(calc_mem_addr_size "$base" "$disp")
			text_bytes_len=$((text_bytes_len + size))
		elif [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^-?[0-9]+$ ]] || [[ "$arg" =~ ^0x[0-9a-fA-F]+$ ]] || [[ -n "${equs[$arg]:-}" ]]; then
			if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
				val=$((16#${BASH_REMATCH[1]}))
			elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
				val=$((arg))
			elif [[ -n "${equs[$arg]:-}" ]]; then
				val=${equs[$arg]}
			fi
			if (( val >= -2147483648 && val <= 2147483647 )); then
				text_bytes_len=$((text_bytes_len + 7))
			else
				text_bytes_len=$((text_bytes_len + 10))
			fi
		else
			text_bytes_len=$((text_bytes_len + 10))
		fi
	}

	# Helper function to calculate arithmetic reg,imm size based on register and value
	calculate_arith_ri_size() {
		reg="${BASH_REMATCH[2]}"
		arg="${BASH_REMATCH[3]}"
		if [[ "$reg" == "rax" ]]; then
			if [[ "$line" =~ ^cmp.*$ ]]; then
				text_bytes_len=$((text_bytes_len + 6))
			else
				text_bytes_len=$((text_bytes_len + 7))
			fi
		else
			text_bytes_len=$((text_bytes_len + 4))
		fi
	}

	# Helper function to calculate simple instruction size
	calculate_simple_instr_size() {
		case "$line" in
			syscall) text_bytes_len=$((text_bytes_len + 2)) ;;
			nop) text_bytes_len=$((text_bytes_len + 1)) ;;
			ret) text_bytes_len=$((text_bytes_len + 1)) ;;
			leave) text_bytes_len=$((text_bytes_len + 1)) ;;
			cqo) text_bytes_len=$((text_bytes_len + 2)) ;;
			cdqe) text_bytes_len=$((text_bytes_len + 2)) ;;
		esac
	}

	# Helper function to handle floating point operations
	handle_fp_operation() {
		local op_name="$1"
		local size="$2"
		local dst="${BASH_REMATCH[1]}"
		local src="${BASH_REMATCH[2]}"
		local modrm=$((0xc0 + xmm_regs[$dst] * 8 + xmm_regs[$src]))
		text_hex+="${fp_opcodes["$op_name"]}$(printf "%02x" $modrm)"
		current_address=$((current_address + size))
	}

	append_instruction() {
		local hex=$1 size=$2
		text_hex+=$hex
		((current_address += size))
	}

	parse_operands() {
		local line=$1
		# Simple split by space, assume max 3 operands
		IFS=' ' read -r mnemonic op1 op2 op3 <<< "$line"
		# Trim
		mnemonic=$(trim_string "$mnemonic")
		op1=$(trim_string "$op1")
		op2=$(trim_string "$op2")
		op3=$(trim_string "$op3")
		echo "$mnemonic|$op1|$op2|$op3"
	}

	# assembler functions
	assemble_simple() {
		local op=$1
		case "$op" in
			syscall) append_instruction "0f05" 2 ;;
			nop) append_instruction "90" 1 ;;
			ret) append_instruction "c3" 1 ;;
			leave) append_instruction "c9" 1 ;;
			cqo) append_instruction "4899" 2 ;;
			cdqe) append_instruction "4898" 2 ;;
			*) echo "unknown simple op $op" >&2; return 1 ;;
		esac
	}

	assemble_xor_self() {
		local reg=$1
		local modrm=$(build_modrm 3 ${regs[$reg]} ${regs[$reg]})
		local hex=$(printf "4831%02x" $modrm)
		append_instruction "$hex" 3
	}

	assemble_push_pop() {
		local op=$1 reg=$2
		local opcode
		if [[ "$op" == "push" ]]; then
			opcode=$((0x50 + regs[$reg]))
		else
			opcode=$((0x58 + regs[$reg]))
		fi
		local hex=$(printf "%02x" $opcode)
		append_instruction "$hex" 1
	}

	assemble_arith_rr() {
		local op=$1 dst=$2 src=$3
		local modrm=$(build_modrm 3 ${regs[$src]} ${regs[$dst]})
		local hex=$(printf "${arith_opcodes[$op]}" $modrm)
		append_instruction "$hex" 3
	}

assemble_mov() {
	local operands="$1"
	if [[ "$operands" =~ $rr_operands ]]; then
		local dst="${BASH_REMATCH[1]}"
		local src="${BASH_REMATCH[2]}"
		# mov reg, reg
		local modrm=$(build_modrm 3 ${regs[$src]} ${regs[$dst]})
		text_hex+=$(printf "4889%02x" $modrm)
		current_address=$((current_address + 3))
	elif [[ "$operands" =~ $mem_dest_operands ]]; then
		# mov [mem], reg
		local mem_op="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
		local reg="${BASH_REMATCH[3]}"
		hex_code=$(assemble_mem_operand "$mem_op" "${regs[$reg]}" "4889")
		text_hex+=$hex_code
		current_address=$((current_address + ${#hex_code}/2))
	elif [[ "$operands" =~ $mem_operands ]]; then
		# mov reg, [mem]
		local reg="${BASH_REMATCH[1]}"
		local mem_op="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
		hex_code=$(assemble_mem_operand "$mem_op" "${regs[$reg]}" "488b")
		text_hex+=$hex_code
		current_address=$((current_address + ${#hex_code}/2))
	else
		# mov reg, imm
		if [[ "$operands" =~ $ri_operands ]]; then
			local reg="${BASH_REMATCH[1]}"
			local arg="${BASH_REMATCH[2]}"
			local val_is_immediate=0
			local val
			if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
				val=$((16#${BASH_REMATCH[1]}))
				val_is_immediate=1
			elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
				if [[ "$arg" =~ ^-?(0|[1-9][0-9]*)$ ]]; then
					val=$((arg))
					val_is_immediate=1
				else
					echo "error: invalid integer format '$arg'" >&2
					return 1
				fi
			elif [[ -n "${equs[$arg]:-}" ]]; then
				val=${equs[$arg]}
				if [[ ! "$val" =~ ^-?[0-9]+$ ]]; then
					echo "error: equ '$arg' resolves to non-numeric value" >&2
					return 1
				fi
				val_is_immediate=1
			else
				val_is_immediate=0
			fi
			if [[ "$val_is_immediate" -eq 1 ]]; then
				if (( val >= -2147483648 && val <= 2147483647 )); then
					local opcode=$((0xc0 + regs[$reg]))
					text_hex+=$(printf "48c7%02x" "$opcode")$(u32le $val)
					current_address=$((current_address + 7))
				else
					local op=$((0xb8 + regs[$reg]))
					text_hex+=$(printf "48%02x" "$op")$(u64le $val)
					current_address=$((current_address + 10))
				fi
			else
				local op=$((0xb8 + regs[$reg]))
				if [[ -n "${data_label_off[$arg]:-}" ]]; then
					addr=$((data_vaddr + data_label_off[$arg]))
				elif [[ -n "${labels[$arg]:-}" ]]; then
					addr=$((text_vaddr + labels[$arg]))
				else
					echo "error: unknown label '$arg' in mov instruction" >&2
					return 1
				fi
				text_hex+=$(printf "48%02x" "$op")$(u64le $addr)
				current_address=$((current_address + 10))
			fi
		else
			echo "invalid mov operands: $operands" >&2
			return 1
		fi
	fi
}

assemble_arith() {
	local mnemonic="$1"
	local operands="$2"
	if [[ "$operands" =~ $rr_operands ]]; then
		local dst="${BASH_REMATCH[1]}"
		local src="${BASH_REMATCH[2]}"
		local modrm=$(build_modrm 3 ${regs[$src]} ${regs[$dst]})
		text_hex+=$(printf "${arith_opcodes[$mnemonic]}" $modrm)
		current_address=$((current_address + 3))
	elif [[ "$operands" =~ $mem_operands ]]; then
		# op reg, [mem]
		local reg="${BASH_REMATCH[1]}"
		local mem_op="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
		local opcode_reg_mem
		case "$mnemonic" in
			add) opcode_reg_mem="4803" ;;
			sub) opcode_reg_mem="482b" ;;
			and) opcode_reg_mem="4823" ;;
			or)  opcode_reg_mem="480b" ;;
			cmp) opcode_reg_mem="483b" ;;
		esac
		hex_code=$(assemble_mem_operand "$mem_op" "${regs[$reg]}" "$opcode_reg_mem")
		text_hex+=$hex_code
		current_address=$((current_address + ${#hex_code}/2))
	elif [[ "$operands" =~ $mem_dest_operands ]]; then
		# op [mem], reg
		local mem_op="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
		local reg="${BASH_REMATCH[3]}"
		local opcode_mem_reg
		case "$mnemonic" in
			add) opcode_mem_reg="4801" ;;
			sub) opcode_mem_reg="4829" ;;
			and) opcode_mem_reg="4821" ;;
			or)  opcode_mem_reg="4809" ;;
			cmp) opcode_mem_reg="4839" ;;
		esac
		hex_code=$(assemble_mem_operand "$mem_op" "${regs[$reg]}" "$opcode_mem_reg")
		text_hex+=$hex_code
		current_address=$((current_address + ${#hex_code}/2))
	else
		# op reg, imm
		if [[ "$operands" =~ $ri_operands ]]; then
			local reg="${BASH_REMATCH[1]}"
			local arg="${BASH_REMATCH[2]}"
			if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
				val=$((16#${BASH_REMATCH[1]}))
			elif [[ "$arg" =~ ^[0-9]+$ ]]; then
				val=$((arg))
			else
				echo "error: unknown immediate value '$arg' in '$mnemonic'" >&2
				return 1
			fi
			if [[ "$reg" == "rax" ]]; then
				case "$mnemonic" in
					add)
						text_hex+="4881c0$(u32le $val)"
						current_address=$((current_address + 7))
						;;
					sub)
						text_hex+="4881e8$(u32le $val)"
						current_address=$((current_address + 7))
						;;
					or)
						text_hex+="4881c8$(u32le $val)"
						current_address=$((current_address + 7))
						;;
					and)
						text_hex+="4881e0$(u32le $val)"
						current_address=$((current_address + 7))
						;;
					cmp)
						text_hex+="483d$(u32le $val)"
						current_address=$((current_address + 6))
						;;
				esac
			else
				local op_ext=0
				case "$mnemonic" in
					add) op_ext=0 ;;
					sub) op_ext=5 ;;
					cmp) op_ext=7 ;;
					or) op_ext=1 ;;
					and) op_ext=4 ;;
				esac
				local modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
				text_hex+=$(printf "4883%02x%02x" "$modrm" "$val")
				current_address=$((current_address + 4))
			fi
		else
			echo "invalid $mnemonic operands: $operands" >&2
			return 1
		fi
	fi
}

assemble_mem_operand() {
		local mem_op="$1"
		local reg_field="$2"
		local opcode="$3"

		# very basic parsing for now
		if [[ "$mem_op" =~ \[([a-z0-9]+)(([+-])([0-9]+))?\] ]]; then
			local base_reg="${BASH_REMATCH[1]}"
			local sign="${BASH_REMATCH[3]:+}"
			local disp_val="${BASH_REMATCH[4]:-0}"
			local disp=$((sign$disp_val))

			local mod
			local rm
			local sib=""
			local disp_hex=""

			# Validate base register exists
			if [[ -z "${regs[$base_reg]:-}" ]]; then
				echo "error: invalid base register '$base_reg' in memory operand '$mem_op'" >&2
				return 1
			fi

			# determine mod
			if (( disp == 0 )); then
				mod=0
				if [[ "$base_reg" == "rbp" || "$base_reg" == "r13" ]]; then
					mod=1
					disp_hex="00"
				fi
			elif (( disp >= -128 && disp <= 127 )); then
				mod=1
				disp_hex=$(printf "%02x" $((disp & 0xff)))
			else
				mod=2
				disp_hex=$(u32le "$disp")
			fi

			rm=${regs[$base_reg]}

			if [[ "$base_reg" == "rsp" || "$base_reg" == "r12" ]]; then
				rm=4 # indicates SIB byte follows
				sib="24" # SIB for [rsp/r12]
			fi

			local modrm
			modrm=$(build_modrm "$mod" "$reg_field" "$rm")
			printf "%s%02x%s%s" "$opcode" "$modrm" "$sib" "$disp_hex"
		else
			echo "error: unsupported memory operand in mov: $mem_op" >&2
			return 1
		fi
	}

	assemble_arith_mem() {
		local op="$1"
		local dst="$2"
		local src="$3"

		local opcode_reg_mem # e.g. add reg, [mem]
		local opcode_mem_reg # e.g. add [mem], reg

		case "$op" in
			add) opcode_reg_mem="4803"; opcode_mem_reg="4801" ;;
			sub) opcode_reg_mem="482b"; opcode_mem_reg="4829" ;;
			and) opcode_reg_mem="4823"; opcode_mem_reg="4821" ;;
			or)  opcode_reg_mem="480b"; opcode_mem_reg="4809" ;;
			cmp) opcode_reg_mem="483b"; opcode_mem_reg="4839" ;;
			*) echo "unsupported arith op" >&2; return 1 ;;
		esac

		if [[ "$dst" =~ ^\[.*\]$ ]]; then # op [mem], reg
			hex_code=$(assemble_mem_operand "$dst" "${regs[$src]}" "$opcode_mem_reg")
			text_hex+=$hex_code
			current_address=$((current_address + ${#hex_code}/2))
		elif [[ "$src" =~ ^\[.*\]$ ]]; then # op reg, [mem]
			hex_code=$(assemble_mem_operand "$src" "${regs[$dst]}" "$opcode_reg_mem")
			text_hex+=$hex_code
			current_address=$((current_address + ${#hex_code}/2))
		fi
	}

	assemble_short_jump() {
		local op="$1"
		local lbl="$2"
		local opcode

		case "$op" in
			je) opcode="74" ;;
			jne) opcode="75" ;;
			jg) opcode="7f" ;;
			jl) opcode="7c" ;;
			jge) opcode="7d" ;;
			jle) opcode="7e" ;;
			ja) opcode="77" ;;
			jb) opcode="72" ;;
			jae) opcode="73" ;;
			jbe) opcode="76" ;;
			jo) opcode="70" ;;
			jno) opcode="71" ;;
			js) opcode="78" ;;
			jns) opcode="79" ;;
			jmp) opcode="eb" ;;
			loop) opcode="e2" ;;
			loope) opcode="e1" ;;
			loopne) opcode="e0" ;;
			*) echo "unsupported jump/loop op" >&2; return 1;;
		esac

		if [[ -z "${labels[$lbl]:-}" ]]; then
			echo "unknown label $lbl" >&2
			return 1
		fi
		local target_address=${labels[$lbl]}
		local offset=$((target_address - (current_address + 2)))
		if [ "$offset" -lt -128 ] || [ "$offset" -gt 127 ]; then
			echo "short jump out of range: $offset" >&2
			return 1
		fi
		local offset_hex=$(printf "%02x" $((offset & 0xff)))
		text_hex+="$opcode$offset_hex"
		current_address=$((current_address + 2))
	}

	data_bytes=""
	text_ins=()
	text_bytes_len=0
	in_section=""
	# first pass: parse instructions, calculate sizes, collect labels
	line_number=0
	for raw in "${lines[@]}"; do
		line_number=$((line_number + 1))
		line="${raw%%;*}"
		line="$(trim_string "$line")"
		[ -z "$line" ] && continue
		case "$line" in
		section\ .data)
			in_section="data"
			continue
			;;
		section\ .text)
			in_section="text"
			continue
			;;
		global\ *) continue ;;
		esac

		if [[ "$in_section" == "data" ]]; then
			local equ_pattern='^([A-Za-z0-9_]+)[[:space:]]+equ[[:space:]]+\$[[:space:]]*-[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*$'
			if [[ "$line" =~ $equ_pattern ]]; then
				name="${BASH_REMATCH[1]}"
				ref="${BASH_REMATCH[2]}"
				if [[ -z "${data_label_off[$ref]:-}" ]]; then
					echo "error at line $line_number: unknown equ reference '$ref' - label not defined in .data section" >&2
					return 1
				fi
				cur_off=$((${#data_bytes} / 2))
				val=$((cur_off - data_label_off[$ref]))
				equs["$name"]=$val
				continue
			fi

			if [[ "$line" =~ $db_pattern ]]; then
				name="${BASH_REMATCH[1]}"
				txt="${BASH_REMATCH[2]}"
				extra="${BASH_REMATCH[4]}"
				# Process escape sequences using pure bash
				txt="${txt//\\/\\\\x5c}"	# Replace \ with \\x5c
				txt="${txt//
/\\n}"			# Replace newlines with \n
				txt="${txt//\"/\\\"}"			# Replace " with \"
				hex=""
				i=0
				while [ "$i" -lt ${#txt} ]; do
					ch="${txt:i:1}"
					oc=$(printf "%d" "'$ch")
					hex+="$(printf "%02x" "$oc")"
					i=$((i + 1))
				done
				if [ -n "$extra" ]; then
					hex+="$(printf "%02x" "$extra")"
				fi
				data_label_off["$name"]=$((${#data_bytes} / 2))
				data_bytes+="$hex"
				continue
			fi

			if [[ "$line" =~ $dq_pattern ]]; then
				name="${BASH_REMATCH[1]}"
				val="${BASH_REMATCH[2]}"
				if [[ "$val" =~ ^0x([0-9a-fA-F]+)$ ]]; then
					val=$((16#${BASH_REMATCH[1]}))
				else
					val=$((val))
				fi
				data_label_off["$name"]=$((${#data_bytes} / 2))
				data_bytes+=$(u64le $val)
				continue
			fi

			echo "error at line $line_number: unsupported data line format: '$line'" >&2
			echo "supported formats: label db \"string\", label dq number, label equ \$-ref" >&2
			return 1
		elif [[ "$in_section" == "text" ]]; then
			if [[ "$line" =~ ^([.a-zA-Z0-9_]+):$ ]]; then
				lbl="${BASH_REMATCH[1]}"
				labels["$lbl"]="$text_bytes_len"
				continue
			fi
			text_ins+=("$line")
			
			# Handle mov reg, reg (3 bytes)
			if [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 3))
			# Handle CMOV (4 bytes)
			elif [[ "$line" =~ $cmov_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			# Handle various MOV patterns
			elif [[ "$line" =~ ^mov[[:space:]]+(r[a-z]{2}),[[:space:]]+(.*)$ ]]; then
				calculate_mov_size
			# Handle simple instructions (1-2 bytes)
			elif [[ "$line" =~ ^(syscall|nop|ret|leave|cqo|cdqe)$ ]]; then
				calculate_simple_instr_size
			# Handle XOR reg, reg with same register (3 bytes)
			elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
				text_bytes_len=$((text_bytes_len + 3))
			# Handle PUSH/POP (1 byte each)
			elif [[ "$line" =~ ^(push|pop)[[:space:]]+(r[a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 1))
			# Handle arithmetic reg, reg (3 bytes)
			elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 3))
			# Handle arithmetic reg, immediate/memory
			elif [[ "$line" =~ ^(add|sub|cmp|or|and)[[:space:]]+(r[a-z]{2}),[[:space:]]*(.*)$ ]]; then
				calculate_arith_ri_size
			# Handle jumps (2 bytes)
			elif [[ "$line" =~ ^(je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jo|jno|js|jns|jmp)[[:space:]]+(.*)$ ]]; then
				text_bytes_len=$((text_bytes_len + 2))
			# Handle loops (2 bytes)
			elif [[ "$line" =~ ^(loop|loope|loopne)[[:space:]]+(.*)$ ]]; then
				text_bytes_len=$((text_bytes_len + 2))
			# Handle unary operations (inc, dec, neg, not) (3 bytes)
			elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+(r[a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 3))
			# Handle CALL (5 bytes)
			elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
				text_bytes_len=$((text_bytes_len + 5))
			# Handle MUL/DIV/IDIV (3 bytes)
			elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 3))
			# Handle IMUL reg, reg (4 bytes)
			elif [[ "$line" =~ ^(imul)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			# Handle LEA (7 bytes)
			elif [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
				text_bytes_len=$((text_bytes_len + 7))
			# Handle shifts (4 bytes)
			elif [[ "$line" =~ ^(shl|shr|sar)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			# Handle TEST reg, reg (3 bytes)
			elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 3))
			# Handle TEST reg, immediate (7 bytes)
			elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
				text_bytes_len=$((text_bytes_len + 7))
			# Handle MOVZX/MOVSX with 8/16-bit registers (4 bytes)
			elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh])$ ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			# Handle MOVZX/MOVSX with 32/64-bit registers (4 bytes)
			elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			# Handle MOVSXD (3 bytes)
			elif [[ "$line" =~ ^movsxd[[:space:]]+(r[a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 3))
			# Handle SETCC (3 bytes)
			elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
				text_bytes_len=$((text_bytes_len + 3))
			# Handle floating point instructions (4 bytes each)
			elif [[ "$line" =~ $movss_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $movsd_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $addss_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $addsd_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $mulss_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $mulsd_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $subss_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $subsd_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $divss_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $divsd_rr_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $movsd_mem_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			elif [[ "$line" =~ $cvtsd2si_pattern ]]; then
				text_bytes_len=$((text_bytes_len + 4))
			else
				echo "error: unsupported instruction: '$line'" >&2
				echo "supported instructions: mov, add, sub, cmp, xor, and, or, push, pop, inc, dec, neg, not, call, ret, jmp, je, jne, jg, jl, jge, jle, ja, jb, jae, jbe, jo, jno, js, jns, lea, imul, mul, div, idiv, test, setcc, cmovcc, movzx, movsx, movsxd, shl, shr, sar, and floating point ops" >&2
				return 1
			fi
		else
			echo "error at line $line_number: instruction outside of section: '$line'" >&2
			echo "hint: make sure your code is inside 'section .text' or 'section .data'" >&2
			return 1
		fi
	done

	base_vaddr=0x400000
	file_text_off=0x200 # increased to avoid header overflow
	code_size=$text_bytes_len
	data_size=$((${#data_bytes} / 2))
	file_data_off=$((file_text_off + code_size))
	text_vaddr=$((base_vaddr + file_text_off))
	data_vaddr=$((base_vaddr + file_data_off))
	entry_vaddr=$text_vaddr
	if [[ -n "${labels[_start]:-}" ]]; then
		entry_vaddr=$((text_vaddr + labels[_start]))
	fi

	# second pass: generate machine code hex for each instruction
	text_hex=""
	current_address=0
	for line in "${text_ins[@]}"; do
		# Handle floating point operations with a generalized function approach for register-register ops
		if [[ "$line" =~ $movss_rr_pattern ]]; then
			handle_fp_operation "movss_rr" 4
		elif [[ "$line" =~ $movsd_rr_pattern ]]; then
			handle_fp_operation "movsd_rr" 4
		elif [[ "$line" =~ $addss_rr_pattern ]]; then
			handle_fp_operation "addss_rr" 4
		elif [[ "$line" =~ $addsd_rr_pattern ]]; then
			handle_fp_operation "addsd_rr" 4
		elif [[ "$line" =~ $mulss_rr_pattern ]]; then
			handle_fp_operation "mulss_rr" 4
		elif [[ "$line" =~ $mulsd_rr_pattern ]]; then
			handle_fp_operation "mulsd_rr" 4
		elif [[ "$line" =~ $subss_rr_pattern ]]; then
			handle_fp_operation "subss_rr" 4
		elif [[ "$line" =~ $subsd_rr_pattern ]]; then
			handle_fp_operation "subsd_rr" 4
		elif [[ "$line" =~ $divss_rr_pattern ]]; then
			handle_fp_operation "divss_rr" 4
		elif [[ "$line" =~ $divsd_rr_pattern ]]; then
			handle_fp_operation "divsd_rr" 4
		elif [[ "$line" =~ $movsd_mem_pattern ]]; then
			reg="${BASH_REMATCH[1]}"
			reg2="${BASH_REMATCH[2]}"
			modrm=$((xmm_regs[$reg] << 3 | regs[$reg2]))
			text_hex+="${fp_opcodes["movsd_mem"]}$(printf "%02x" $modrm)"
			current_address=$((current_address + 4))
		elif [[ "$line" =~ $cvtsd2si_pattern ]]; then
			reg="${BASH_REMATCH[1]}"
			xmm="${BASH_REMATCH[2]}"
			modrm=$((0xc0 | regs[$reg] << 3 | xmm_regs[$xmm]))
			text_hex+="${fp_opcodes["cvtsd2si"]}$(printf "%02x" $modrm)"
			current_address=$((current_address + 4))
		elif [[ "$line" =~ ^(movzx|movsx)[[:space:]]+(r[a-z]{2}),[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
			op="${BASH_REMATCH[1]}"
			dst="${BASH_REMATCH[2]}"
			src="${BASH_REMATCH[3]}"
			dst_reg=$(get_reg_num "$dst")
			src_reg=$(get_reg_num "$src")
			if (( dst_reg < 0 )); then
				echo "error at line $line_number: invalid destination register '$dst' in '$line'" >&2
				return 1
			fi
			if (( src_reg < 0 )); then
				echo "error at line $line_number: invalid source register '$src' in '$line'" >&2
				return 1
			fi
			modrm=$((0xc0 | (dst_reg << 3) | src_reg))
			if [[ "$op" == "movzx" ]]; then
				text_hex+=$(printf "480fb6%02x" $modrm)
			else
				text_hex+=$(printf "480fbe%02x" $modrm)
			fi
			current_address=$((current_address + 4))
		elif [[ "$line" =~ ^movsxd[[:space:]]+(r[a-z]{2}),[[:space:]]+([er][a-z]{2})$ ]]; then
			dst="${BASH_REMATCH[1]}"
			src="${BASH_REMATCH[2]}"
			dst_reg=$(get_reg_num "$dst")
			src_reg=$(get_reg_num "$src")
			if (( dst_reg < 0 )); then
				echo "error at line $line_number: invalid destination register '$dst' in '$line'" >&2
				return 1
			fi
			if (( src_reg < 0 )); then
				echo "error at line $line_number: invalid source register '$src' in '$line'" >&2
				return 1
			fi
			modrm=$((0xc0 | (dst_reg << 3) | src_reg))
			text_hex+=$(printf "4863%02x" $modrm)
			current_address=$((current_address + 3))
		elif [[ "$line" =~ ^mov ]]; then
			local mov_operands="${line#mov }"
			local dst="${mov_operands%%,*}"
			local src="${mov_operands#*,}"
			dst=$(trim_string "$dst")
			src=$(trim_string "$src")

			if [[ "$dst" =~ ^r[a-z]{2}$ && "$src" =~ ^r[a-z]{2}$ ]]; then
				# mov reg, reg
				modrm=$((0xc0 + regs[$src] * 8 + regs[$dst]))
				text_hex+=$(printf "4889%02x" "$modrm")
				current_address=$((current_address + 3))
			elif [[ "$dst" =~ ^\[.*\]$ ]]; then # mov [mem], reg
				hex_code=$(assemble_mem_operand "$dst" "${regs[$src]}" "4889")
				text_hex+=$hex_code
				current_address=$((current_address + ${#hex_code}/2))
			elif [[ "$src" =~ ^\[.*\]$ ]]; then # mov reg, [mem]
				hex_code=$(assemble_mem_operand "$src" "${regs[$dst]}" "488b")
				text_hex+=$hex_code
				current_address=$((current_address + ${#hex_code}/2))
			else
				# mov reg, imm
				local reg="$dst"
				local arg="$src"
				local val_is_immediate=0
				local val
				if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
					val=$((16#${BASH_REMATCH[1]}))
					val_is_immediate=1
				elif [[ "$arg" =~ ^-?[0-9]+$ ]]; then
					if [[ "$arg" =~ ^-?(0|[1-9][0-9]*)$ ]]; then
						val=$((arg))
						val_is_immediate=1
					else
						echo "error: invalid integer format '$arg'" >&2
						return 1
					fi
				elif [[ -n "${equs[$arg]:-}" ]]; then
					val=${equs[$arg]}
					if [[ ! "$val" =~ ^-?[0-9]+$ ]]; then
						echo "error: equ '$arg' resolves to non-numeric value" >&2
						return 1
					fi
					val_is_immediate=1
				else
					val_is_immediate=0
				fi

				if [[ "$val_is_immediate" -eq 1 ]]; then
					if (( val >= -2147483648 && val <= 2147483647 )); then
						opcode=$((0xc0 + regs[$reg]))
						text_hex+=$(printf "48c7%02x" "$opcode")$(u32le $val)
						current_address=$((current_address + 7))
					else
						op=$((0xb8 + regs[$reg]))
						text_hex+=$(printf "48%02x" "$op")$(u64le $val)
						current_address=$((current_address + 10))
					fi
				else
					op=$((0xb8 + regs[$reg]))
					if [[ -n "${data_label_off[$arg]:-}" ]]; then
						addr=$((data_vaddr + data_label_off[$arg]))
					elif [[ -n "${labels[$arg]:-}" ]]; then
						addr=$((text_vaddr + labels[$arg]))
					else
						echo "error at line $line_number: unknown label '$arg' in mov instruction '$line'" >&2
						return 1
					fi
					text_hex+=$(printf "48%02x" "$op")$(u64le $addr)
					current_address=$((current_address + 10))
				fi
			fi
		elif [[ "$line" =~ $cmov_pattern ]]; then
			cond="${BASH_REMATCH[1]}"
			dst="${BASH_REMATCH[2]}"
			src="${BASH_REMATCH[3]}"
			case "$cond" in
			e) cc=0x44 ;;
			ne) cc=0x45 ;;
			a) cc=0x47 ;;
			ae) cc=0x43 ;;
			b) cc=0x42 ;;
			be) cc=0x46 ;;
			g) cc=0x4f ;;
			ge) cc=0x4d ;;
			l) cc=0x4c ;;
			le) cc=0x4e ;;
			o) cc=0x40 ;;
			no) cc=0x41 ;;
			s) cc=0x48 ;;
			ns) cc=0x49 ;;
			p) cc=0x4a ;;
			np) cc=0x4b ;;
			*) echo "unknown cmov condition $cond" >&2; return 1 ;;
			esac
			modrm=$((0xc0 | (regs[$dst] << 3) | regs[$src]))
			text_hex+="48"
			text_hex+=$(printf "0f%02x%02x" "$cc" "$modrm")
			current_address=$((current_address + 4))
		elif [[ "$line" =~ ^(syscall|nop|ret|leave|cqo|cdqe)$ ]]; then
			# Handle simple instructions using lookup table
			case "$line" in
				syscall) text_hex+="0f05"; current_address=$((current_address + 2)) ;;
				nop) text_hex+="90"; current_address=$((current_address + 1)) ;;
				ret) text_hex+="c3"; current_address=$((current_address + 1)) ;;
				leave) text_hex+="c9"; current_address=$((current_address + 1)) ;;
				cqo) text_hex+="4899"; current_address=$((current_address + 2)) ;;
				cdqe) text_hex+="4898"; current_address=$((current_address + 2)) ;;
			esac
elif [[ "$line" =~ ^xor[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
			reg="${BASH_REMATCH[1]}"
			modrm=$((0xc0 + regs[$reg] * 8 + regs[$reg]))
			text_hex+=$(printf "4831%02x" $modrm)
			current_address=$((current_address + 3))
				elif [[ "$line" =~ ^push[[:space:]]+(r[a-z]{2})$ ]]; then
			reg="${BASH_REMATCH[1]}"
			op=$((0x50 + regs[$reg]))
			text_hex+=$(printf "%02x" $op)
			current_address=$((current_address + 1))
		elif [[ "$line" =~ ^pop[[:space:]]+(r[a-z]{2})$ ]]; then
			reg="${BASH_REMATCH[1]}"
			op=$((0x58 + regs[$reg]))
			text_hex+=$(printf "%02x" $op)
			current_address=$((current_address + 1))
		elif [[ "$line" =~ ^(add|sub|cmp|or|and) ]]; then
			local op="${BASH_REMATCH[1]}"
			local operands="${line#$op }"
			local dst="${operands%%,*}"
			local src="${operands#*,}"
			dst=$(trim_string "$dst")
			src=$(trim_string "$src")

			if [[ "$dst" =~ ^r[a-z]{2}$ && "$src" =~ ^r[a-z]{2}$ ]]; then
				# op reg, reg
				local reg1="$dst"
				local reg2="$src"
				local modrm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
				case "$op" in
				add) text_hex+=$(printf "4801%02x" $modrm) ;;
				sub) text_hex+=$(printf "4829%02x" $modrm) ;;
				and) text_hex+=$(printf "4821%02x" $modrm) ;;
				or) text_hex+=$(printf "4809%02x" $modrm) ;;
				cmp) text_hex+=$(printf "4839%02x" $modrm) ;;
				esac
				current_address=$((current_address + 3))
			elif [[ "$dst" =~ ^\[.*\]$ || "$src" =~ ^\[.*\]$ ]]; then
				# op with memory
				assemble_arith_mem "$op" "$dst" "$src"
			else
				# op reg, imm
				local reg="$dst"
				local arg="$src"

				if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
					val=$((16#${BASH_REMATCH[1]}))
				elif [[ "$arg" =~ ^[0-9]+$ ]]; then
					val=$((arg))
				else
					echo "error: unknown immediate value '$arg' in '$line'" >&2
					return 1
				fi

				if [[ "$reg" == "rax" ]]; then
					case "$op" in
					add)
						text_hex+="4881c0$(u32le $val)"
						current_address=$((current_address + 7))
						;;
					sub)
						text_hex+="4881e8$(u32le $val)"
						current_address=$((current_address + 7))
						;;
					or)
						text_hex+="4881c8$(u32le $val)"
						current_address=$((current_address + 7))
						;;
					and)
						text_hex+="4881e0$(u32le $val)"
						current_address=$((current_address + 7))
						;;
					cmp)
						text_hex+="483d$(u32le $val)"
						current_address=$((current_address + 6))
						;;
					esac
				else
					op_ext=0
					case "$op" in
					add) op_ext=0 ;;
					sub) op_ext=5 ;;
					cmp) op_ext=7 ;;
					or) op_ext=1 ;;
					and) op_ext=4 ;;
					esac
					modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
					text_hex+=$(printf "4883%02x%02x" "$modrm" "$val")
					current_address=$((current_address + 4))
				fi
			fi
				elif [[ "$line" =~ ^(je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jo|jno|js|jns|jmp|loop|loope|loopne)[[:space:]]+(.*)$ ]]; then
					local op="${BASH_REMATCH[1]}"
					local lbl="${BASH_REMATCH[2]}"
					assemble_short_jump "$op" "$lbl"
				elif [[ "$line" =~ ^(inc|dec|neg|not)[[:space:]]+(r[a-z]{2})$ ]]; then	op="${BASH_REMATCH[1]}"
	reg="${BASH_REMATCH[2]}"
	op_ext=0
	if [[ "$op" == "inc" ]]; then
		modrm=$((0xc0 + regs[$reg]))
		text_hex+=$(printf "48ff%02x" $modrm)
	elif [[ "$op" == "dec" ]]; then
		modrm=$((0xc8 + regs[$reg]))
		text_hex+=$(printf "48ff%02x" $modrm)
	elif [[ "$op" == "neg" ]]; then
		op_ext=3
		modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
		text_hex+=$(printf "48f7%02x" $modrm)
	elif [[ "$op" == "not" ]]; then
		op_ext=2
		modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
		text_hex+=$(printf "48f7%02x" $modrm)
	fi
			current_address=$((current_address + 3))
				elif [[ "$line" =~ ^call[[:space:]]+([.a-zA-Z0-9_]+)$ ]]; then
			lbl="${BASH_REMATCH[1]}"
			if [[ -z "${labels[$lbl]:-}" ]]; then
				echo "error: unknown label '$lbl' in call instruction '$line'" >&2
				return 1
			fi
			target_address=${labels[$lbl]}
			offset=$((target_address - (current_address + 5)))
			text_hex+="e8$(u32le $offset)"
			current_address=$((current_address + 5))
		elif [[ "$line" =~ ^(mul|div|idiv)[[:space:]]+(r[a-z]{2})$ ]]; then
			op="${BASH_REMATCH[1]}"
			reg="${BASH_REMATCH[2]}"
			op_ext=0
			case "$op" in
			mul) op_ext=4 ;;
			div) op_ext=6 ;;
			idiv) op_ext=7 ;;
			esac
			modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
			text_hex+=$(printf "48f7%02x" $modrm)
			current_address=$((current_address + 3))
				elif [[ "$line" =~ ^imul[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
			reg1="${BASH_REMATCH[1]}"
			reg2="${BASH_REMATCH[2]}"
			modrm=$((0xc0 | (regs[$reg1] << 3) | regs[$reg2]))
			text_hex+=$(printf "480faf%02x" $modrm)
			current_address=$((current_address + 4))
		elif [[ "$line" =~ ^lea[[:space:]]+(r[a-z]{2}),[[:space:]]+\[([a-zA-Z0-9_]+)\]$ ]]; then
			reg="${BASH_REMATCH[1]}"
			lbl="${BASH_REMATCH[2]}"
			if [[ -z "${data_label_off[$lbl]:-}" ]]; then
				echo "unknown label $lbl" >&2
				return 1
			fi
			addr=$((data_vaddr + data_label_off[$lbl]))
			modrm=$(((regs[$reg] << 3) | 5))
			text_hex+=$(printf "488d%02x" $modrm)
			# RIP-relative addressing, offset is from the *next* instruction
			offset=$((addr - (text_vaddr + current_address + 7)))
			text_hex+=$(u32le $offset)
			current_address=$((current_address + 7))
elif [[ "$line" =~ ^(shl|shr|sar)[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+)$ ]]; then
	op="${BASH_REMATCH[1]}"
	reg="${BASH_REMATCH[2]}"
	val="${BASH_REMATCH[3]}"
	op_ext=0
	if [[ "$op" == "shl" ]]; then
		op_ext=4
	elif [[ "$op" == "shr" ]]; then
		op_ext=5
	elif [[ "$op" == "sar" ]]; then
		op_ext=7
	fi
	modrm=$((0xc0 | (op_ext << 3) | regs[$reg]))
	text_hex+=$(printf "48c1%02x%02x" $modrm $val)
			current_address=$((current_address + 4))
		elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+(r[a-z]{2})$ ]]; then
			reg1="${BASH_REMATCH[1]}"
			reg2="${BASH_REMATCH[2]}"
			modrm=$((0xc0 | (regs[$reg2] << 3) | regs[$reg1]))
			text_hex+=$(printf "4885%02x" $modrm)
			current_address=$((current_address + 3))
				elif [[ "$line" =~ ^test[[:space:]]+(r[a-z]{2}),[[:space:]]+([0-9]+|0x[0-9a-fA-F]+)$ ]]; then
			reg="${BASH_REMATCH[1]}"
			arg="${BASH_REMATCH[2]}"
			if [[ "$arg" =~ ^0x([0-9a-fA-F]+)$ ]]; then
				val=$((16#${BASH_REMATCH[1]}))
			else
				val=$((arg))
			fi
			modrm=$((0xc0 | regs[$reg]))
							text_hex+=$(printf "48f7%02x" "$modrm")$(u32le "$val")
						current_address=$((current_address + 7))
					elif [[ "$line" =~ ^set(e|ne|a|ae|b|be|g|ge|l|le|z|nz|o|no|s|ns)[[:space:]]+([ab][lh]|[cd][lh]|r[a-z]{2})$ ]]; then
			cond="${BASH_REMATCH[1]}"
			dst="${BASH_REMATCH[2]}"
			dst_reg=$(get_reg_num "$dst")
			if (( dst_reg < 0 )); then
				echo "error at line $line_number: invalid register '$dst' in '$line'" >&2
				return 1
			fi
			modrm=$((0xc0 | dst_reg))
			
			case "$cond" in
			e|z) text_hex+=$(printf "0f94%02x" $modrm) ;;
			ne|nz) text_hex+=$(printf "0f95%02x" $modrm) ;;
			a) text_hex+=$(printf "0f97%02x" $modrm) ;;
			ae) text_hex+=$(printf "0f93%02x" $modrm) ;;
			b) text_hex+=$(printf "0f92%02x" $modrm) ;;
			be) text_hex+=$(printf "0f96%02x" $modrm) ;;
			g) text_hex+=$(printf "0f9f%02x" $modrm) ;;
			ge) text_hex+=$(printf "0f9d%02x" $modrm) ;;
			l) text_hex+=$(printf "0f9c%02x" $modrm) ;;
			le) text_hex+=$(printf "0f9e%02x" $modrm) ;;
			o) text_hex+=$(printf "0f90%02x" $modrm) ;;
			no) text_hex+=$(printf "0f91%02x" $modrm) ;;
			s) text_hex+=$(printf "0f98%02x" $modrm) ;;
			ns) text_hex+=$(printf "0f99%02x" $modrm) ;;
			esac
			current_address=$((current_address + 3))
		else
			echo "internal error assembling: $line" >&2
			return 1
		fi
	done

	tmpf="$(mktemp)" || { echo "error: failed to create temporary file" >&2; return 1; }
	# build elf header in hex
	header_hex=""
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
	filesz=$((file_data_off + data_size))
	header_hex+="$(u64le $filesz)"
	header_hex+="$(u64le $filesz)"
	header_hex+="$(u64le 0x200000)"

	hex_to_bin "$header_hex" >"$tmpf"

	# Calculate expected header size from hex string length (each 2 hex chars = 1 byte)
	cur_size=$((${#header_hex} / 2))
	if ((cur_size > file_text_off)); then
		echo "header too big" >&2
		return 1
	fi
	pad=$((file_text_off - cur_size))
	generate_zeros "$pad" >>"$tmpf"

	hex_to_bin "$text_hex" >>"$tmpf"
	hex_to_bin "$data_bytes" >>"$tmpf"

	# Calculate expected total size: header + padding + text + data
	text_size=$((${#text_hex} / 2))
	data_size=$((${#data_bytes} / 2))
	actual_size=$((file_text_off + text_size + data_size))
	
	if [ "$actual_size" -ne "$filesz" ]; then
		filesz=$actual_size
		seek=$((0x38))
		pf="$(u64le "$filesz")$(u64le "$filesz")"
		# Create a temporary file with the binary data, then write at specific offset using pure bash
		local temp_bin
		temp_bin=$(mktemp) || { echo "error: failed to create temporary file for patch" >&2; rm -f "$tmpf"; return 1; }
		hex_to_bin "$pf" > "$temp_bin"
		write_at_offset "$temp_bin" "$tmpf" "$seek"
		rm -f "$temp_bin"
	fi

	chmod +x "$tmpf"
	mv -f "$tmpf" "$outfile"
	return 0
}

