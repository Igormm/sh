# bash completion для mytool

_mytool()
{
    local cur prev words cword
    _init_completion -n : || return

    # Имя команды
    local cmd="${COMP_WORDS[0]}"

    # Если нет подкоманды — подсказываем список команд
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        # Вызов mytool list-commands для получения списка
        local cmds
        cmds="$("$cmd" list-commands 2>/dev/null)"
        COMPREPLY=( $(compgen -W "$cmds help list-commands -h --help -V --version" -- "$cur") )
        return
    fi

    # Есть подкоманда
    local subcmd="${COMP_WORDS[1]}"

    case "$subcmd" in
        help)
            # после help подсказывать команды
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                local cmds
                cmds="$("$cmd" list-commands 2>/dev/null)"
                COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
            fi
            ;;
        build)
            # простейший пример: окружения
            local envs="dev stage prod"
            COMPREPLY=( $(compgen -W "$envs" -- "$cur") )
            ;;
        deploy)
            local envs="dev stage prod"
            COMPREPLY=( $(compgen -W "$envs" -- "$cur") )
            ;;
        *)
            # по умолчанию — completion по файлам
            COMPREPLY=( $(compgen -f -- "$cur") )
            ;;
    esac
}

complete -F _mytool mytool