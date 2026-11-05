#!/bin/sh
##########################################################################################
# MatrixModule - Installer Failure Scenarios Test Suite (Hardened)
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="/tmp/matrix_installer_test_$$"
CUSTOMIZE_SCRIPT="$BASE_DIR/customize.sh"

cleanup() {
    rm -rf "$SANDBOX" 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "[*] Setting up Installer Failure Scenarios Sandbox: $SANDBOX"
mkdir -p "$SANDBOX/data/matrix_module" "$SANDBOX/mod"

ERRORS=0
PASSES=0
SKIPS=0

fail() {
    echo "[-] FAIL: $1"
    ERRORS=$((ERRORS + 1))
}

pass() {
    echo "[+] PASS: $1"
    PASSES=$((PASSES + 1))
}

skip() {
    echo "[-] SKIP: $1"
    SKIPS=$((SKIPS + 1))
}

get_perm() {
    stat -c "%a" "$1" 2>/dev/null || python3 -c "import os, sys; print(oct(os.stat(sys.argv[1]).st_mode)[-3:])" "$1" 2>/dev/null
}

# Helper to run customize.sh with specific environment and mock functions
run_customize_test() {
    _bootmode="$1"
    _api="$2"
    _arch="$3"
    _zipfile="$4"
    _modpath="$5"
    _datadir="${6:-$SANDBOX/data/matrix_module}"

    sh -c '
        BOOTMODE="'"$_bootmode"'"
        API="'"$_api"'"
        ARCH="'"$_arch"'"
        ZIPFILE="'"$_zipfile"'"
        MODPATH="'"$_modpath"'"
        DATA_DIR="'"$_datadir"'"
        
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

# 4. Test Extraction Failure on Corrupted ZIP (abort handling)
echo "[*] Test 4: Testing extraction failure handling on corrupted ZIP..."
CORRUPT_ZIP="$SANDBOX/corrupt.zip"
echo "NOT_A_VALID_ZIP" > "$CORRUPT_ZIP"
out=$(run_customize_test "true" "34" "arm64" "$CORRUPT_ZIP" "$SANDBOX/mod_corrupt" 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Failed to extract"; then
    pass "Corrupted ZIP extraction failure safely aborted with exit code 2"
else
    fail "Corrupted ZIP handling failed to abort: code=$code, output=$out"
fi

# 5. Dynamic Detection & Positive Installation Simulation with Current Release ZIP
echo "[*] Test 5: Testing valid environment acceptance with current release ZIP..."
MOCK_MODPATH="$SANDBOX/valid_mod"
mkdir -p "$MOCK_MODPATH"

CURRENT_VER=$(grep "^version=" "$BASE_DIR/module.prop" | cut -d= -f2 | tr -d '[:space:]')
CURRENT_ZIP="$BASE_DIR/dist/MatrixModule-${CURRENT_VER}.zip"

if [ -f "$CURRENT_ZIP" ]; then
    out=$(run_customize_test "true" "34" "arm64" "$CURRENT_ZIP" "$MOCK_MODPATH" "$SANDBOX/data/matrix_module" 2>&1)
    code=$?
    if [ "$code" -eq 0 ] && echo "$out" | grep -q "Installation successful"; then
        pass "Valid installation simulation completed with exit code 0 using $CURRENT_ZIP"

        # Verify Installed Permissions
        echo "[*] Test 5a: Verifying installed file permissions in sandbox..."
        prop_perm=$(get_perm "$MOCK_MODPATH/module.prop")
        service_perm=$(get_perm "$MOCK_MODPATH/service.sh")
        post_perm=$(get_perm "$MOCK_MODPATH/post-fs-data.sh")
        core_perm=$(get_perm "$MOCK_MODPATH/core/matrix_health.sh")
        html_perm=$(get_perm "$MOCK_MODPATH/webroot/index.html")
        mod_dir_perm=$(get_perm "$MOCK_MODPATH")
        web_dir_perm=$(get_perm "$MOCK_MODPATH/webroot")

        if [ "$prop_perm" = "644" ]; then
            pass "Installed module.prop has non-executable permission 0644"
        else
            fail "Installed module.prop permission mismatch: expected 644, got $prop_perm"
        fi

        if [ "$service_perm" = "755" ] && [ "$post_perm" = "755" ] && [ "$core_perm" = "755" ]; then
            pass "Installed shell scripts have executable permission 0755"
        else
            fail "Installed script permissions mismatch: service=$service_perm, post-fs=$post_perm, core=$core_perm"
        fi

        if [ "$html_perm" = "644" ]; then
            pass "Installed webroot assets have non-executable permission 0644"
        else
            fail "Installed webroot permission mismatch: expected 644, got $html_perm"
        fi

        if [ "$mod_dir_perm" = "755" ] && [ "$web_dir_perm" = "755" ]; then
            pass "Installed directories have permission 0755"
        else
            fail "Installed directory permissions mismatch: root=$mod_dir_perm, webroot=$web_dir_perm"
        fi
    else
        fail "Valid installation simulation failed: code=$code, output=$out"
    fi
else
    skip "Release package $CURRENT_ZIP not found; skipping positive installation and permission tests"
fi

# 6. Test MM-DEF-05: update-binary Shebang Verification
echo "[*] Test 6: MM-DEF-05 - Verifying update-binary shebang uses /system/bin/sh..."
UPDATE_BIN="$BASE_DIR/META-INF/com/google/android/update-binary"
if [ -f "$UPDATE_BIN" ]; then
    first_line=$(head -n 1 "$UPDATE_BIN")
    if [ "$first_line" = "#!/system/bin/sh" ]; then
        pass "MM-DEF-05 verified: update-binary uses #!/system/bin/sh"
    else
        fail "MM-DEF-05 failure: update-binary shebang is '$first_line', expected #!/system/bin/sh"
    fi
else
    fail "update-binary missing from $UPDATE_BIN"
fi

# 7. Test updater-script Contract
echo "[*] Test 7: Verifying updater-script dummy contract..."
UPDATER_SCRIPT="$BASE_DIR/META-INF/com/google/android/updater-script"
if [ -f "$UPDATER_SCRIPT" ] && grep -q "#MAGISK" "$UPDATER_SCRIPT"; then
    pass "updater-script verified with #MAGISK contract token"
else
    fail "updater-script missing or invalid"
fi

# 8. Test update-binary Syntax
echo "[*] Test 8: Verifying update-binary syntax..."
if sh -n "$UPDATE_BIN"; then
    pass "update-binary passed POSIX sh syntax validation"
else
    fail "update-binary syntax error"
fi

echo "=================================================="
echo " Results: $PASSES passed, $ERRORS failed, $SKIPS skipped."
if [ "$ERRORS" -eq 0 ]; then
    echo "[+] All Installer Failure Tests PASSED (0 errors)."
    exit 0
else
    echo "[-] Installer Failure Tests FAILED ($ERRORS error(s))."
    exit 1
fi
