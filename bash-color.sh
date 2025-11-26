#!/usr/bin/env bash

set -euo pipefail

RESET="\e[0m"

print_colored_string() {
    local code="$1"
    local text="$2"
    echo -e "${code}${text}${RESET}"
}

make_ansi_colored_code() {
    if [[ $# -eq 1 ]]; then
        echo -ne "\e[${1}m"
    else
        echo -ne "\e[${1};${2}m"
    fi
}

if [[ $# -eq 0 ]]; then
    echo "Нужен 1 или 2 аргумента (числа)." >&2
    exit 1
fi

CODE=$(make_ansi_colored_code "$@")

# красим stdin
if ! [ -t 0 ]; then
    while IFS= read -r line; do
        print_colored_string "$CODE" "$line"
    done
    exit 0
fi
