#!/usr/bin/env bash
# trace-cmd.sh — расширенный трассировщик команды

set -euo pipefail

#-------- цвета --------
if [[ -t 1 && ${NO_COLOR:-} != 1 ]]; then
  sbg=$'\e[7;1m'  ebg=$'\e[m'
  sdbg=$'\e[7;3m' df=$'\e[3m'
else
  sbg= ebg= sdbg= df=
fi

#-------- утилиты --------
die(){ echo "$*" >&2; exit 1; }
check(){ command -v "$1" &>/dev/null; }

#-------- аргументы --------
[[ $# -eq 1 ]] || die "Usage: $0 COMMAND"
CMD=$1

#-------- заголовок --------
echo -e "${sbg}Extended trace for '${CMD}'${ebg}\n"

#-------- функция-обёртка --------
run_or_skip(){
  local msg=$1; shift
  echo -e "${sbg}$msg${ebg} ${sdbg}$*${ebg}"
  if "$@"; then true; else
    echo -e "\t${df}skipped (non-zero exit)${ebg}"
  fi
}

#-------- which --------
run_or_skip "Executable path" "which" "-a" "$CMD"

#-------- type (aliases/functions) --------
echo -e "${sbg}Shell type information${ebg}"
type -a "$CMD" 2>/dev/null || echo -e "\t${df}no type info found${ebg}"

#-------- command -v --------
echo -e "${sbg}Command location (command -v)${ebg}"
command -v "$CMD" || echo -e "\t${df}not found in PATH${ebg}"

#-------- whereis --------
run_or_skip "Source/man pages" "whereis" "$CMD" \
  | tr ' ' '\n' | grep -v '^$' || true

#-------- apropos --------
run_or_skip "Manual pages" "apropos" "-f" "$CMD"

#-------- locate --------
if check locate; then
  run_or_skip "File locations (locate)" "locate" "/$CMD"
else
  echo -e "${sbg}File locations (locate)${ebg} ${df}locate not found${ebg}"
fi

#-------- file type --------
if CMD_PATH=$(command -v "$CMD" 2>/dev/null); then
  echo -e "${sbg}File type${ebg}"
  file "$CMD_PATH"
  
  echo -e "${sbg}File details (ls -l)${ebg}"
  ls -l "$CMD_PATH"
  
  echo -e "${sbg}MD5 checksum${ebg}"
  md5sum "$CMD_PATH"
fi

#-------- package info --------
if CMD_PATH=$(command -v "$CMD" 2>/dev/null); then
  echo -e "${sbg}Package information${ebg}"
  
  # Debian/Ubuntu
  if check dpkg; then
    dpkg -S "$CMD_PATH" 2>/dev/null || echo -e "\t${df}not found in dpkg${ebg}"
  fi
  
  # RHEL/CentOS/Fedora
  if check rpm; then
    rpm -qf "$CMD_PATH" 2>/dev/null || echo -e "\t${df}not found in rpm${ebg}"
  fi
fi

#-------- systemd units --------
echo -e "${sbg}Systemd units${ebg}"
if check systemctl; then
  systemctl list-units --all | grep -i "$CMD" || echo -e "\t${df}no systemd units found${ebg}"
else
  echo -e "\t${df}systemctl not available${ebg}"
fi

#-------- journalctl --------
echo -e "${sbg}Journal entries (last week)${ebg}"
if check journalctl; then
  journalctl -q --since "1 week ago" | grep -i "$CMD" | tail -20 || echo -e "\t${df}no recent journal entries${ebg}"
else
  echo -e "\t${df}journalctl not available${ebg}"
fi

#-------- history --------
echo -e "${sbg}Shell history${ebg}"
for h in "$HOME/.bash_history" /root/.bash_history; do
  [[ -r $h ]] && grep -Hn -- "$CMD" "$h" 2>/dev/null || true
done
# дополнительные истории
find /root /home -type f -readable -name '*history*' 2>/dev/null \
  -exec grep -Hn -- "$CMD" {} \+ 2>/dev/null || true

#-------- логи --------
echo -e "${sbg}Log files${ebg}"
find /var/log -type f -readable -name '*.log' 2>/dev/null \
  -exec grep -Hn -- "$CMD" {} \+ 2>/dev/null || true

echo -e "\n${sbg}Done${ebg}"