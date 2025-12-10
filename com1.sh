#!/usr/bin/env sh

# Проверка количества аргументов
if [ $# -ne 1 ]; then
	printf "❌ Usage: %s <command_name>\n" "$(basename "$0")" >&2
	printf "   Please provide exactly one command to check\n" >&2
	exit 1
fi

command="$1"

# Проверка на пустую строку
if [ -z "$command" ]; then
	printf "❌ Error: Command name cannot be empty\n" >&2
	exit 1
fi

# Проверка на пробелы в имени команды
case "$command" in
*[[:space:]]*)
	printf "❌ Error: Command name cannot contain spaces\n" >&2
	printf "   Got: '%s'\n" "$command" >&2
	exit 1
	;;
esac

# Проверка, что это одно слово (только буквы, цифры, подчеркивания, дефисы)
# Это необязательная проверка, но хорошая практика
if ! echo "$command" | grep -q '^[[:alnum:]_-]\+$'; then
	printf "⚠️  Warning: Command name contains special characters\n" >&2
	printf "   This might not be a valid command name\n" >&2
	# Не выходим, просто предупреждаем
fi

# Проверка длины (опционально, обычно команды не очень длинные)
if [ ${#command} -gt 50 ]; then
	printf "⚠️  Warning: Command name is unusually long (%d characters)\n" ${#command} >&2
fi

# Основные проверки
printf "🔍 Type:\n"
magn=$({
	command type "$command" || command whereis "$command"
} 2>/dev/null)
printf "%s\n" "$magn"

printf "⚡ What is:\n"
whatis_output=$(command whatis "$command" 2>/dev/null)
if [ -n "$whatis_output" ]; then
	printf "%s\n" "$whatis_output"
else
	printf "(no whatis entry)\n"
fi

printf "📂 Where is:\n"
whereis_output=$(command whereis "$command")
printf "%s\n" "$whereis_output"

printf "💬 Help:\n"
help_output=$(command help "$command" 2>/dev/null | head -2)
if [ -n "$help_output" ]; then
	printf "%s\n" "$help_output"
else
	printf "(no built-in help)\n"
fi

printf "📘 Man pages:\n"
man_output=$(command man -f "$command" 2>/dev/null)
if [ -n "$man_output" ]; then
	printf "%s\n" "$man_output"
else
	printf "(no man pages found)\n"
fi

printf "📋 Command list:\n"
compgen_output=$(command compgen -c | command grep -w "$command" 2>/dev/null)
if [ -n "$compgen_output" ]; then
	printf "%s\n" "$compgen_output"
else
	printf "(not found in compgen list)\n"
fi

printf "🔗 Apropos (related):\n"
apropos_output=$(command apropos "$command" 2>/dev/null | head -5)
if [ -n "$apropos_output" ]; then
	printf "%s\n" "$apropos_output"
else
	printf "(no apropos results)\n"
fi
