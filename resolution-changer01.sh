#!/usr/bin/env bash
# change-display-resolution.sh
# Установка произвольного режима отображения
# Поддержка: X11 (xrandr), Wayland (wlr-randr, kscreen-doctor где возможно)
# 2025-ready

set -Eeuo pipefail

# ---------------------- CONFIG ----------------------
DEFAULT_REFRESH_RATE=60
DEFAULT_MONITOR_PORT="VGA-0"        # имеет смысл задавать явно аргументом
LOG_FILE="${HOME}/.change-display-resolution.log"
# ---------------------------------------------------

# -------- LOGGING / DRY-RUN / COMMON HELPERS -------
DRY_RUN=0
WAYLAND_BACKEND=""                  # auto-detect позже: x11|sway|kde|other

log() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] $*" | tee -a "$LOG_FILE" >&2
}

run_cmd() {
    # run_cmd <comment> <cmd...>
    local comment="$1"; shift
    log "CMD: ${comment}: $*"
    if (( DRY_RUN )); then
        return 0
    fi
    "$@"
}

error() {
    log "ERROR: $*"
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

usage() {
    cat <<EOF
Использование:
  $0 [ОПЦИИ] <X> <Y> [MONITOR_OUTPUT] [REFRESH]

Обязательные параметры:
  X, Y           - ширина и высина в пикселях (целые > 0)

Необязательные:
  MONITOR_OUTPUT - имя выхода (xrandr / wlr-randr / kscreen-doctor),
                   по умолчанию: ${DEFAULT_MONITOR_PORT} (для X11)
  REFRESH        - частота, Гц (по умолчанию: ${DEFAULT_REFRESH_RATE})

Опции:
  -n, --dry-run       Только показать команды, ничего не менять
  -l, --log FILE      Логировать в указанный файл (по умолчанию: ${LOG_FILE})
  -h, --help          Показать справку

Примеры:
  X11:
    $0 1920 1080
    $0 1920 1080 HDMI-0
    $0 1920 1080 HDMI-0 75
    $0 --dry-run 2560 1440 HDMI-0 144

  Wayland / Sway (wlr-randr):
    wlr-randr                         # посмотреть имена выходов
    $0 1920 1080 eDP-1
    $0 1920 1080 eDP-1 120

  Wayland / KDE (kscreen-doctor):
    kscreen-doctor -o                 # посмотреть конфигурацию
    $0 1920 1080 eDP-1
    $0 1920 1080 eDP-1 144

Полезные команды:
  X11:     xrandr --listmonitors, xrandr --query
  Wayland: wlr-randr, kscreen-doctor, swaymsg -t get_outputs, kwin_wayland
EOF
    exit 1
}

# --------------------- PARSE ARGS -------------------
ARGS=()
while (( $# > 0 )); do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -l|--log)
            [[ $# -ge 2 ]] || { echo "Отсутствует путь к лог-файлу для $1" >&2; exit 1; }
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Неизвестная опция: $1" >&2
            usage
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${ARGS[@]}"

if (( $# < 2 || $# > 4 )); then
    usage
fi

X_RES="$1"
Y_RES="$2"
MONITOR_OUTPUT="${3:-$DEFAULT_MONITOR_PORT}"
REFRESH="${4:-$DEFAULT_REFRESH_RATE}"

# ------------------ VALIDATION ----------------------
[[ "$X_RES" =~ ^[0-9]+$ ]] || error "X должно быть целым числом, получено: $X_RES"
[[ "$Y_RES" =~ ^[0-9]+$ ]] || error "Y должно быть целым числом, получено: $Y_RES"
[[ "$REFRESH" =~ ^[0-9]+$ ]] || error "Частота должна быть целым числом, получено: $REFRESH"

(( X_RES > 0 )) || error "X должно быть > 0"
(( Y_RES > 0 )) || error "Y должно быть > 0"
(( REFRESH > 0 && REFRESH <= 1000 )) || error "Частота должна быть в разумных пределах (1–1000 Гц)"

# Создадим лог-файл, если его нет
touch "$LOG_FILE" 2>/dev/null || {
    echo "Предупреждение: не удалось создать лог-файл ${LOG_FILE}, логирование в файл отключено." >&2
    LOG_FILE="/dev/null"
}

log "---------- START ----------"
log "Параметры: X=${X_RES}, Y=${Y_RES}, OUT=${MONITOR_OUTPUT}, REFRESH=${REFRESH}, DRY_RUN=${DRY_RUN}"

# ------------------ BACKEND DETECTION ----------------
detect_backend() {
    # Попробуем понять, что за окружение: X11 или Wayland
    if [[ "${XDG_SESSION_TYPE:-}" == "x11" || -n "${DISPLAY:-}" ]]; then
        WAYLAND_BACKEND="x11"
        return
    fi

    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        # пробуем конкретные композиторы
        if command_exists swaymsg; then
            WAYLAND_BACKEND="sway"
        elif command_exists wlr-randr; then
            WAYLAND_BACKEND="wlr"
        elif command_exists kscreen-doctor; then
            WAYLAND_BACKEND="kde"
        else
            WAYLAND_BACKEND="wayland-unknown"
        fi
        return
    fi

    WAYLAND_BACKEND="unknown"
}

detect_backend
log "Обнаруженный backend: ${WAYLAND_BACKEND}"

# --------------------- X11 / XRANDR ------------------
apply_x11_xrandr() {
    command_exists xrandr || error "xrandr не найден. Установите пакет xrandr."

    if ! xrandr >/dev/null 2>&1; then
        error "xrandr не может получить информацию о дисплее. Возможно, нет X-сессии, переменной DISPLAY и т.п."
    fi

    # Проверка существования выхода
    if ! xrandr --query | grep -qE "^${MONITOR_OUTPUT}\b"; then
        log "Выход '${MONITOR_OUTPUT}' не найден в xrandr --query"
        log "Доступные выходы:"
        xrandr --query | awk '/ connected| disconnected/ {print "  "$1" ("$2")"}' | tee -a "$LOG_FILE" >&2
        error "Укажите корректный MONITOR_OUTPUT."
    fi

    # cvt/gtf
    if ! command_exists cvt && ! command_exists gtf; then
        error "Не найдены ни cvt, ни gtf. Установите хотя бы одну утилиту (x11-xserver-utils/xorg-x11-utils)."
    fi

    local MODE_UTIL=""
    local MODE_LINE=""
    local MODE_NAME=""

    if command_exists cvt; then
        local RAW_LINE
        RAW_LINE="$(cvt "$X_RES" "$Y_RES" "$REFRESH" | sed -n '2p' || true)"
        if [[ -n "$RAW_LINE" ]]; then
            MODE_UTIL="cvt"
            MODE_LINE="${RAW_LINE#Modeline }"
        fi
    fi

    if [[ -z "$MODE_LINE" ]] && command_exists gtf; then
        local RAW_LINE
        RAW_LINE="$(gtf "$X_RES" "$Y_RES" "$REFRESH" | sed -n '3p' || true)"
        if [[ -n "$RAW_LINE" ]]; then
            MODE_UTIL="gtf"
            MODE_LINE="${RAW_LINE#Modeline }"
        fi
    fi

    [[ -n "$MODE_LINE" ]] || error "Не удалось сгенерировать Modeline для ${X_RES}x${Y_RES}@${REFRESH} через cvt/gtf."
    MODE_NAME="$(printf '%s\n' "$MODE_LINE" | awk '{print $1}')"
    [[ -n "$MODE_NAME" ]] || error "Не удалось извлечь имя режима из Modeline."

    log "X11/xrandr: утилита генерации: ${MODE_UTIL}"
    log "X11/xrandr: Modeline: ${MODE_LINE}"
    log "X11/xrandr: Имя режима: ${MODE_NAME}"

    # Существует ли уже такой режим
    local MODE_EXISTS=0
    if xrandr --query | grep -q "\"${MODE_NAME}\""; then
        MODE_EXISTS=1
    fi

    if (( MODE_EXISTS == 0 )); then
        run_cmd "Создание нового режима" xrandr --newmode ${MODE_LINE} \
            || error "Не удалось создать новый режим: ${MODE_LINE}"
    else
        log "Режим '${MODE_NAME}' уже существует, пропускаю --newmode."
    fi

    # Проверка, привязан ли режим к выходу
    local MODE_BOUND=0
    if xrandr --query | awk -v out="$MONITOR_OUTPUT" '
        BEGIN{found=0}
        $1==out {found=1; next}
        found && NF == 0 {found=0}
        found && $1 ~ /^[0-9]+x[0-9]+/ {
            for(i=1;i<=NF;i++){
                if($i ~ /^\+/){
                    print $1
                }
            }
        }' | grep -q "^${MODE_NAME}$"; then
        MODE_BOUND=1
    fi

    if (( MODE_BOUND == 0 )); then
        run_cmd "Привязка режима к выходу" xrandr --addmode "${MONITOR_OUTPUT}" "${MODE_NAME}" \
            || error "Не удалось привязать режим '${MODE_NAME}' к '${MONITOR_OUTPUT}'."
    else
        log "Режим '${MODE_NAME}' уже привязан к '${MONITOR_OUTPUT}', пропускаю --addmode."
    fi

    run_cmd "Установка режима для выхода" xrandr --output "${MONITOR_OUTPUT}" --mode "${MODE_NAME}" \
        || error "Не удалось установить режим '${MODE_NAME}' для '${MONITOR_OUTPUT}'."

    log "X11/xrandr: Готово: ${X_RES}x${Y_RES}@${REFRESH} для ${MONITOR_OUTPUT}"
}

# --------------- WAYLAND: wlr-randr / Sway ----------
apply_wayland_wlr() {
    # для sway и других wlroots-композиторов
    if ! command_exists wlr-randr; then
        error "wlr-randr не найден. Установите wlr-randr или используйте другой backend."
    fi

    # Список выходов
    local outputs
    outputs="$(wlr-randr 2>/dev/null || true)"
    if [[ -z "$outputs" ]]; then
        error "wlr-randr не вернул список выходов. Проверьте, что вы в Wayland-сессии (sway и т.д.)."
    fi

    if ! grep -qE "^${MONITOR_OUTPUT}\b" <<<"$outputs"; then
        log "Выход '${MONITOR_OUTPUT}' не найден в выводе wlr-randr."
        log "Доступные выходы:"
        grep '^[^ ]' <<<"$outputs" | sed 's/^/  /' | tee -a "$LOG_FILE" >&2
        error "Укажите корректный MONITOR_OUTPUT для wlr-randr."
    fi

    # wlr-randr поддерживает формат: wlr-randr --output OUT --mode WxH@REFRESH
    local mode_str="${X_RES}x${Y_RES}@${REFRESH}"
    run_cmd "Wayland(wlr-randr): установка режима" \
        wlr-randr --output "${MONITOR_OUTPUT}" --mode "${mode_str}" \
        || error "wlr-randr: не удалось установить режим ${mode_str} для ${MONITOR_OUTPUT}"

    log "Wayland(wlr-randr): Готово: ${mode_str} для ${MONITOR_OUTPUT}"
}

# --------------- WAYLAND: KDE / kscreen-doctor ------
apply_wayland_kde() {
    if ! command_exists kscreen-doctor; then
        error "kscreen-doctor не найден. Установите его или используйте другой backend."
    fi

    # Получение списка выходов
    local info
    info="$(kscreen-doctor -o 2>/dev/null || true)"
    if [[ -z "$info" ]]; then
        error "kscreen-doctor не вернул список выходов. Проверьте Wayland/KDE-сессию."
    fi

    if ! grep -q "output.${MONITOR_OUTPUT}." <<<"$info"; then
        log "Выход '${MONITOR_OUTPUT}' не найден в выводе kscreen-doctor -o."
        log "Доступные outputs (по шаблону output.*):"
        grep -o 'output\.[^ ]*' <<<"$info" | sort -u | sed 's/^/  /' | tee -a "$LOG_FILE" >&2
        error "Укажите корректный MONITOR_OUTPUT для kscreen-doctor (например, eDP-1, HDMI-A-1 и т.д.)."
    fi

    # Kscreen-doctor использует формат: kscreen-doctor output.<id>.mode.<mode-id>
    # где <mode-id> — это индекс или имя режима, а не произвольная геометрия.
    # В общем случае задать полностью произвольный режим затруднительно.
    # Попробуем найти подходящий режим с нужным WxH и частотой.

    local mode_id=""
    # Ищем блоки вроде:
    #   Mode "1920x1080@60"    # или c отдельными строками
    # Но kscreen-doctor выводит, например:
    #   Mode "1920x1080@60" ...
    #   ...
    #   Modes:
    #     "1920x1080@60" ...
    # Мы попытаемся вытащить все режимы для конкретного выхода.

    # Упростим: на практике обычно хватает указания геометрии без частоты:
    # kscreen-doctor output.<OUT>.mode.<W>x<H>
    local basic_mode="${X_RES}x${Y_RES}"

    # Проверим, что такой режим присутствует
    if ! grep -q "${basic_mode}" <<<"$info"; then
        log "Режим ${basic_mode} не найден для выхода ${MONITOR_OUTPUT}."
        log "Доступные режимы для этого выхода смотрите в выводе: kscreen-doctor -o"
        error "Создание произвольных режимов через kscreen-doctor не поддерживается в общем виде."
    fi

    # Попробуем использовать базовый режим без частоты
    mode_id="${basic_mode}"

    run_cmd "Wayland(KDE/kscreen-doctor): установка режима" \
        kscreen-doctor "output.${MONITOR_OUTPUT}.mode.${mode_id}" \
        || error "kscreen-doctor: не удалось установить режим ${mode_id} для ${MONITOR_OUTPUT}"

    log "Wayland(KDE): Установлен режим ${mode_id} для ${MONITOR_OUTPUT}"
    log "Внимание: точная частота ${REFRESH} Гц могла не быть применена (зависит от наличия такого режима)."
}

# --------------- WAYLAND: fallback / unknown --------
apply_wayland_unknown() {
    error "Обнаружен Wayland, но не удалось определить/поддержать композитор.
Поддерживаются:
  - wlroots/sway (wlr-randr)
  - KDE/Plasma (kscreen-doctor)
Попробуйте явно использовать x11-сессию или эти инструменты."
}

# --------------------------- MAIN -------------------
case "$WAYLAND_BACKEND" in
    x11)
        apply_x11_xrandr
        ;;
    sway|wlr)
        apply_wayland_wlr
        ;;
    kde)
        apply_wayland_kde
        ;;
    wayland-unknown)
        apply_wayland_unknown
        ;;
    unknown)
        error "Не удаётся определить тип сессии (ни X11, ни Wayland).
Убедитесь, что скрипт выполняется в графической сессии пользователя."
        ;;
    *)
        error "Неизвестный backend: ${WAYLAND_BACKEND}"
        ;;
esac

log "---------- DONE ----------"
