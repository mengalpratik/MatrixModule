#!/system/bin/sh
##########################################################################################
# MatrixModule - Environment & Diagnostics Helper
##########################################################################################

# Ensure non-fatal return on individual probes
matrix_detect_root() {
    if [ "$KSU" = "true" ] || [ -d "/data/adb/ksu" ]; then
        echo "KernelSU"
    elif [ "$APATCH" = "true" ] || [ -d "/data/adb/ap" ]; then
        echo "APatch"
    elif [ "$MAGISK_VER" ] || [ -d "/data/adb/magisk" ]; then
        echo "Magisk"
    else
        echo "Unknown"
    fi
}

matrix_get_arch() {
    case "$(uname -m)" in
        aarch64)        echo "arm64-v8a" ;;
        armv7*|armv8l)  echo "armeabi-v7a" ;;
        x86_64)         echo "x86_64" ;;
        i?86)           echo "x86" ;;
        *)              echo "unsupported" ;;
    esac
}

matrix_get_sdk() {
    _sdk=$(getprop ro.build.version.sdk 2>/dev/null)
    [ -z "$_sdk" ] && _sdk=0
    echo "$_sdk"
}

matrix_get_android_release() {
    getprop ro.build.version.release 2>/dev/null || echo "Unknown"
}

matrix_get_device_model() {
    getprop ro.product.model 2>/dev/null || echo "Generic"
}

matrix_get_ksu_versions() {
    # Returns: manager_code kernel_code is_matched(0|1)
    _m_code="${KSU_VER_CODE:-0}"
    _k_code="${KSU_KERNEL_VER_CODE:-0}"

    if [ "$_m_code" -gt 0 ] && [ "$_k_code" -gt 0 ]; then
        if [ "$_m_code" -eq "$_k_code" ]; then
            echo "$_m_code $_k_code 1"
        else
            echo "$_m_code $_k_code 0"
        fi
    else
        echo "${_m_code} ${_k_code} -1"
    fi
}

matrix_check_zygisk() {
    # Non-destructive check for Zygisk providers
    _zygisk_found=""
    for mod in /data/adb/modules/* /data/adb/modules_update/*; do
        [ -d "$mod" ] || continue
        ([ -f "$mod/disable" ] || [ -f "$mod/remove" ]) && continue
        if [ -f "$mod/bin/zygiskd" ] || [ -f "$mod/bin/zygiskd64" ]; then
            _mname=$(grep "^name=" "$mod/module.prop" 2>/dev/null | cut -d= -f2-)
            [ -z "$_mname" ] && _mname=$(basename "$mod")
            _zygisk_found="$_mname"
            break
        fi
    done

    if [ -z "$_zygisk_found" ]; then
        # Check Magisk built-in Zygisk
        if command -v magisk >/dev/null 2>&1; then
            _magisk_zygisk=$(magisk --sqlite "SELECT value FROM settings WHERE key = 'zygisk'" 2>/dev/null | cut -d= -f2)
            if [ "$_magisk_zygisk" = "1" ]; then
                _zygisk_found="Magisk-Builtin"
            fi
        fi
    fi

    [ -n "$_zygisk_found" ] && echo "$_zygisk_found" || echo "None"
}

matrix_get_selinux() {
    if command -v getenforce >/dev/null 2>&1; then
        getenforce 2>/dev/null || echo "Unknown"
    elif [ -f /sys/fs/selinux/enforce ]; then
        _val=$(cat /sys/fs/selinux/enforce 2>/dev/null)
        [ "$_val" = "1" ] && echo "Enforcing" || echo "Permissive"
    else
        echo "Unknown"
    fi
}

matrix_dump_env() {
    echo "Root Manager: $(matrix_detect_root)"
    echo "Architecture: $(matrix_get_arch)"
    echo "Android SDK: $(matrix_get_sdk) ($(matrix_get_android_release))"
    echo "Device Model: $(matrix_get_device_model)"
    echo "Zygisk Host: $(matrix_check_zygisk)"
    echo "SELinux Mode: $(matrix_get_selinux)"
}
