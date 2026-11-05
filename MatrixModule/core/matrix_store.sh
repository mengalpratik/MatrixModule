#!/system/bin/sh
##########################################################################################
# MatrixModule - Centralized Atomic Configuration & State Management
##########################################################################################

MATRIX_DATA_DIR="/data/adb/matrix_module"
MATRIX_CONF_FILE="$MATRIX_DATA_DIR/config"
MATRIX_BAK_FILE="$MATRIX_DATA_DIR/config.bak"
MATRIX_STATE_FILE="$MATRIX_DATA_DIR/state"

matrix_store_init() {
    mkdir -p "$MATRIX_DATA_DIR" 2>/dev/null || return 1
    chmod 700 "$MATRIX_DATA_DIR" 2>/dev/null

    if [ ! -f "$MATRIX_CONF_FILE" ]; then
        if [ -f "$MATRIX_BAK_FILE" ]; then
            cp -f "$MATRIX_BAK_FILE" "$MATRIX_CONF_FILE" 2>/dev/null
        else
            matrix_store_write_defaults
        fi
    fi
    chmod 600 "$MATRIX_CONF_FILE" 2>/dev/null
    return 0
}

matrix_store_write_defaults() {
    cat << 'EOF' > "$MATRIX_CONF_FILE"
# MatrixModule Configuration File
diagnostics_enabled=1
health_watchdog_enabled=1
watchdog_interval_sec=300
log_level=INFO
backup_on_boot=1
telemetry_logging=1
conflict_warning_only=1
EOF
    cp -f "$MATRIX_CONF_FILE" "$MATRIX_BAK_FILE" 2>/dev/null
}

matrix_cfg_get() {
    _key="$1"
    _default="$2"
    [ -f "$MATRIX_CONF_FILE" ] || { echo "$_default"; return 0; }
    _val=$(grep "^${_key}=" "$MATRIX_CONF_FILE" 2>/dev/null | tail -n1 | cut -d= -f2-)
    if [ -n "$_val" ]; then
        echo "$_val"
    else
        echo "$_default"
    fi
}

matrix_cfg_set() {
    _key="$1"
    _val="$2"
    matrix_store_init || return 1

    # Atomic write pattern: stream to temp file, then rename
    _tmp_file="${MATRIX_CONF_FILE}.tmp.$$"
    if [ -f "$MATRIX_CONF_FILE" ]; then
        grep -v "^${_key}=" "$MATRIX_CONF_FILE" 2>/dev/null > "$_tmp_file"
    fi
    echo "${_key}=${_val}" >> "$_tmp_file"

    if mv -f "$_tmp_file" "$MATRIX_CONF_FILE" 2>/dev/null; then
        chmod 600 "$MATRIX_CONF_FILE" 2>/dev/null
        # Update backup
        cp -f "$MATRIX_CONF_FILE" "$MATRIX_BAK_FILE" 2>/dev/null
        return 0
    else
        rm -f "$_tmp_file" 2>/dev/null
        return 1
    fi
}

matrix_cfg_del() {
    _key="$1"
    [ -f "$MATRIX_CONF_FILE" ] || return 0
    _tmp_file="${MATRIX_CONF_FILE}.tmp.$$"
    grep -v "^${_key}=" "$MATRIX_CONF_FILE" 2>/dev/null > "$_tmp_file"
    mv -f "$_tmp_file" "$MATRIX_CONF_FILE" 2>/dev/null
    chmod 600 "$MATRIX_CONF_FILE" 2>/dev/null
}

matrix_state_set() {
    _key="$1"
    _val="$2"
    mkdir -p "$MATRIX_DATA_DIR" 2>/dev/null
    _tmp_file="${MATRIX_STATE_FILE}.tmp.$$"
    if [ -f "$MATRIX_STATE_FILE" ]; then
        grep -v "^${_key}=" "$MATRIX_STATE_FILE" 2>/dev/null > "$_tmp_file"
    fi
    echo "${_key}=${_val}" >> "$_tmp_file"
    mv -f "$_tmp_file" "$MATRIX_STATE_FILE" 2>/dev/null
    chmod 600 "$MATRIX_STATE_FILE" 2>/dev/null
}

matrix_state_get() {
    _key="$1"
    _default="$2"
    [ -f "$MATRIX_STATE_FILE" ] || { echo "$_default"; return 0; }
    _val=$(grep "^${_key}=" "$MATRIX_STATE_FILE" 2>/dev/null | tail -n1 | cut -d= -f2-)
    [ -n "$_val" ] && echo "$_val" || echo "$_default"
}

matrix_cfg_backup() {
    [ -f "$MATRIX_CONF_FILE" ] && cp -f "$MATRIX_CONF_FILE" "$MATRIX_BAK_FILE" 2>/dev/null
}

matrix_cfg_restore() {
    [ -f "$MATRIX_BAK_FILE" ] && cp -f "$MATRIX_BAK_FILE" "$MATRIX_CONF_FILE" 2>/dev/null
}
