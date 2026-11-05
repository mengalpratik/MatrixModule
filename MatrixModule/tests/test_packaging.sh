#!/bin/sh
##########################################################################################
# MatrixModule Test: Packaging & ZIP Integrity Validation
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$BASE_DIR/dist"
ERRS=0

echo "[*] Testing Module Packaging via build.sh..."

sh "$BASE_DIR/build.sh"

VERSION=$(grep "^version=" "$BASE_DIR/module.prop" | cut -d= -f2)
ZIP_FILE="$DIST_DIR/MatrixModule-${VERSION}.zip"

if [ ! -f "$ZIP_FILE" ]; then
    echo "  [FAIL] ZIP file was not created in $DIST_DIR"
    exit 1
fi

echo "  [PASS] Found generated package: $ZIP_FILE"

# 1. Archive integrity test
if unzip -t "$ZIP_FILE" >/dev/null 2>&1; then
    echo "  [PASS] ZIP archive integrity verified (unzip -t passed)"
else
    echo "  [FAIL] ZIP archive corrupted"
    ERRS=$((ERRS + 1))
fi

# 2. Check for required inclusions
for req in "module.prop" "customize.sh" "post-fs-data.sh" "service.sh" "action.sh" "core/matrix_env.sh" "webroot/index.html"; do
    if unzip -l "$ZIP_FILE" | grep -q "$req"; then
        echo "  [PASS] Archive contains: $req"
    else
        echo "  [FAIL] Missing required entry in ZIP: $req"
        ERRS=$((ERRS + 1))
    fi
done

# 3. Security Boundary: Ensure references/ is EXCLUDED
if unzip -l "$ZIP_FILE" 2>/dev/null | grep -q "references/"; then
    echo "  [FAIL] SECURITY VIOLATION: references/ included in deployable ZIP!"
    ERRS=$((ERRS + 1))
else
    echo "  [PASS] Security Boundary: references/ correctly excluded from release ZIP"
fi

if [ "$ERRS" -eq 0 ]; then
    echo "[+] Packaging validation passed."
    exit 0
else
    echo "[-] Found $ERRS packaging validation errors."
    exit 1
fi
