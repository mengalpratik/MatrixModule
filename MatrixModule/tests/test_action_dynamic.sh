#!/bin/sh
##########################################################################################
# MatrixModule - Action Interface & Dynamic Path Test Suite (MM-DEF-04)
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="/tmp/matrix_action_test_$$"
SPACE_DIR="/tmp/matrix test spaces $$"

cleanup() {
    rm -rf "$SANDBOX" "$SPACE_DIR" 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "[*] Setting up Action Dynamic Path Sandboxes..."
mkdir -p "$SANDBOX" "$SPACE_DIR"

ERRORS=0

fail() {
    echo "[-] FAIL: $1"
    ERRORS=$((ERRORS + 1))
}

pass() {
    echo "[+] PASS: $1"
}

# 1. Test Static Syntax & Fallback Check
echo "[*] Test 1: Verifying elimination of hardcoded /data/adb fallback..."
if grep -q '\[ -z "\$MODPATH" \] && MODPATH="/data/adb/modules/matrix_module"' "$BASE_DIR/action.sh"; then
    fail "MM-DEF-04 violation: Hardcoded fallback /data/adb/modules/matrix_module still present"
else
    pass "MM-DEF-04 verified: Hardcoded fallback successfully removed from action.sh"
fi

if grep -q 'WebUI Location:   /data/adb/modules/matrix_module/webroot' "$BASE_DIR/action.sh"; then
    fail "MM-DEF-04 violation: Hardcoded WebUI Location still present"
else
    pass "MM-DEF-04 verified: Dynamic \$MODPATH/webroot used for WebUI Location"
fi

# 2. Test Execution in Path Containing Spaces
echo "[*] Test 2: Testing action.sh selftest in directory path containing spaces..."
cp -r "$BASE_DIR/core" "$BASE_DIR/webroot" "$BASE_DIR/action.sh" "$BASE_DIR/module.prop" "$BASE_DIR/service.sh" "$BASE_DIR/post-fs-data.sh" "$SPACE_DIR/"

out_spaces=$(sh "$SPACE_DIR/action.sh" selftest 2>&1)
code_spaces=$?

if [ "$code_spaces" -eq 0 ] && echo "$out_spaces" | grep -q "All core component files verified successfully"; then
    pass "action.sh selftest passed inside path containing spaces: '$SPACE_DIR'"
else
    fail "action.sh failed in space path: code=$code_spaces, output=$out_spaces"
fi

# 3. Test Dynamic MODDIR Environment Variable Support
echo "[*] Test 3: Testing explicit MODDIR environment variable override..."
CUSTOM_MODDIR="$SANDBOX/custom_location"
mkdir -p "$CUSTOM_MODDIR"
cp -r "$BASE_DIR/core" "$BASE_DIR/webroot" "$BASE_DIR/action.sh" "$BASE_DIR/module.prop" "$BASE_DIR/service.sh" "$BASE_DIR/post-fs-data.sh" "$CUSTOM_MODDIR/"

out_moddir=$(MODDIR="$CUSTOM_MODDIR" sh "$CUSTOM_MODDIR/action.sh" selftest 2>&1)
code_moddir=$?

if [ "$code_moddir" -eq 0 ] && echo "$out_moddir" | grep -q "All core component files verified successfully"; then
    pass "action.sh honored explicit MODDIR override: '$CUSTOM_MODDIR'"
else
    fail "action.sh failed with custom MODDIR: code=$code_moddir, output=$out_moddir"
fi

# 4. Test Dynamic WebUI Location Output
echo "[*] Test 4: Verifying WebUI Location reports dynamic MODPATH in dashboard output..."
out_dash=$(MODDIR="$CUSTOM_MODDIR" sh "$CUSTOM_MODDIR/action.sh" 2>&1)
if echo "$out_dash" | grep -q "WebUI Location:   $CUSTOM_MODDIR/webroot"; then
    pass "Dashboard output correctly printed dynamic WebUI path: $CUSTOM_MODDIR/webroot"
else
    fail "Dashboard failed to report dynamic WebUI path: $out_dash"
fi

echo "=================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "[+] All Action Dynamic Path Tests PASSED (0 errors)."
    exit 0
else
    echo "[-] Action Dynamic Path Tests FAILED ($ERRORS error(s))."
    exit 1
fi
