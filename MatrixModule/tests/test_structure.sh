#!/bin/sh
##########################################################################################
# MatrixModule Test: Directory & Metadata Structure Validation
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ERRS=0

echo "[*] Running Structure & Metadata Validation..."

check_file() {
    if [ ! -f "$1" ]; then
        echo "  [FAIL] Missing required file: $1"
        ERRS=$((ERRS + 1))
    else
        echo "  [PASS] File exists: $1"
    fi
}

check_dir() {
    if [ ! -d "$1" ]; then
        echo "  [FAIL] Missing required directory: $1"
        ERRS=$((ERRS + 1))
    else
        echo "  [PASS] Directory exists: $1"
    fi
}

# 1. Structure checks
check_file "$BASE_DIR/module.prop"
check_file "$BASE_DIR/customize.sh"
check_file "$BASE_DIR/post-fs-data.sh"
check_file "$BASE_DIR/service.sh"
check_file "$BASE_DIR/action.sh"
check_file "$BASE_DIR/uninstall.sh"
check_file "$BASE_DIR/META-INF/com/google/android/update-binary"
check_file "$BASE_DIR/META-INF/com/google/android/updater-script"
check_dir "$BASE_DIR/core"
check_dir "$BASE_DIR/webroot"
check_dir "$BASE_DIR/docs"
check_dir "$BASE_DIR/tests"
check_dir "$BASE_DIR/references"
check_file "$BASE_DIR/references/README.md"

# 2. Metadata checks
check_prop() {
    key="$1"
    val=$(grep "^${key}=" "$BASE_DIR/module.prop" 2>/dev/null | cut -d= -f2-)
    if [ -z "$val" ]; then
        echo "  [FAIL] module.prop missing key: $key"
        ERRS=$((ERRS + 1))
    else
        echo "  [PASS] module.prop: $key=$val"
    fi
}

check_prop "id"
check_prop "name"
check_prop "version"
check_prop "versionCode"
check_prop "author"
check_prop "description"

# 3. WebUI assets check
check_file "$BASE_DIR/webroot/index.html"
check_file "$BASE_DIR/webroot/app.css"
check_file "$BASE_DIR/webroot/main.js"

if [ "$ERRS" -eq 0 ]; then
    echo "[+] Structure and metadata validation passed."
    exit 0
else
    echo "[-] Found $ERRS structure validation errors."
    exit 1
fi
