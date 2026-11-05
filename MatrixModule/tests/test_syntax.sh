#!/bin/sh
##########################################################################################
# MatrixModule Test: Shell Syntax Validation
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ERRS=0

echo "[*] Running Shell Syntax Validation (sh -n)..."

check_syntax() {
    file="$1"
    if [ -f "$file" ]; then
        if sh -n "$file"; then
            echo "  [PASS] $file"
        else
            echo "  [FAIL] Syntax error in $file"
            ERRS=$((ERRS + 1))
        fi
    fi
}

# Root lifecycle scripts
for f in customize.sh post-fs-data.sh service.sh action.sh uninstall.sh build.sh; do
    check_syntax "$BASE_DIR/$f"
done

# Update binary
check_syntax "$BASE_DIR/META-INF/com/google/android/update-binary"

# Core helpers
for f in "$BASE_DIR"/core/*.sh; do
    check_syntax "$f"
done

# Test scripts
for f in "$BASE_DIR"/tests/*.sh; do
    [ "$f" != "$0" ] && check_syntax "$f"
done

if [ "$ERRS" -eq 0 ]; then
    echo "[+] All shell scripts passed syntax validation."
    exit 0
else
    echo "[-] Found $ERRS syntax errors."
    exit 1
fi
