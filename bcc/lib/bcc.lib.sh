#!/usr/bin/env bash

# Source basm library to use its assembler functionality
source "$(dirname "${BASH_SOURCE[0]}")/basm.lib.sh"

# Function to call the basm assembler from file
basm_assemble_from_file() {
    local infile="$1"
    local outfile="$2"
    
    local code=$(< "$infile")
    basm_assemble "$code" "$outfile"
}

# Function to process includes - for now we'll just handle stdio.h specially
process_includes() {
    local c_code="$1"
    local processed_code=""
    
    mapfile -t lines <<< "$c_code"
    
    for line in "${lines[@]}"; do
        # Check for #include directives
        if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*include[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
            local header="${BASH_REMATCH[1]}"
            # Just skip the include line for now
            continue
        elif [[ "$line" =~ ^[[:space:]]*#[[:space:]]*include[[:space:]]*\< ]]; then
            # For angle-bracket includes like #include <stdio.h>
            # Just skip the include line for now
            continue
        else
            # Add the line as-is
            processed_code+="$line"$'\n'
        fi
    done
    
    echo -n "$processed_code"
}

# Main function to compile C code to assembly
bcc_compile_c_to_asm() {
    local c_code="${1:-""}"
    
    # Process includes first
    local processed_code
    processed_code=$(process_includes "$c_code")
    
    # This is the main function that will parse C code and generate x86-64 assembly
    # For now, let's implement a very basic C compiler that can handle a simple hello world
    
    mapfile -t lines <<< "$processed_code"
    
    # Initialize an array to store all assembly lines
    # Start with sections to ensure the assembler recognizes them
    local asm_lines=()
    asm_lines+=("section .data")
    # Don't add comment in data section since assembler might not recognize it
    
    # Process the C code to extract strings and other data
    local in_function=0
    local current_function=""
    local function_body=""
    local found_main=0
    local msg_counter=0  # For multiple messages
    
    for line in "${lines[@]}"; do
        # Clean the line but preserve the full original for pattern matching
        local original_line="$line"
        local clean_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/\/\/.*//')
        
        # Skip empty lines
        [ -z "$clean_line" ] && continue
        
        # Look for main function - can be with or without arguments
        if [[ "$clean_line" == *"int main"* ]] && [[ "$clean_line" == *") {"* ]]; then
            found_main=1
            # Add text section after we're done with data
            # We'll add it when we start processing the main function body
            break  # We'll continue after adding text section
        fi
        
        # Also check for main without explicit int return type
        if [[ "$clean_line" == *"main("* ]] && [[ "$clean_line" == *") {"* ]]; then
            found_main=1
            break  # We'll continue after adding text section
        fi
    done
    
    # Restart processing to handle main function and its body
    mapfile -t lines <<< "$processed_code"
    local processed_main_found=0
    
    for line in "${lines[@]}"; do
        # Clean the line but preserve the full original for pattern matching
        local original_line="$line"
        local clean_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/\/\/.*//')
        
        # Skip empty lines
        [ -z "$clean_line" ] && continue
        
        # Look for main function - can be with or without arguments
        if [[ "$clean_line" == *"int main"* ]] && [[ "$clean_line" == *") {"* ]]; then
            processed_main_found=1
            asm_lines+=("section .text")
            asm_lines+=("global _start")
            asm_lines+=("_start:")
            continue
        fi
        
        # Also check for main without explicit int return type
        if [[ "$clean_line" == *"main("* ]] && [[ "$clean_line" == *") {"* ]]; then
            processed_main_found=1
            asm_lines+=("section .text")
            asm_lines+=("global _start")
            asm_lines+=("_start:")
            continue
        fi
        
        # If we're in main function, look for printf or puts calls
        if [ $processed_main_found -eq 1 ]; then
            # Handle simple printf("hello world\n");
            if [[ "$clean_line" == *"printf("* ]] && [[ "$clean_line" == *");"* ]]; then
                # Extract the string inside printf using sed
                local full_match=$(echo "$clean_line" | sed -n 's/.*printf[[:space:]]*([[:space:]]*"\(.*\)"[[:space:]]*);.*/\1/p')
                if [ -n "$full_match" ]; then
                    # Process escape sequences in the string
                    # Replace \n with actual newlines for proper handling
                    local msg="$full_match"
                    # Use printf to interpret escape sequences
                    msg=$(printf '%b' "$msg")
                    
                    # Add message to data section
                    local msg_name="msg$msg_counter"
                    # Insert these lines after the "section .data" line
                    local new_asm_lines=()
                    local data_inserted=0
                    for asm_line in "${asm_lines[@]}"; do
                        if [[ "$asm_line" == "section .data" ]] && [ $data_inserted -eq 0 ]; then
                            new_asm_lines+=("$asm_line")
                            new_asm_lines+=("$msg_name db \"$msg\", 10")  # Use decimal 10 instead of 0xa
                            new_asm_lines+=("len$msg_counter equ \$ - $msg_name")
                            data_inserted=1
                        else
                            new_asm_lines+=("$asm_line")
                        fi
                    done
                    if [ $data_inserted -eq 0 ]; then
                        # If section .data was not found, add it at the top
                        asm_lines=("section .data" "$msg_name db \"$msg\", 10" "len$msg_counter equ \$ - $msg_name" "${asm_lines[@]}")
                    else
                        asm_lines=("${new_asm_lines[@]}")
                    fi
                    ((msg_counter++))
                    
                    # Add assembly code to print the message
                    asm_lines+=("    mov rax, 1          ; syscall: write")
                    asm_lines+=("    mov rdi, 1          ; file descriptor: stdout")
                    asm_lines+=("    mov rsi, $msg_name  ; pointer to message")
                    asm_lines+=("    mov rdx, len$((msg_counter-1))        ; message length")
                    asm_lines+=("    syscall             ; invoke syscall")
                fi
            fi
            
            # Look for simple return statement
            if [[ "$clean_line" == *"return "* ]] && [[ "$clean_line" == *";"* ]]; then
                if [[ "$clean_line" =~ [0-9]+ ]]; then
                    asm_lines+=("    mov rax, 60         ; syscall: exit")
                    asm_lines+=("    mov rdi, 0          ; exit code 0")
                    asm_lines+=("    syscall")
                fi
            fi
            
            # Handle exit(0) call
            if [[ "$clean_line" == *"exit("* ]] && [[ "$clean_line" == *");"* ]]; then
                asm_lines+=("    mov rax, 60         ; syscall: exit")
                asm_lines+=("    mov rdi, 0          ; exit code 0")
                asm_lines+=("    syscall")
            fi
        fi
    done
    
    # If no return/exit was found, add exit syscall
    local has_exit=0
    for asm_line in "${asm_lines[@]}"; do
        if [[ "$asm_line" =~ "mov rax, 60" ]]; then
            has_exit=1
            break
        fi
    done
    
    if [ $has_exit -eq 0 ]; then
        asm_lines+=("    mov rax, 60         ; syscall: exit")
        asm_lines+=("    mov rdi, 0          ; exit code 0")
        asm_lines+=("    syscall")
    fi
    
    # Combine all lines with proper newlines
    local result=""
    for asm_line in "${asm_lines[@]}"; do
        result+="$asm_line"$'\n'
    done
    
    echo -n "$result"
}