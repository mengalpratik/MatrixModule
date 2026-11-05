#!/bin/sh
##########################################################################################
# MatrixModule Test: Packaging & ZIP Integrity Validation (Isolated & Safe)
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX_DIST="/tmp/matrix_test_dist_$$"

cleanup() {
    rm -rf "$SANDBOX_DIST" 2>/dev/null
}
trap cleanup EXIT INT TERM

ERRS=0
PASSES=0
SKIPS=0

pass() {
    echo "  [PASS] $1"
    PASSES=$((PASSES + 1))
}

fail() {
    echo "  [FAIL] $1"
    ERRS=$((ERRS + 1))
}

skip() {
    echo "  [SKIP] $1"
    SKIPS=$((SKIPS + 1))
}

echo "[*] Testing Module Packaging in isolated sandbox: $SANDBOX_DIST..."
mkdir -p "$SANDBOX_DIST"

# Execute build.sh pointing exclusively to the temporary sandbox
DIST_DIR="$SANDBOX_DIST" sh "$BASE_DIR/build.sh" >/dev/null 2>&1
build_code=$?

if [ "$build_code" -ne 0 ]; then
    fail "build.sh failed with exit code $build_code"
    exit 1
fi

VERSION=$(grep "^version=" "$BASE_DIR/module.prop" | cut -d= -f2 | tr -d '[:space:]')
ZIP_FILE="$SANDBOX_DIST/MatrixModule-${VERSION}.zip"

if [ ! -f "$ZIP_FILE" ]; then
    fail "ZIP file was not created in sandbox $SANDBOX_DIST"
    exit 1
fi

pass "Found generated package in isolated directory: $ZIP_FILE"

# 1. Archive integrity test
if unzip -t "$ZIP_FILE" >/dev/null 2>&1; then
    pass "ZIP archive integrity verified (unzip -t passed)"
else
    fail "ZIP archive corrupted"
fi

# 2. Check for required inclusions at root
for req in "module.prop" "customize.sh" "post-fs-data.sh" "service.sh" "action.sh" "core/matrix_env.sh" "webroot/index.html"; do
    if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "$req" || unzip -l "$ZIP_FILE" | grep -q "$req"; then
        pass "Archive contains: $req"
    else
        fail "Missing required entry in ZIP: $req"
    fi
done

# 3. Security Boundary: Ensure references/ is EXCLUDED
if unzip -l "$ZIP_FILE" 2>/dev/null | grep -q "references/"; then
    fail "SECURITY VIOLATION: references/ included in deployable ZIP!"
else
    pass "Security Boundary: references/ correctly excluded from release ZIP"
fi

# 4. Root structure check: module.prop must be at ZIP root, not nested
if unzip -l "$ZIP_FILE" | grep -Eq '^[ ]*[0-9]+[ ]+[^ ]+[ ]+[^ ]+[ ]+module\.prop$'; then
    pass "Root placement verified: module.prop is at ZIP root"
else
    fail "Root placement failed: module.prop is nested or missing"
fi

# 5. Unix External Permission Attributes Verification
echo "[*] Verifying ZIP entry Unix permission attributes via zipinfo..."
_attr_err=0
# Verify all directory entries have exact mode drwxr-xr-x (0755)
while IFS= read -r line; do
    [ -z "$line" ] && continue
    _entry_perm=$(echo "$line" | awk '{print $1}')
    _entry_name=$(echo "$line" | awk '{print $NF}')
    case "$_entry_name" in
        */)
            if [ "$_entry_perm" != "drwxr-xr-x" ]; then
                fail "Directory entry $_entry_name has incorrect mode: $_entry_perm (expected drwxr-xr-x / 0755)"
                _attr_err=$((_attr_err + 1))
            fi
            ;;
        *.sh|*update-binary)
            if [ "$_entry_perm" != "-rwxr-xr-x" ]; then
                fail "Executable script $_entry_name has incorrect mode: $_entry_perm (expected -rwxr-xr-x / 0755)"
                _attr_err=$((_attr_err + 1))
            fi
            ;;
        *)
            if [ "$_entry_perm" != "-rw-r--r--" ]; then
                fail "Non-executable asset $_entry_name has incorrect mode: $_entry_perm (expected -rw-r--r-- / 0644)"
                _attr_err=$((_attr_err + 1))
            fi
            ;;
    esac
done << EOF
$(zipinfo "$ZIP_FILE" | grep -E '^[-d][rwx-]{9}')
EOF

if [ "$_attr_err" -eq 0 ]; then
    pass "All ZIP directory entries normalized to exact 0755 and file modes strictly verified"
else
    fail "ZIP archive contains $_attr_err entries with improper permissions"
fi

# 6. Production release artifact verification in dist/
PROD_ZIP="$BASE_DIR/dist/MatrixModule-${VERSION}.zip"
if [ -f "$PROD_ZIP" ]; then
    echo "[*] Verifying production release artifact in dist/..."
    if unzip -t "$PROD_ZIP" >/dev/null 2>&1; then
        pass "Production release ZIP exists and passes integrity check ($PROD_ZIP)"
    else
        fail "Production release ZIP is corrupted: $PROD_ZIP"
    fi
else
    skip "Production release ZIP not yet built in dist/; sandbox build verified"
fi

echo "=================================================="
echo " Results: $PASSES passed, $ERRS failed, $SKIPS skipped."
if [ "$ERRS" -eq 0 ]; then
    echo "[+] Packaging validation passed."
    exit 0
else
    echo "[-] Found $ERRS packaging validation errors."
    exit 1
fi
