#!/system/bin/sh
##########################################################################################
# MatrixModule - Safe Uninstallation Script
##########################################################################################

DATA_DIR="/data/adb/matrix_module"

# Clean up state and runtime files
if [ -d "$DATA_DIR" ]; then
    rm -f "$DATA_DIR/state" 2>/dev/null
    rm -f "$DATA_DIR/health.json" 2>/dev/null
    rm -rf "$DATA_DIR/logs" 2>/dev/null

    # If the user wishes to completely remove data, remove config
    # By default, leave config.bak for safety if re-installed
    rm -f "$DATA_DIR/config" 2>/dev/null
    rmdir "$DATA_DIR" 2>/dev/null || true
fi

exit 0
