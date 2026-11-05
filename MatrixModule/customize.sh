#!/system/bin/sh
##########################################################################################
# MatrixModule - KernelSU Installation Lifecycle Script
##########################################################################################

SKIPUNZIP=1
MIN_SDK=29

ui_print "=========================================="
ui_print "       MatrixModule Unified Framework      "
ui_print "=========================================="

# 1. Environment Validation
if [ "$BOOTMODE" != "true" ]; then
    abort "! Install from root manager app (KernelSU/APatch/Magisk), not recovery!"
fi

if [ "$KSU" = "true" ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
    ui_print "! Warning: KernelSU version ($KSU_VER_CODE) is older than recommended (10670+)"
fi

if [ "$API" -lt "$MIN_SDK" ]; then
    abort "! MatrixModule requires Android 10+ (API $MIN_SDK+). Found: API $API"
fi

case "$ARCH" in
    arm64) ABI_DIR="arm64-v8a" ;;
    arm)   ABI_DIR="armeabi-v7a" ;;
    x64)   ABI_DIR="x86_64" ;;
    x86)   ABI_DIR="x86" ;;
    *)     abort "! Unsupported CPU Architecture: $ARCH" ;;
esac

ui_print "- Detected Architecture: $ARCH ($ABI_DIR)"
ui_print "- Detected Android API:  $API"

# 2. Extract Core Module Files
install_file() {
    unzip -qqjo "$ZIPFILE" "$1" -d "$2" || abort "! Failed to extract: $1"
}

get_octal_mode() {
    _target="$1"
    [ ! -e "$_target" ] && return 1
    _mode=""
    if command -v stat >/dev/null 2>&1; then
        _mode=$(stat -c "%a" "$_target" 2>/dev/null)
    elif [ -x /system/bin/toybox ]; then
        _mode=$(/system/bin/toybox stat -c "%a" "$_target" 2>/dev/null)
    elif [ -x /system/bin/stat ]; then
        _mode=$(/system/bin/stat -c "%a" "$_target" 2>/dev/null)
    fi

    # Fallback to ls -ld parsing if stat didn't yield a valid numeric mode
    if [ -z "$_mode" ] || ! echo "$_mode" | grep -Eq '^[0-9]+$'; then
        _ls=$(ls -ld "$_target" 2>/dev/null | awk '{print $1}')
        if [ -n "$_ls" ]; then
            _perm=${_ls#?}
            _oct_digit() {
                case "$1" in
                    rwx) echo 7 ;;
                    rw-) echo 6 ;;
                    r-x) echo 5 ;;
                    r--) echo 4 ;;
                    -wx) echo 3 ;;
                    -w-) echo 2 ;;
                    --x) echo 1 ;;
                    *)   echo 0 ;;
                esac
            }
            _mode="$(_oct_digit "$(echo "$_perm" | cut -c1-3)")$(_oct_digit "$(echo "$_perm" | cut -c4-6)")$(_oct_digit "$(echo "$_perm" | cut -c7-9)")"
        fi
    fi

    echo "$_mode" | sed 's/.*\(...\)$/\1/'
}

get_file_owner() {
    _target="$1"
    [ ! -e "$_target" ] && return 1
    if command -v stat >/dev/null 2>&1; then
        stat -c "%u:%g" "$_target" 2>/dev/null
    elif [ -x /system/bin/toybox ]; then
        /system/bin/toybox stat -c "%u:%g" "$_target" 2>/dev/null
    else
        ls -ld "$_target" 2>/dev/null | awk '{print $3":"$4}'
    fi
}

apply_perm() {
    _target="$1"
    _owner="$2"
    _group="$3"
    _mode="$4"
    _con="${5:-u:object_r:system_file:s0}"

    if [ ! -e "$_target" ]; then
        abort "! Target file or directory missing: $_target"
    fi

    # Try set_perm if available (standard Magisk / KernelSU installer environment)
    if command -v set_perm >/dev/null 2>&1; then
        set_perm "$_target" "$_owner" "$_group" "$_mode" "$_con" 2>/dev/null || \
            ui_print "! Notice: set_perm reported non-zero on $_target, using fallback"
    fi

    # Mandatory exact mode verification & enforcement
    _req_norm=$(echo "$_mode" | sed 's/.*\(...\)$/\1/')
    _cur_mode=$(get_octal_mode "$_target")
    if [ "$_cur_mode" != "$_req_norm" ]; then
        if ! chmod "$_mode" "$_target" 2>/dev/null; then
            abort "! Mandatory permission failure: failed to chmod $_mode on $_target"
        fi
        _cur_mode=$(get_octal_mode "$_target")
        if [ "$_cur_mode" != "$_req_norm" ]; then
            abort "! Mandatory permission failure: mode mismatch on $_target (expected $_req_norm, got $_cur_mode)"
        fi
    fi

    # Ownership check (chown)
    # If running as root (id -u == 0), chown failure is fatal
    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
        if ! chown "$_owner:$_group" "$_target" 2>/dev/null; then
            abort "! Mandatory ownership failure: failed to chown $_owner:$_group on $_target"
        fi
        _cur_owner=$(get_file_owner "$_target")
        if [ "$_cur_owner" != "0:0" ] && [ "$_cur_owner" != "root:root" ]; then
            abort "! Mandatory ownership failure: owner mismatch on $_target (expected 0:0, got $_cur_owner)"
        fi
    else
        chown "$_owner:$_group" "$_target" 2>/dev/null || \
            ui_print "! Notice: Skipped chown on $_target (non-root environment)"
    fi

    # SELinux context handling (chcon)
    # Distinguish unsupported context operations from mandatory permission failures
    if command -v chcon >/dev/null 2>&1 && [ -n "$_con" ]; then
        if ! chcon "$_con" "$_target" 2>/dev/null; then
            ui_print "! Notice: SELinux context not supported or failed on: $_target"
        fi
    fi

    return 0
}

apply_perm_recursive() {
    _dir="$1"
    _owner="$2"
    _group="$3"
    _dmode="$4"
    _fmode="$5"
    _con="${6:-u:object_r:system_file:s0}"

    if [ ! -d "$_dir" ]; then
        abort "! Target directory missing: $_dir"
    fi

    if command -v set_perm_recursive >/dev/null 2>&1; then
        set_perm_recursive "$_dir" "$_owner" "$_group" "$_dmode" "$_fmode" "$_con" 2>/dev/null || \
            ui_print "! Notice: set_perm_recursive reported non-zero on $_dir, using fallback"
    fi

    # POSIX Fallback
    if ! find "$_dir" -type d -exec chmod "$_dmode" {} + 2>/dev/null; then
        abort "! Mandatory permission failure: failed to chmod $_dmode on directories in $_dir"
    fi
    if ! find "$_dir" -type f -exec chmod "$_fmode" {} + 2>/dev/null; then
        abort "! Mandatory permission failure: failed to chmod $_fmode on files in $_dir"
    fi

    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
        if ! chown -R "$_owner:$_group" "$_dir" 2>/dev/null; then
            abort "! Mandatory ownership failure: failed to chown -R $_owner:$_group on $_dir"
        fi
    else
        chown -R "$_owner:$_group" "$_dir" 2>/dev/null || \
            ui_print "! Notice: Skipped chown -R on $_dir (non-root environment)"
    fi

    if command -v chcon >/dev/null 2>&1 && [ -n "$_con" ]; then
        if ! chcon -R "$_con" "$_dir" 2>/dev/null; then
            ui_print "! Notice: SELinux context not supported or failed on: $_dir"
        fi
    fi

    return 0
}

ui_print "- Extracting module components..."

# Ensure root module directory exists with 0755
mkdir -p "$MODPATH"
apply_perm "$MODPATH" 0 0 0755

# module.prop: non-executable metadata (0644)
install_file "module.prop" "$MODPATH"
apply_perm "$MODPATH/module.prop" 0 0 0644

# Base lifecycle scripts: executable (0755)
for f in post-fs-data.sh service.sh action.sh uninstall.sh; do
    if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "$f"; then
        install_file "$f" "$MODPATH"
        apply_perm "$MODPATH/$f" 0 0 0755
    fi
done

# Core helper library: directory 0755, scripts executable (0755)
mkdir -p "$MODPATH/core"
apply_perm "$MODPATH/core" 0 0 0755
for f in matrix_env.sh matrix_store.sh matrix_log.sh matrix_health.sh; do
    if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "core/$f"; then
        install_file "core/$f" "$MODPATH/core"
        apply_perm "$MODPATH/core/$f" 0 0 0755
    fi
done

# WebUI Assets: directory 0755, files non-executable (0644)
mkdir -p "$MODPATH/webroot"
apply_perm "$MODPATH/webroot" 0 0 0755
for f in index.html app.css main.js; do
    if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "webroot/$f"; then
        install_file "webroot/$f" "$MODPATH/webroot"
        apply_perm "$MODPATH/webroot/$f" 0 0 0644
    fi
done

# Ensure recursive directory permissions are consistent
apply_perm_recursive "$MODPATH/webroot" 0 0 0755 0644

# 3. Persistent Data Initialization
DATA_DIR="${DATA_DIR:-/data/adb/matrix_module}"
mkdir -p "$DATA_DIR/logs" 2>/dev/null
apply_perm "$DATA_DIR" 0 0 0700
apply_perm "$DATA_DIR/logs" 0 0 0700

if [ ! -f "$DATA_DIR/config" ]; then
    ui_print "- Initializing default configuration..."
    if [ -f "$MODPATH/core/matrix_store.sh" ]; then
        . "$MODPATH/core/matrix_store.sh"
        matrix_store_init
    fi
else
    ui_print "- Preserving existing configuration..."
fi

verify_installed_permissions() {
    ui_print "- Verifying installed permissions..."
    _perm_err=0
    _is_root=0
    [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] && _is_root=1

    _verify_exact_mode() {
        _path="$1"
        _expected="$2"
        _type="$3"

        if [ ! -e "$_path" ]; then
            ui_print "! Critical: Required $_type missing during verification: $_path"
            _perm_err=$((_perm_err + 1))
            return 1
        fi

        _actual=$(get_octal_mode "$_path")
        _exp_norm=$(echo "$_expected" | sed 's/.*\(...\)$/\1/')
        if [ "$_actual" != "$_exp_norm" ]; then
            ui_print "! Critical: Exact mode mismatch on $_type $_path (expected $_exp_norm, got $_actual)"
            _perm_err=$((_perm_err + 1))
        fi

        if [ "$_is_root" -eq 1 ]; then
            _owner=$(get_file_owner "$_path")
            if [ "$_owner" != "0:0" ] && [ "$_owner" != "root:root" ]; then
                ui_print "! Critical: Ownership mismatch on $_path (expected root:root / 0:0, got $_owner)"
                _perm_err=$((_perm_err + 1))
            fi
        fi
    }

    # 1. Shell scripts must be exactly 0755
    for f in "$MODPATH/post-fs-data.sh" "$MODPATH/service.sh" "$MODPATH/action.sh" "$MODPATH/uninstall.sh" \
             "$MODPATH/core/matrix_env.sh" "$MODPATH/core/matrix_store.sh" "$MODPATH/core/matrix_log.sh" "$MODPATH/core/matrix_health.sh"; do
        if [ -f "$f" ]; then
            _verify_exact_mode "$f" "755" "script"
        fi
    done

    # 2. Non-executable assets must be exactly 0644
    _verify_exact_mode "$MODPATH/module.prop" "644" "metadata"
    for f in "$MODPATH/webroot/index.html" "$MODPATH/webroot/app.css" "$MODPATH/webroot/main.js"; do
        if [ -f "$f" ]; then
            _verify_exact_mode "$f" "644" "webroot asset"
        fi
    done

    # 3. Module & code directories must be exactly 0755
    for d in "$MODPATH" "$MODPATH/core" "$MODPATH/webroot"; do
        if [ -d "$d" ]; then
            _verify_exact_mode "$d" "755" "directory"
        fi
    done

    # 4. Persistent data directory and logs directory must be exactly 0700
    for d in "$DATA_DIR" "$DATA_DIR/logs"; do
        if [ -d "$d" ]; then
            _verify_exact_mode "$d" "700" "persistent directory"
        fi
    done

    if [ "$_perm_err" -gt 0 ]; then
        abort "! Post-installation permission verification failed ($_perm_err errors)"
    fi
}

verify_installed_permissions

ui_print "- Installation successful!"
ui_print "- Access WebUI or tap [Action] after boot."
ui_print "=========================================="
