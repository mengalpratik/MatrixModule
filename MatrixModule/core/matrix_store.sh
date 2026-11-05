#!/system/bin/sh
##########################################################################################
# MatrixModule - Centralized Atomic Configuration & State Management
##########################################################################################

MATRIX_DATA_DIR="${MATRIX_DATA_DIR:-/data/adb/matrix_module}"
MATRIX_CONF_FILE="${MATRIX_CONF_FILE:-$MATRIX_DATA_DIR/config}"
MATRIX_BAK_FILE="${MATRIX_BAK_FILE:-$MATRIX_DATA_DIR/config.bak}"
MATRIX_STATE_FILE="${MATRIX_STATE_FILE:-$MATRIX_DATA_DIR/state}"

matrix_cfg_validate_key_value() {
    _k="$1"
    _v="$2"

    # 1. Key must be purely alphanumeric and underscore
    echo "$_k" | grep -Eq '^[a-zA-Z0-9_]+$' || return 1

    # 2. Value must be non-empty and strictly alphanumeric, underscore, dot, dash, colon, slash
    [ -z "$_v" ] && return 1
    echo "$_v" | grep -Eq '^[a-zA-Z0-9_.:/-]+$' || return 1

    # 3. Known key constraints
    case "$_k" in
        watchdog_interval_sec)
            echo "$_v" | grep -Eq '^[0-9]+$' || return 1
            [ "$_v" -ge 60 ] 2>/dev/null && [ "$_v" -le 3600 ] 2>/dev/null || return 1
            ;;
        diagnostics_enabled|health_watchdog_enabled|backup_on_boot|telemetry_logging|conflict_warning_only)
            case "$_v" in
                0|1) ;;
                *) return 1 ;;
            esac
            ;;
        log_level)
            case "$_v" in
                INFO|WARN|ERROR|DEBUG) ;;
                *) return 1 ;;
            esac
            ;;
    esac

    return 0
}

matrix_cfg_validate_file() {
    _file="$1"
    [ -f "$_file" ] || return 1
    [ -s "$_file" ] || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            \#*|"") continue ;;
            *=*)
                _k="${line%%=*}"
                _v="${line#*=}"
                matrix_cfg_validate_key_value "$_k" "$_v" || return 1
                ;;
            *)
                return 1
                ;;
        esac
    done < "$_file"

    return 0
}

matrix_store_init() {
    mkdir -p "$MATRIX_DATA_DIR" 2>/dev/null || return 1
    chmod 700 "$MATRIX_DATA_DIR" 2>/dev/null

    if [ ! -f "$MATRIX_CONF_FILE" ]; then
        if [ -f "$MATRIX_BAK_FILE" ] && matrix_cfg_validate_file "$MATRIX_BAK_FILE"; then
            cp -f "$MATRIX_BAK_FILE" "$MATRIX_CONF_FILE" 2>/dev/null
        else
            matrix_store_write_defaults
        fi
    elif ! matrix_cfg_validate_file "$MATRIX_CONF_FILE"; then
        # Active config corrupted: attempt rollback from backup
        if [ -f "$MATRIX_BAK_FILE" ] && matrix_cfg_validate_file "$MATRIX_BAK_FILE"; then
            cp -f "$MATRIX_BAK_FILE" "$MATRIX_CONF_FILE" 2>/dev/null
        else
            matrix_store_write_defaults
        fi
    fi

    chmod 600 "$MATRIX_CONF_FILE" 2>/dev/null
    [ -f "$MATRIX_BAK_FILE" ] && chmod 600 "$MATRIX_BAK_FILE" 2>/dev/null
    return 0
}

matrix_store_write_defaults() {
    _tmp_def="${MATRIX_CONF_FILE}.def.$$"
    cat << 'EOF' > "$_tmp_def"
# MatrixModule Configuration File
diagnostics_enabled=1
health_watchdog_enabled=1
watchdog_interval_sec=300
log_level=INFO
backup_on_boot=1
telemetry_logging=1
conflict_warning_only=1
EOF
    mv -f "$_tmp_def" "$MATRIX_CONF_FILE" 2>/dev/null
    chmod 600 "$MATRIX_CONF_FILE" 2>/dev/null
    cp -f "$MATRIX_CONF_FILE" "$MATRIX_BAK_FILE" 2>/dev/null
    chmod 600 "$MATRIX_BAK_FILE" 2>/dev/null
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

    # 1. Validate key and value strictly before modifying anything
    matrix_cfg_validate_key_value "$_key" "$_val" || return 1

    # 2. Atomic write pattern: stream to temp file, validate, then rename
    _tmp_file="${MATRIX_CONF_FILE}.tmp.$$"
    if [ -f "$MATRIX_CONF_FILE" ]; then
        grep -v "^${_key}=" "$MATRIX_CONF_FILE" 2>/dev/null > "$_tmp_file"
    fi
    echo "${_key}=${_val}" >> "$_tmp_file"

    # 3. Validate entire resulting file before atomic rename
    if matrix_cfg_validate_file "$_tmp_file"; then
        if mv -f "$_tmp_file" "$MATRIX_CONF_FILE" 2>/dev/null; then
            chmod 600 "$MATRIX_CONF_FILE" 2>/dev/null
            # MM-DEF-02 Fix: DO NOT overwrite backup here!
            # Backup is preserved as the last-known-good boot configuration.
            return 0
        else
            rm -f "$_tmp_file" 2>/dev/null
            return 1
        fi
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
    if matrix_cfg_validate_file "$_tmp_file"; then
        mv -f "$_tmp_file" "$MATRIX_CONF_FILE" 2>/dev/null
        chmod 600 "$MATRIX_CONF_FILE" 2>/dev/null
    else
        rm -f "$_tmp_file" 2>/dev/null
    fi
}

matrix_state_set() {
    _key="$1"
    _val="$2"
    mkdir -p "$MATRIX_DATA_DIR" 2>/dev/null || return 1
    _tmp_file="${MATRIX_STATE_FILE}.tmp.$$"
    if [ -f "$MATRIX_STATE_FILE" ]; then
        grep -v "^${_key}=" "$MATRIX_STATE_FILE" 2>/dev/null > "$_tmp_file"
    fi
    echo "${_key}=${_val}" >> "$_tmp_file"
    if mv -f "$_tmp_file" "$MATRIX_STATE_FILE" 2>/dev/null; then
        chmod 600 "$MATRIX_STATE_FILE" 2>/dev/null
        return 0
    else
        rm -f "$_tmp_file" 2>/dev/null
        return 1
    fi
}

matrix_state_get() {
    _key="$1"
    _default="$2"
    [ -f "$MATRIX_STATE_FILE" ] || { echo "$_default"; return 0; }
    _val=$(grep "^${_key}=" "$MATRIX_STATE_FILE" 2>/dev/null | tail -n1 | cut -d= -f2-)
    [ -n "$_val" ] && echo "$_val" || echo "$_default"
}

matrix_cfg_backup() {
    # MM-DEF-02 Fix: Only promote config to backup if it passes full validation
    if [ -f "$MATRIX_CONF_FILE" ] && matrix_cfg_validate_file "$MATRIX_CONF_FILE"; then
        _tmp_bak="${MATRIX_BAK_FILE}.tmp.$$"
        cp -f "$MATRIX_CONF_FILE" "$_tmp_bak" 2>/dev/null
        if mv -f "$_tmp_bak" "$MATRIX_BAK_FILE" 2>/dev/null; then
            chmod 600 "$MATRIX_BAK_FILE" 2>/dev/null
            return 0
        else
            rm -f "$_tmp_bak" 2>/dev/null
            return 1
        fi
    fi
    return 1
}

matrix_cfg_restore() {
    if [ -f "$MATRIX_BAK_FILE" ] && matrix_cfg_validate_file "$MATRIX_BAK_FILE"; then
        _tmp_res="${MATRIX_CONF_FILE}.tmp.$$"
        cp -f "$MATRIX_BAK_FILE" "$_tmp_res" 2>/dev/null
        mv -f "$_tmp_res" "$MATRIX_CONF_FILE" 2>/dev/null
        chmod 600 "$MATRIX_CONF_FILE" 2>/dev/null
        return 0
    else
        matrix_store_write_defaults
        return 1
    fi
}
