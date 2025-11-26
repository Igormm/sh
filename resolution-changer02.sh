#!/usr/bin/env bash
# change-display-resolution.sh
# Установка произвольного режима отображения
# Поддержка: X11 (xrandr), Wayland (wlr-randr, kscreen-doctor)
# 2025-ready
set -Eeuo pipefail

# ---------------------- CONFIG ----------------------
readonly DEFAULT_REFRESH_RATE=60
readonly DEFAULT_MONITOR_PORT="VGA-0"
readonly LOG_FILE="${HOME}/.change-display-resolution.log"
# ----------------------------------------------------

# ---------- LOGGER / DRY-RUN / HELPERS ------------
DRY_RUN=0
WAYLAND_BACKEND=""
log() {
    local ts
    ts=$(date '+%F %T')
    printf '[%s] %s\n' "$ts" "$*" | tee -a "$LOG_FILE" >&2
}
run_cmd() {
    local comment=$1; shift
    log "CMD: $comment: $*"
    (( DRY_RUN )) && return 0
    "$@"
}
error() { log "ERROR: $*"; exit 1; }
cmd_ok() { command -v "$1" >/dev/null 2>&1; }

# ------------------ CLI PARSER --------------------
usage() {
    cat <<EOF
Использование:
  $0 [ОПЦИИ] <X> <Y> [MONITOR_OUTPUT] [REFRESH]
Опции:
  -n, --dry-run      показать команды, не применять
  -l, --log FILE     путь к лог-файлу (по умолчанию: $LOG_FILE)
  -h, --help         эта справка
EOF
    exit 1
}

ARGS=()
while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1; shift ;;
        -l|--log)     LOG_FILE=${2:?}; shift 2 ;;
        -h|--help)    usage ;;
        -*)           echo "Неизвестная опция: $1" >&2; usage ;;
        *)            ARGS+=("$1"); shift ;;
    esac
done
set -- "${ARGS[@]}"
((${#ARGS[@]} < 2 || ${#ARGS[@]} > 4)) && usage

# ------------------ VALIDATION --------------------
X_RES=$1; Y_RES=$2; MONITOR_OUTPUT=${3:-$DEFAULT_MONITOR_PORT}; REFRESH=${4:-$DEFAULT_REFRESH_RATE}

[[ $X_RES =~ ^[1-9][0-9]{0,4}$ ]]   || error "X должен быть целым 1-99999"
[[ $Y_RES =~ ^[1-9][0-9]{0,4}$ ]]   || error "Y должен быть целым 1-99999"
[[ $REFRESH =~ ^([1-9][0-9]?|1000)$ ]] || error "Частота должна быть 1-1000 Гц"

touch "$LOG_FILE" 2>/dev/null || LOG_FILE=/dev/null
log "---------- START ----------"
log "Параметры: ${X_RES}x${Y_RES}@${REFRESH}  out=${MONITOR_OUTPUT}  dry-run=${DRY_RUN}"

# --------------- BACKEND AUTO-DETECT --------------
detect_backend() {
    case ${XDG_SESSION_TYPE:-} in
        x11|wayland) WAYLAND_BACKEND=$XDG_SESSION_TYPE ;;
    esac
    if [[ -n ${DISPLAY:-} ]]; then
        WAYLAND_BACKEND=x11
    elif [[ -n ${WAYLAND_DISPLAY:-} ]]; then
        if cmd_ok swaymsg; then WAYLAND_BACKEND=sway
        elif cmd_ok wlr-randr; then WAYLAND_BACKEND=wlr
        elif cmd_ok kscreen-doctor; then WAYLAND_BACKEND=kde
        else WAYLAND_BACKEND=wayland-unknown
        fi
    else
        WAYLAND_BACKEND=unknown
    fi
}
detect_backend
log "Backend: $WAYLAND_BACKEND"

# ------------------ XRANDR BACKEND ------------------
apply_x11_xrandr() {
    cmd_ok xrandr || error "xrandr не найден"
    xrandr >/dev/null 2>&1 || error "xrandr не может получить информацию о дисплее"

    if ! grep -qE "^${MONITOR_OUTPUT}[[:space:]]" < <(xrandr --query); then
        log "Доступные выходы:"
        xrandr --query | awk '/ connected| disconnected/ {print "  "$1" ("$2")"}' >&2
        error "Выход '$MONITOR_OUTPUT' не найден"
    fi

    local gen= line= name=
    if cmd_ok cvt; then
        line=$(cvt "$X_RES" "$Y_RES" "$REFRESH" | sed -n '2s/^[[:space:]]*Modeline[[:space:]]*//p')
        gen=cvt
    elif cmd_ok gtf; then
        line=$(gtf "$X_RES" "$Y_RES" "$REFRESH" | sed -n '3s/^[[:space:]]*Modeline[[:space:]]*//p')
        gen=gtf
    fi
    [[ -z $line ]] && error "Не удалось сгенерировать Modeline"
    name=${line%% *}
    log "X11: утилита=$gen  Modeline=$line  name=$name"

    if ! xrandr --query | grep -qF "\"$name\""; then
        run_cmd "Создание режима" xrandr --newmode $line
    else
        log "Режим '$name' уже существует"
    fi

    if ! xrandr --query | awk -v out=$MONITOR_OUTPUT '
        $1==out{f=1;next} f&&NF==0{f=0} f&&$0~name{exit 0} END{exit 1}' name="+$name"; then
        run_cmd "Привязка режима" xrandr --addmode "$MONITOR_OUTPUT" "$name"
    else
        log "Режим '$name' уже привязан"
    fi

    run_cmd "Установка режима" xrandr --output "$MONITOR_OUTPUT" --mode "$name"
    log "X11: готово ${X_RES}x${Y_RES}@${REFRESH} на $MONITOR_OUTPUT"
}

# ----------------- WAYLAND HELPERS ------------------
wl_output_ok() {
    local out=$1 tool=$2
    local list
    list=$($tool 2>/dev/null) || return 1
    grep -qE "^${out}[[:space:]]" <<<"$list"
}

# -------------- WLROOTS / SWAY BACKEND --------------
apply_wayland_wlr() {
    cmd_ok wlr-randr || error "wlr-randr не найден"
    wl_output_ok "$MONITOR_OUTPUT" wlr-randr || {
        wlr-randr | grep '^[^ ]' >&2
        error "Выход '$MONITOR_OUTPUT' не найден в wlr-randr"
    }
    local mode=${X_RES}x${Y_RES}@${REFRESH}
    run_cmd "Wayland(wlr-randr): установка режима" \
        wlr-randr --output "$MONITOR_OUTPUT" --mode "$mode"
    log "Wayland(wlr-randr): готово $mode на $MONITOR_OUTPUT"
}

# ---------------- KDE / KSCREEN-DOCTOR --------------
apply_wayland_kde() {
    cmd_ok kscreen-doctor || error "kscreen-doctor не найден"
    local info
    info=$(kscreen-doctor -o 2>/dev/null) || error "kscreen-doctor не вернул данные"
    grep -q "output.${MONITOR_OUTPUT}." <<<"$info" || {
        grep -o 'output\.[^ ]*' <<<"$info" | sort -u >&2
        error "Выход '$MONITOR_OUTPUT' не найден в kscreen-doctor"
    }
    local mode=${X_RES}x${Y_RES}
    grep -q "$mode" <<<"$info" || {
        error "Режим $mode не найден для $MONITOR_OUTPUT (kscreen-doctor не умеет создавать произвольные)"
    }
    run_cmd "Wayland(KDE): установка режима" \
        kscreen-doctor "output.${MONITOR_OUTPUT}.mode.${mode}"
    log "Wayland(KDE): установлен $mode на $MONITOR_OUTPUT"
}

# --------------------- MAIN DISPATCH ----------------
case $WAYLAND_BACKEND in
    x11)      apply_x11_xrandr ;;
    sway|wlr) apply_wayland_wlr ;;
    kde)      apply_wayland_kde ;;
    wayland-unknown) error "Wayland-композитор не поддерживается (нужен wlr-randr или kscreen-doctor)" ;;
    unknown)  error "Не удалось определить сессию (X11/Wayland)" ;;
    *)        error "Внутренняя ошибка: неизвестный backend '$WAYLAND_BACKEND'" ;;
esac

log "---------- DONE ----------"
