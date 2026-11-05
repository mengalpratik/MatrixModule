#!/system/bin/sh
##########################################################################################
# MatrixModule - Centralized Logging & Telemetry Engine
##########################################################################################

MATRIX_LOG_DIR="/data/adb/matrix_module/logs"
MATRIX_LOG_FILE="$MATRIX_LOG_DIR/matrix.log"
MATRIX_LOG_OLD="$MATRIX_LOG_DIR/matrix.old.log"
MATRIX_MAX_LOG_SIZE=524288 # 512 KB

matrix_log_init() {
    mkdir -p "$MATRIX_LOG_DIR" 2>/dev/null
    chmod 700 "$MATRIX_LOG_DIR" 2>/dev/null
    if [ ! -f "$MATRIX_LOG_FILE" ]; then
        touch "$MATRIX_LOG_FILE" 2>/dev/null
        chmod 600 "$MATRIX_LOG_FILE" 2>/dev/null
    fi
}

matrix_log_rotate() {
    if [ -f "$MATRIX_LOG_FILE" ]; then
        _size=$(wc -c < "$MATRIX_LOG_FILE" 2>/dev/null || echo 0)
        if [ "$_size" -gt "$MATRIX_MAX_LOG_SIZE" ]; then
            mv -f "$MATRIX_LOG_FILE" "$MATRIX_LOG_OLD" 2>/dev/null
            touch "$MATRIX_LOG_FILE" 2>/dev/null
            chmod 600 "$MATRIX_LOG_FILE" 2>/dev/null
        fi
    fi
}

matrix_log() {
    _level="$1"
    _tag="$2"
    _msg="$3"

    matrix_log_init

    _timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    _formatted="[$_timestamp] [$_level] [$_tag] $_msg"

    # Write to log file
    echo "$_formatted" >> "$MATRIX_LOG_FILE" 2>/dev/null
    matrix_log_rotate

    # Bridge to Android logcat if log command exists
    if command -v log >/dev/null 2>&1; then
        case "$_level" in
            ERROR) log -t "MatrixModule" -p e "$_tag: $_msg" ;;
            WARN)  log -t "MatrixModule" -p w "$_tag: $_msg" ;;
            DEBUG) log -t "MatrixModule" -p d "$_tag: $_msg" ;;
            *)     log -t "MatrixModule" -p i "$_tag: $_msg" ;;
        esac
    fi
}

log_info()  { matrix_log "INFO"  "${1:-Core}" "$2"; }
log_warn()  { matrix_log "WARN"  "${1:-Core}" "$2"; }
log_error() { matrix_log "ERROR" "${1:-Core}" "$2"; }
log_debug() { matrix_log "DEBUG" "${1:-Core}" "$2"; }

matrix_log_clear() {
    matrix_log_init
    : > "$MATRIX_LOG_FILE" 2>/dev/null
    rm -f "$MATRIX_LOG_OLD" 2>/dev/null
}

matrix_log_dump() {
    _lines="${1:-100}"
    if [ -f "$MATRIX_LOG_FILE" ]; then
        tail -n "$_lines" "$MATRIX_LOG_FILE"
    else
        echo "No logs available."
    fi
}
