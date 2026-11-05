#!/bin/sh
##########################################################################################
# MatrixModule - Installer Failure Scenarios Test Suite
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="/tmp/matrix_installer_test_$$"
CUSTOMIZE_SCRIPT="$BASE_DIR/customize.sh"

cleanup() {
    rm -rf "$SANDBOX" 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "[*] Setting up Installer Failure Scenarios Sandbox: $SANDBOX"
mkdir -p "$SANDBOX"

ERRORS=0

fail() {
    echo "[-] FAIL: $1"
    ERRORS=$((ERRORS + 1))
}

pass() {
    echo "[+] PASS: $1"
}

# Helper to run customize.sh with specific environment and mock functions
run_customize_test() {
    _bootmode="$1"
    _api="$2"
    _arch="$3"
    _zipfile="$4"
    _modpath="$5"

    sh -c '
        BOOTMODE="'"$_bootmode"'"
        API="'"$_api"'"
        ARCH="'"$_arch"'"
        ZIPFILE="'"$_zipfile"'"
        MODPATH="'"$_modpath"'"
        
        ui_print() { echo "[UI] $*"; }
        abort() { echo "[ABORT] $*"; exit 2; }
        
        . "'"$CUSTOMIZE_SCRIPT"'"
    '
}

# 1. Test Recovery Flash Rejection (BOOTMODE != true)
echo "[*] Test 1: Testing recovery flash rejection (BOOTMODE=false)..."
out=$(run_customize_test "false" "34" "arm64" "dummy.zip" "$SANDBOX/mod" 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Install from root manager app"; then
    pass "Recovery flash successfully rejected with abort code 2"
else
    fail "Recovery flash check failed: code=$code, output=$out"
fi

# 2. Test Minimum Android SDK Rejection (API < 29)
echo "[*] Test 2: Testing obsolete Android SDK rejection (API=28 / Android 9)..."
out=$(run_customize_test "true" "28" "arm64" "dummy.zip" "$SANDBOX/mod" 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "requires Android 10+"; then
    pass "Obsolete SDK successfully rejected with abort code 2"
else
    fail "SDK minimum check failed: code=$code, output=$out"
fi

# 3. Test Unsupported Architecture Rejection (ARCH=mips)
echo "[*] Test 3: Testing unsupported architecture rejection (ARCH=mips)..."
out=$(run_customize_test "true" "34" "mips" "dummy.zip" "$SANDBOX/mod" 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Unsupported CPU Architecture"; then
    pass "Unsupported architecture successfully rejected with abort code 2"
else
    fail "Architecture check failed: code=$code, output=$out"
fi

# 4. Test Valid Environment Pass (arm64, API 34, BOOTMODE=true)
echo "[*] Test 4: Testing valid environment acceptance with mock zip..."
MOCK_MODPATH="$SANDBOX/valid_mod"
mkdir -p "$MOCK_MODPATH"
MOCK_ZIP="$BASE_DIR/dist/MatrixModule-v1.0.0.zip"

if [ -f "$MOCK_ZIP" ]; then
    out=$(run_customize_test "true" "34" "arm64" "$MOCK_ZIP" "$MOCK_MODPATH" 2>&1)
    code=$?
    if [ "$code" -eq 0 ] && echo "$out" | grep -q "Installation successful"; then
        pass "Valid installation simulation completed with exit code 0"
    else
        fail "Valid installation simulation failed: code=$code, output=$out"
    fi
else
    echo "[!] Warning: $MOCK_ZIP not found for full mock, testing environment check only"
fi

echo "=================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "[+] All Installer Failure Tests PASSED (0 errors)."
    exit 0
else
    echo "[-] Installer Failure Tests FAILED ($ERRORS error(s))."
    exit 1
fi
