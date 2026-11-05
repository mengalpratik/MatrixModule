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

ui_print "- Extracting module components..."

# Base scripts and properties
for f in module.prop post-fs-data.sh service.sh action.sh uninstall.sh; do
    install_file "$f" "$MODPATH"
    chmod 755 "$MODPATH/$f" 2>/dev/null
done

# Core helper library
mkdir -p "$MODPATH/core"
for f in matrix_env.sh matrix_store.sh matrix_log.sh matrix_health.sh; do
    install_file "core/$f" "$MODPATH/core"
    chmod 755 "$MODPATH/core/$f" 2>/dev/null
done

# WebUI Assets
mkdir -p "$MODPATH/webroot"
for f in index.html app.css main.js; do
    if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "webroot/$f"; then
        install_file "webroot/$f" "$MODPATH/webroot"
        chmod 644 "$MODPATH/webroot/$f" 2>/dev/null
    fi
done

# 3. Persistent Data Initialization
DATA_DIR="/data/adb/matrix_module"
mkdir -p "$DATA_DIR/logs" 2>/dev/null
chmod 700 "$DATA_DIR" 2>/dev/null

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
