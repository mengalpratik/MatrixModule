#!/system/bin/sh
##########################################################################################
# MatrixModule - Interactive KernelSU Action Interface
##########################################################################################

if [ -n "$MODDIR" ] && [ -d "$MODDIR" ]; then
    MODPATH="$MODDIR"
else
    _script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
    if [ -n "$_script_dir" ] && [ -d "$_script_dir" ]; then
        MODPATH="$_script_dir"
    else
        MODPATH="${0%/*}"
    fi
fi
cd "$MODPATH" 2>/dev/null

# Hop into busybox ash if available
if [ -z "$MATRIX_ASH" ]; then
    for bb in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
        if [ -x "$bb" ]; then
            export MATRIX_ASH=1
            exec "$bb" sh "$MODPATH/action.sh" "$@"
        fi
    done
fi

# Source core infrastructure
[ -f "$MODPATH/core/matrix_env.sh" ] && . "$MODPATH/core/matrix_env.sh"
[ -f "$MODPATH/core/matrix_store.sh" ] && . "$MODPATH/core/matrix_store.sh"
[ -f "$MODPATH/core/matrix_log.sh" ] && . "$MODPATH/core/matrix_log.sh"
[ -f "$MODPATH/core/matrix_health.sh" ] && . "$MODPATH/core/matrix_health.sh"

echo "=================================================="
echo "          MatrixModule Diagnostics Console         "
echo "=================================================="

case "$1" in
    logs)
        echo "[*] Recent Module Logs:"
        echo "--------------------------------------------------"
        matrix_log_dump 50
        echo "--------------------------------------------------"
        exit 0
        ;;
    reload)
        echo "[*] Reloading Configuration..."
        matrix_store_init
        matrix_cfg_backup
        echo "[+] Configuration reloaded and backup refreshed."
        exit 0
        ;;
    selftest)
        echo "[*] Running Internal Self-Tests..."
        _errs=0
        [ -f "$MODPATH/module.prop" ] || { echo "[-] Missing module.prop"; _errs=$((_errs+1)); }
        [ -f "$MODPATH/service.sh" ] || { echo "[-] Missing service.sh"; _errs=$((_errs+1)); }
        [ -f "$MODPATH/post-fs-data.sh" ] || { echo "[-] Missing post-fs-data.sh"; _errs=$((_errs+1)); }
        [ -d "$MODPATH/webroot" ] || { echo "[-] Missing webroot"; _errs=$((_errs+1)); }
        if [ "$_errs" -eq 0 ]; then
            echo "[+] All core component files verified successfully."
        else
            echo "[-] Found $_errs self-test errors."
        fi
        exit "$_errs"
        ;;
    *)
        # Default status dashboard
        _root=$(matrix_detect_root)
        _arch=$(matrix_get_arch)
        _sdk=$(matrix_get_sdk)
        _rel=$(matrix_get_android_release)
        _model=$(matrix_get_device_model)
        _zygisk=$(matrix_check_zygisk)
        _selinux=$(matrix_get_selinux)
        _boot_stage=$(matrix_state_get "boot_stage" "unknown")
        _boot_dur=$(matrix_state_get "boot_duration_sec" "N/A")
        _conflicts=$(matrix_scan_conflicts)

        echo " Device Model:     $_model"
        echo " Android Release:  $_rel (SDK $_sdk)"
        echo " CPU Architecture: $_arch"
        echo " Root Manager:     $_root"
        echo " SELinux Policy:   $_selinux"
        echo " Zygisk Provider:  $_zygisk"
        echo " Boot Duration:    ${_boot_dur}s"
        echo "--------------------------------------------------"

        # KernelSU Version Check
        if [ "$_root" = "KernelSU" ]; then
            _ksu_res=$(matrix_get_ksu_versions)
            _m_code=$(echo "$_ksu_res" | cut -d' ' -f1)
            _k_code=$(echo "$_ksu_res" | cut -d' ' -f2)
            _match=$(echo "$_ksu_res" | cut -d' ' -f3)

            if [ "$_match" = "1" ]; then
                echo " [OK] KernelSU Driver & Manager Synchronized (v$_m_code)"
            elif [ "$_match" = "0" ]; then
                echo " [WARN] KernelSU Mismatch: Manager ($_m_code) != Driver ($_k_code)"
            fi
        fi

        # Zygisk Status
        if [ "$_zygisk" != "None" ]; then
            echo " [OK] Zygisk Framework Active: $_zygisk"
        else
            echo " [INFO] No active Zygisk framework detected"
        fi

        # Coexistence / Conflict Warning
        if [ -n "$_conflicts" ]; then
            echo " [NOTICE] Coexisting Modules: $_conflicts"
            echo "          Operating safely without modifying third-party modules."
        else
            echo " [OK] Clean module environment (no conflicting modules)"
        fi

        # Refresh health report
        matrix_health_generate_report
        _status=$(matrix_health_determine_status "$_root" "$_boot_stage" "$_conflicts" "$_match" "$_selinux" "$_arch" "$_sdk")
        echo "--------------------------------------------------"
        echo " Status:           $_status"
        echo " WebUI Location:   $MODPATH/webroot"
        echo " Config Location:  /data/adb/matrix_module/config"
        echo "=================================================="
        ;;
esac

exit 0
