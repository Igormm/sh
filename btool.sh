#!/usr/bin/env bash
set -euo pipefail

# Путь к директории скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Файл с функциями/подкомандами
COMMANDS_FILE="${SCRIPT_DIR}/btool.sh"

# Проверка наличия файла с командами
if [[ -f "$COMMANDS_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$COMMANDS_FILE"
else
    echo "Файл с командами не найден: $COMMANDS_FILE" >&2
    exit 1
fi

# Общие опции
MYTOOL_VERSION="0.1.0"

usage() {
    cat <<EOF
Использование: $(basename "$0") <команда> [опции]

Команды:
  help                Показать эту справку
  list-commands       Показать список доступных команд

$(mytool_list_commands_descriptions)

Общие опции:
  -h, --help          Показать помощь
  -V, --version       Показать версию

EOF
}

version() {
    echo "$(basename "$0") версия ${MYTOOL_VERSION}"
}

# Стандартные служебные команды (могут переопределяться в btool.sh)
mytool_list_commands() {
    # Должна вывести список ИМЕН команд через пробел
    # Базовые команды:
    echo "help list-commands"
    # Пользовательские:
    if declare -F mytool_user_list_commands >/dev/null 2>&1; then
        mytool_user_list_commands
    fi
}

mytool_list_commands_descriptions() {
    if declare -F mytool_user_list_commands_descriptions >/dev/null 2>&1; then
        mytool_user_list_commands_descriptions
    fi
}

mytool_dispatch() {
    local cmd="$1"
    shift || true

    case "$cmd" in
        help|-h|--help|"")
            usage
            ;;
        -V|--version|version)
            version
            ;;
        list-commands)
            mytool_list_commands
            ;;
        *)
            # Ожидается функция формата: mytool_cmd_<имя>
            local func="mytool_cmd_${cmd//-/_}"
            if declare -F "$func" >/dev/null 2>&1; then
                "$func" "$@"
            else
                echo "Неизвестная команда: $cmd" >&2
                echo "Смотри: $(basename "$0") help" >&2
                exit 1
            fi
            ;;
    esac
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    local cmd="$1"
    shift

    mytool_dispatch "$cmd" "$@"
}

main "$@"