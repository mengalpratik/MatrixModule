#!/system/bin/sh
##########################################################################################
# MatrixModule - Boot Health & Diagnostics Engine
##########################################################################################

_CORE_DIR="${0%/*}"
[ ! -f "$_CORE_DIR/matrix_env.sh" ] && [ -f "$_CORE_DIR/core/matrix_env.sh" ] && _CORE_DIR="$_CORE_DIR/core"
[ ! -f "$_CORE_DIR/matrix_env.sh" ] && [ -n "$MODDIR" ] && [ -f "$MODDIR/core/matrix_env.sh" ] && _CORE_DIR="$MODDIR/core"
[ -f "$_CORE_DIR/matrix_log.sh" ] && . "$_CORE_DIR/matrix_log.sh"
[ -f "$_CORE_DIR/matrix_store.sh" ] && . "$_CORE_DIR/matrix_store.sh"
[ -f "$_CORE_DIR/matrix_env.sh" ] && . "$_CORE_DIR/matrix_env.sh"

command -v log_info  >/dev/null 2>&1 || log_info()  { :; }
command -v log_warn  >/dev/null 2>&1 || log_warn()  { :; }
command -v log_error >/dev/null 2>&1 || log_error() { :; }
command -v log_debug >/dev/null 2>&1 || log_debug() { :; }

MATRIX_HEALTH_FILE="${MATRIX_HEALTH_FILE:-/data/adb/matrix_module/health.json}"

matrix_health_mark_boot_start() {
    matrix_store_init || return 1
    _ts=$(date +%s 2>/dev/null || echo 0)
    matrix_state_set "boot_start_time" "$_ts" || return 1
    matrix_state_set "boot_stage" "post-fs-data" || return 1
    log_info "Health" "Early boot stage registered (post-fs-data)"
    return 0
}

matrix_health_mark_boot_complete() {
    _ts=$(date +%s 2>/dev/null || echo 0)
    _start_ts=$(matrix_state_get "boot_start_time" "0")
    _duration=0
    if [ "$_start_ts" -gt 0 ] && [ "$_ts" -ge "$_start_ts" ]; then
        _duration=$((_ts - _start_ts))
    fi

    matrix_state_set "boot_complete_time" "$_ts" || return 1
    matrix_state_set "boot_duration_sec" "$_duration" || return 1
    matrix_state_set "boot_stage" "completed" || return 1
    matrix_state_set "boot_failure_count" "0" || return 1

    log_info "Health" "Boot completed in ${_duration}s"
    matrix_health_generate_report || return 1
    return 0
}

matrix_health_mark_boot_timeout() {
    _reason="${1:-sys.boot_completed timeout after wait period}"
    _ts=$(date +%s 2>/dev/null || echo 0)
    _start_ts=$(matrix_state_get "boot_start_time" "0")
    _duration=0
    if [ "$_start_ts" -gt 0 ] && [ "$_ts" -ge "$_start_ts" ]; then
        _duration=$((_ts - _start_ts))
    fi

    matrix_state_set "boot_stage" "timeout"
    matrix_state_set "boot_timeout_reason" "$_reason"
    matrix_state_set "boot_duration_sec" "$_duration"

    log_warn "Health" "Boot completion timed out (${_duration}s): $_reason"
    matrix_health_generate_report
}

matrix_health_mark_boot_failed() {
    _reason="${1:-lifecycle error encountered}"
    _ts=$(date +%s 2>/dev/null || echo 0)
    _start_ts=$(matrix_state_get "boot_start_time" "0")
    _duration=0
    if [ "$_start_ts" -gt 0 ] && [ "$_ts" -ge "$_start_ts" ]; then
        _duration=$((_ts - _start_ts))
    fi

    _curr_stage=$(matrix_state_get "boot_stage" "unknown")
    _prev_failures=$(matrix_state_get "boot_failure_count" "0")
    echo "$_prev_failures" | grep -Eq '^[0-9]+$' || _prev_failures=0

    # Do not increment failure counter more than once for the same lifecycle failure event
    if [ "$_curr_stage" = "failed" ]; then
        _new_failures="$_prev_failures"
    else
        _new_failures=$((_prev_failures + 1))
    fi

    matrix_state_set "boot_stage" "failed"
    matrix_state_set "boot_failure_reason" "$_reason"
    matrix_state_set "boot_failure_count" "$_new_failures"
    matrix_state_set "boot_duration_sec" "$_duration"

    log_error "Health" "Boot stage failed (${_duration}s): $_reason (failures: $_new_failures)"
    matrix_health_generate_report
}

matrix_health_mark_boot_aborted() {
    _reason="${1:-lifecycle aborted}"
    _ts=$(date +%s 2>/dev/null || echo 0)
    _start_ts=$(matrix_state_get "boot_start_time" "0")
    _duration=0
    if [ "$_start_ts" -gt 0 ] && [ "$_ts" -ge "$_start_ts" ]; then
        _duration=$((_ts - _start_ts))
    fi

    matrix_state_set "boot_stage" "aborted"
    matrix_state_set "boot_failure_reason" "$_reason"
    matrix_state_set "boot_duration_sec" "$_duration"

    log_error "Health" "Boot stage aborted: $_reason"
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
    # Properly escape JSON special characters and all C0 control characters (0x01-0x1F):
    # - Backslash (\ -> \\) and Double quote (" -> \")
    # - Standard concise JSON C0 escapes: \b (0x08), \t (0x09), \n (0x0A), \f (0x0C), \r (0x0D)
    # - Standard Unicode C0 escapes: \u0001-\u001f for remaining control characters (e.g. \u0007, \u000b, \u001b)
    # Uses awk with a sentinel suffix to preserve trailing newlines while remaining
    # fully compatible with BusyBox, Android toybox, and POSIX awk/sed.
    printf "%s." "$1" | awk '
    BEGIN {
        first = 1
        for (i = 1; i <= 31; i++) {
            c = sprintf("%c", i)
            if (i == 8) map[c] = "\\b"
            else if (i == 9) map[c] = "\\t"
            else if (i == 10) map[c] = "\\n"
            else if (i == 12) map[c] = "\\f"
            else if (i == 13) map[c] = "\\r"
            else map[c] = sprintf("\\u%04x", i)
        }
        map["\\"] = "\\\\"
        map["\""] = "\\\""
    }
    {
        if (!first) {
            printf "\\n"
        }
        first = 0
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
            ch = chars[i]
            if (ch in map) {
                printf "%s", map[ch]
            } else {
                printf "%s", ch
            }
        }
    }' | sed 's/.$//'
}

matrix_health_determine_status() {
    # Determine honest health status based on environment and probe diagnostics.
    # Strict Precedence Order: ERROR -> UNKNOWN -> WARNING -> HEALTHY
    #
    # 1. ERROR (Critical failure states):
    #    - Device in recovery / rescue mode
    #    - Boot stage is failed, aborted, or recovery
    #    - Boot failure count > 0
    #    - Unsupported CPU architecture
    #
    # 2. UNKNOWN (Missing, uninitialized, or unresolvable telemetry):
    #    - Boot stage is unknown, uninitialized, or empty
    #    - Root manager probe returned Unknown or empty
    #    - SELinux mode returned Unknown or empty
    #    - Android SDK level is 0 or empty
    #
    # 3. WARNING (Degraded or non-final operational states):
    #    - Active third-party module conflicts detected
    #    - KernelSU Manager / Driver version code mismatch
    #    - Boot stage is post-fs-data (early boot in progress, not complete)
    #    - Boot stage is timeout (sys.boot_completed was not confirmed within wait timeout)
    #
    # 4. HEALTHY (Normal operational state):
    #    - Boot stage is strictly "completed"
    #    - All environment and security probes fully resolved and valid
    #    - Zero conflicts, mismatches, or failures detected

    _d_root="${1:-$(matrix_detect_root 2>/dev/null)}"
    _d_boot_stage="${2:-$(matrix_state_get "boot_stage" "unknown" 2>/dev/null)}"
    _d_conflicts="${3:-$(matrix_scan_conflicts 2>/dev/null)}"
    _d_ksu_match="${4:-}"
    _d_selinux="${5:-$(matrix_get_selinux 2>/dev/null)}"
    _d_arch="${6:-$(matrix_get_arch 2>/dev/null)}"
    _d_sdk="${7:-$(matrix_get_sdk 2>/dev/null)}"

    if [ -z "$_d_ksu_match" ] && [ "$_d_root" = "KernelSU" ]; then
        _ksu_res=$(matrix_get_ksu_versions 2>/dev/null || echo "0 0 -1")
        _d_ksu_match=$(echo "$_ksu_res" | cut -d' ' -f3)
    fi

    # 1. Critical ERROR conditions
    if matrix_health_check_recovery_mode; then
        echo "ERROR"
        return 0
    fi
    case "$_d_boot_stage" in
        aborted|failed|recovery)
            echo "ERROR"
            return 0
            ;;
    esac
    if [ "$_d_arch" = "unsupported" ]; then
        echo "ERROR"
        return 0
    fi
    _fail_count=$(matrix_state_get "boot_failure_count" "0" 2>/dev/null)
    if [ -n "$_fail_count" ] && [ "$_fail_count" -gt 0 ] 2>/dev/null; then
        echo "ERROR"
        return 0
    fi

    # 2. UNKNOWN conditions (missing, uninitialized, or unresolvable probes)
    case "$_d_boot_stage" in
        unknown|""|uninitialized)
            echo "UNKNOWN"
            return 0
            ;;
    esac
    if [ "$_d_root" = "Unknown" ] || [ -z "$_d_root" ]; then
        echo "UNKNOWN"
        return 0
    fi
    if [ "$_d_selinux" = "Unknown" ] || [ -z "$_d_selinux" ]; then
        echo "UNKNOWN"
        return 0
    fi
    if [ -z "$_d_sdk" ] || [ "$_d_sdk" = "0" ]; then
        echo "UNKNOWN"
        return 0
    fi

    # 3. WARNING conditions (degraded or in-progress states)
    if [ -n "$_d_conflicts" ] && [ "$_d_conflicts" != "None" ]; then
        echo "WARNING"
        return 0
    fi
    if [ "$_d_root" = "KernelSU" ] && [ "$_d_ksu_match" = "0" ]; then
        echo "WARNING"
        return 0
    fi
    case "$_d_boot_stage" in
        post-fs-data|timeout)
            echo "WARNING"
            return 0
            ;;
    esac

    # 4. HEALTHY condition (must be strictly completed)
    if [ "$_d_boot_stage" = "completed" ]; then
        echo "HEALTHY"
        return 0
    fi

    # Unrecognized boot stage defaults to UNKNOWN
    echo "UNKNOWN"
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

    # KernelSU version and synchronization probe
    _ksu_res=$(matrix_get_ksu_versions 2>/dev/null || echo "0 0 -1")
    _m_code=$(echo "$_ksu_res" | cut -d' ' -f1)
    _k_code=$(echo "$_ksu_res" | cut -d' ' -f2)
    _ksu_match=$(echo "$_ksu_res" | cut -d' ' -f3)

    # Ensure numeric values are valid integers
    echo "$_sdk" | grep -Eq '^[0-9]+$' || _sdk=0
    echo "$_boot_dur" | grep -Eq '^[0-9]+$' || _boot_dur=0
    echo "$_m_code" | grep -Eq '^[0-9]+$' || _m_code=0
    echo "$_k_code" | grep -Eq '^[0-9]+$' || _k_code=0
    echo "$_ksu_match" | grep -Eq '^-?[0-9]+$' || _ksu_match=-1

    _fail_count=$(matrix_state_get "boot_failure_count" "0")
    echo "$_fail_count" | grep -Eq '^[0-9]+$' || _fail_count=0

    # Dynamically determine honest health status
    _status=$(matrix_health_determine_status "$_root" "$_boot_stage" "$_conflicts" "$_ksu_match" "$_selinux" "$_arch" "$_sdk")
    _status_esc=$(matrix_json_escape "$_status")

    _report="{
  \"timestamp\": \"$_ts_esc\",
  \"root_manager\": \"$_root_esc\",
  \"architecture\": \"$_arch_esc\",
  \"sdk_level\": $_sdk,
  \"device_model\": \"$_model_esc\",
  \"zygisk_host\": \"$_zygisk_esc\",
  \"selinux_mode\": \"$_selinux_esc\",
  \"boot_stage\": \"$_boot_stage_esc\",
  \"boot_duration_sec\": $_boot_dur,
  \"active_conflicts\": \"$_conflicts_esc\",
  \"ksu_manager_code\": $_m_code,
  \"ksu_kernel_code\": $_k_code,
  \"ksu_version_match\": $_ksu_match,
  \"boot_failure_count\": $_fail_count,
  \"status\": \"$_status_esc\"
}"

    mkdir -p "${MATRIX_HEALTH_FILE%/*}" 2>/dev/null
    printf "%s\n" "$_report" > "$MATRIX_HEALTH_FILE" 2>/dev/null
    chmod 644 "$MATRIX_HEALTH_FILE" 2>/dev/null
}

# If executed directly (not sourced), generate and output the JSON health report
if [ "${0##*/}" = "matrix_health.sh" ] || [ "$1" = "report" ] || [ "$1" = "json" ]; then
    matrix_health_generate_report >/dev/null 2>&1
    if [ -f "$MATRIX_HEALTH_FILE" ]; then
        cat "$MATRIX_HEALTH_FILE"
        exit 0
    elif [ -n "$_report" ]; then
        printf "%s\n" "$_report"
        exit 0
    else
        exit 1
    fi
fi
