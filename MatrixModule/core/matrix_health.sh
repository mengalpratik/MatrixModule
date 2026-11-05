#!/system/bin/sh
##########################################################################################
# MatrixModule - Boot Health & Diagnostics Engine
##########################################################################################

_CORE_DIR="${0%/*}"
[ -f "$_CORE_DIR/matrix_log.sh" ] && . "$_CORE_DIR/matrix_log.sh"
[ -f "$_CORE_DIR/matrix_store.sh" ] && . "$_CORE_DIR/matrix_store.sh"
[ -f "$_CORE_DIR/matrix_env.sh" ] && . "$_CORE_DIR/matrix_env.sh"

MATRIX_HEALTH_FILE="${MATRIX_HEALTH_FILE:-/data/adb/matrix_module/health.json}"

matrix_health_mark_boot_start() {
    matrix_store_init
    _ts=$(date +%s 2>/dev/null || echo 0)
    matrix_state_set "boot_start_time" "$_ts"
    matrix_state_set "boot_stage" "post-fs-data"
    log_info "Health" "Early boot stage registered (post-fs-data)"
}

matrix_health_mark_boot_complete() {
    _ts=$(date +%s 2>/dev/null || echo 0)
    _start_ts=$(matrix_state_get "boot_start_time" "0")
    _duration=0
    if [ "$_start_ts" -gt 0 ] && [ "$_ts" -ge "$_start_ts" ]; then
        _duration=$((_ts - _start_ts))
    fi

    matrix_state_set "boot_complete_time" "$_ts"
    matrix_state_set "boot_duration_sec" "$_duration"
    matrix_state_set "boot_stage" "completed"
    matrix_state_set "boot_failure_count" "0"

    log_info "Health" "Boot completed in ${_duration}s"
    matrix_health_generate_report
}

matrix_health_check_recovery_mode() {
    _mode=$(getprop ro.boot.mode 2>/dev/null)
    [ -z "$_mode" ] && _mode=$(getprop ro.bootmode 2>/dev/null)
    case "$_mode" in
        recovery*|rescue*)
            log_warn "Health" "Device detected in recovery/rescue mode ($_mode)"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

matrix_scan_conflicts() {
    # Non-destructive conflict scan: reports findings, never removes files
    _conflicts=""
    _known_mods="tricky_store tricky_store_v2 TrickyStore TEESimulator TEESimulator-RS hma_oss_zygisk playintegrityfix playintegrityfork"

    for mod in $_known_mods; do
        if [ "$mod" != "matrix_module" ] && [ -d "/data/adb/modules/$mod" ]; then
            if [ ! -f "/data/adb/modules/$mod/disable" ] && [ ! -f "/data/adb/modules/$mod/remove" ]; then
                _conflicts="$_conflicts $mod"
            fi
        fi
    done

    echo "$_conflicts" | sed 's/^[[:space:]]*//'
}

matrix_json_escape() {
    # Properly escape JSON special characters:
    # 1. Backslashes (\ -> \\)
    # 2. Double quotes (" -> \")
    # 3. Carriage returns (\r -> \r)
    # 4. Tabs (\t -> \t)
    # 5. Newlines (\n -> \n)
    # Uses awk with a sentinel suffix to preserve trailing newlines while remaining
    # fully compatible with BusyBox, Android toybox, and POSIX awk/sed.
    printf "%s." "$1" | awk '
    BEGIN { first = 1 }
    {
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        gsub(/\r/, "\\r")
        gsub(/\t/, "\\t")
        if (first) {
            printf "%s", $0
            first = 0
        } else {
            printf "\\n%s", $0
        }
    }' | sed 's/.$//'
}

matrix_health_generate_report() {
    mkdir -p "${MATRIX_HEALTH_FILE%/*}" 2>/dev/null
    _root=$(matrix_detect_root)
    _arch=$(matrix_get_arch)
    _sdk=$(matrix_get_sdk)
    _model=$(matrix_get_device_model)
    _zygisk=$(matrix_check_zygisk)
    _selinux=$(matrix_get_selinux)
    _boot_stage=$(matrix_state_get "boot_stage" "unknown")
    _boot_dur=$(matrix_state_get "boot_duration_sec" "0")
    _conflicts=$(matrix_scan_conflicts)
    _ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")

    # Sanitize and escape all JSON string properties
    _root_esc=$(matrix_json_escape "$_root")
    _arch_esc=$(matrix_json_escape "$_arch")
    _model_esc=$(matrix_json_escape "$_model")
    _zygisk_esc=$(matrix_json_escape "$_zygisk")
    _selinux_esc=$(matrix_json_escape "$_selinux")
    _boot_stage_esc=$(matrix_json_escape "$_boot_stage")
    _conflicts_esc=$(matrix_json_escape "$_conflicts")
    _ts_esc=$(matrix_json_escape "$_ts")

    # Ensure numeric values are valid integers
    echo "$_sdk" | grep -Eq '^[0-9]+$' || _sdk=0
    echo "$_boot_dur" | grep -Eq '^[0-9]+$' || _boot_dur=0

    cat << EOF > "$MATRIX_HEALTH_FILE"
{
  "timestamp": "$_ts_esc",
  "root_manager": "$_root_esc",
  "architecture": "$_arch_esc",
  "sdk_level": $_sdk,
  "device_model": "$_model_esc",
  "zygisk_host": "$_zygisk_esc",
  "selinux_mode": "$_selinux_esc",
  "boot_stage": "$_boot_stage_esc",
  "boot_duration_sec": $_boot_dur,
  "active_conflicts": "$_conflicts_esc",
  "status": "HEALTHY"
}
EOF
    chmod 644 "$MATRIX_HEALTH_FILE" 2>/dev/null
}
