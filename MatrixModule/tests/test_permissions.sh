#!/bin/sh
##########################################################################################
# MatrixModule Test: File Permissions Validation
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ERRS=0

echo "[*] Running File Permissions Validation..."

check_exec() {
    file="$1"
    if [ -f "$file" ]; then
        if [ -x "$file" ]; then
            echo "  [PASS] Executable: $file"
        else
            echo "  [FAIL] Not executable: $file"
            ERRS=$((ERRS + 1))
        fi
    fi
}

check_non_exec() {
    file="$1"
    if [ -f "$file" ]; then
        if [ ! -x "$file" ]; then
            echo "  [PASS] Non-executable: $file"
        else
            echo "  [FAIL] Unexpected executable bit: $file"
            ERRS=$((ERRS + 1))
        fi
    fi
}

# Lifecycle scripts must be executable
for f in customize.sh post-fs-data.sh service.sh action.sh uninstall.sh build.sh; do
    check_exec "$BASE_DIR/$f"
done
check_exec "$BASE_DIR/META-INF/com/google/android/update-binary"

for f in "$BASE_DIR"/core/*.sh; do
    check_exec "$f"
done

# Web assets and metadata must be non-executable
check_non_exec "$BASE_DIR/module.prop"
check_non_exec "$BASE_DIR/META-INF/com/google/android/updater-script"
check_non_exec "$BASE_DIR/webroot/index.html"
check_non_exec "$BASE_DIR/webroot/app.css"
check_non_exec "$BASE_DIR/webroot/main.js"

if [ "$ERRS" -eq 0 ]; then
    echo "[+] Permissions validation passed."
    exit 0
else
    echo "[-] Found $ERRS permission validation errors."
    exit 1
fi
