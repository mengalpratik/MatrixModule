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

apply_perm() {
    _target="$1"
    _owner="$2"
    _group="$3"
    _mode="$4"
    _con="${5:-u:object_r:system_file:s0}"

    if command -v set_perm >/dev/null 2>&1; then
        set_perm "$_target" "$_owner" "$_group" "$_mode" "$_con" 2>/dev/null || true
    else
        chown "$_owner:$_group" "$_target" 2>/dev/null || true
        chmod "$_mode" "$_target" 2>/dev/null || true
        chcon "$_con" "$_target" 2>/dev/null || true
    fi
}

apply_perm_recursive() {
    _dir="$1"
    _owner="$2"
    _group="$3"
    _dmode="$4"
    _fmode="$5"
    _con="${6:-u:object_r:system_file:s0}"

    if command -v set_perm_recursive >/dev/null 2>&1; then
        set_perm_recursive "$_dir" "$_owner" "$_group" "$_dmode" "$_fmode" "$_con" 2>/dev/null || true
    else
        find "$_dir" -type d -exec chmod "$_dmode" {} + 2>/dev/null || true
        find "$_dir" -type f -exec chmod "$_fmode" {} + 2>/dev/null || true
        chown -R "$_owner:$_group" "$_dir" 2>/dev/null || true
        chcon -R "$_con" "$_dir" 2>/dev/null || true
    fi
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

ui_print "- Installation successful!"
ui_print "- Access WebUI or tap [Action] after boot."
ui_print "=========================================="
