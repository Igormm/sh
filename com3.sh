#!/usr/bin/env sh

# Function to print success messages
success() {
    printf "✅ %s\n" "$1"
}

# Function to print error messages
error() {
    printf "❌ %s\n" "$1" >&2
}

# Function to print info messages
info() {
    printf "ℹ️  %s\n" "$1"
}

# Function to print section headers
section() {
    printf "\n%s\n" "$1"
}

# Validate arguments
if [ $# -ne 1 ]; then
    error "Usage: $(basename "$0") <command_name>"
    error "   Please provide exactly one command to check"
    exit 1
fi

commd="$1"

# Check for empty string
if [ -z "$commd" ]; then
    error "Command name cannot be empty"
    exit 1
fi

# Check for spaces in command name
case "$commd" in
    *[[:space:]]*)
        error "Command name cannot contain spaces"
        error "   Got: '$commd'"
        exit 1
        ;;
esac

# Check command name length
if [ ${#commd} -gt 50 ]; then
    info "Warning: Command name is unusually long (${#commd} characters)"
fi

# Function to check command in specific shell
check_command_in_shell() {
    local shell_path="$1"
    local shell_name="$2"
    
    case "$shell_name" in
        *zsh*|*bash*)
            # Supports -ic and command -V
            if output=$("$shell_path" -ic "command -V '$commd'" 2>&1); then
                success "$output"
            else
                error "Not found in $shell_name"
            fi
            ;;
        *ksh*)
            # Often lacks command -V, use type instead
            if output=$("$shell_path" -ic "type '$commd'" 2>&1); then
                success "$output"
            else
                error "Not found in $shell_name"
            fi
            ;;
        *dash*)
            # Dash doesn't support -i for interactivity, use -c
            if output=$("$shell_path" -c "type '$commd'" 2>&1); then
                success "$output"
            else
                error "Not found in $shell_name"
            fi
            ;;
        *)
            # Try -ic first, fallback to -c
            if "$shell_path" -ic ":" 2>/dev/null; then
                # Interactive mode supported
                if output=$("$shell_path" -ic "command -V '$commd' || type '$commd'" 2>&1); then
                    success "$output"
                else
                    error "Not found in $shell_name"
                fi
            else
                # Non-interactive mode only
                if output=$("$shell_path" -c "command -V '$commd' 2>&1; [ \$? -ne 0 ] && type '$commd' 2>&1"); then
                    success "$output"
                else
                    error "Not found or error in $shell_name"
                fi
            fi
            ;;
    esac
}

# Main checks
section "🔍 Command type:"
if [ -f /etc/shells ]; then
    while IFS= read -r shell_path; do
        [ -n "$shell_path" ] || continue
        printf "🔧 Shell: %s\n" "$shell_path"
        shell_name=$(basename "$shell_path")
        check_command_in_shell "$shell_path" "$shell_name"
    done < /etc/shells
fi

section "⚡ What is:"
whatis_output=$(command whatis "$commd" 2>/dev/null)
if [ -n "$whatis_output" ]; then
    printf "%s\n" "$whatis_output"
else
    printf "(no whatis entry)\n"
fi

section "📂 Where is:"
whereis_output=$(command whereis "$commd")
printf "%s\n" "$whereis_output"

section "💬 Help:"
help_output=$(command help "$commd" 2>/dev/null | head -2)
if [ -n "$help_output" ]; then
    printf "%s\n" "$help_output"
else
    printf "(no built-in help)\n"
fi

section "📘 Man pages:"
man_output=$(command man -f "$commd" 2>/dev/null)
if [ -n "$man_output" ]; then
    printf "%s\n" "$man_output"
else
    printf "(no man pages found)\n"
fi

section "📋 Command list:"
compgen_output=$(command compgen -c | command grep -w "$commd" 2>/dev/null)
if [ -n "$compgen_output" ]; then
    printf "%s\n" "$compgen_output"
else
    printf "(not found in compgen list)\n"
fi

section "🔗 Apropos (related):"
apropos_output=$(command apropos "$commd" 2>/dev/null | head -5)
if [ -n "$apropos_output" ]; then
    printf "%s\n" "$apropos_output"
else
    printf "(no apropos results)\n"
fi