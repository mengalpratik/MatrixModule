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

# Common function loader for installer subshell execution
LOAD_INSTALLER_FUNCS='
    ui_print() { echo "[UI] $*"; }
    abort() { echo "[ABORT] $*"; exit 2; }
    eval "$(sed -n "/^get_octal_mode() {/,/^}/p" "'"$CUSTOMIZE_SCRIPT"'")"
    eval "$(sed -n "/^get_file_owner() {/,/^}/p" "'"$CUSTOMIZE_SCRIPT"'")"
    eval "$(sed -n "/^apply_perm() {/,/^}/p" "'"$CUSTOMIZE_SCRIPT"'")"
    eval "$(sed -n "/^apply_perm_recursive() {/,/^}/p" "'"$CUSTOMIZE_SCRIPT"'")"
    eval "$(sed -n "/^verify_installed_permissions() {/,/^}/p" "'"$CUSTOMIZE_SCRIPT"'")"
'

# 9. Test apply_perm error handling: missing target
echo "[*] Test 9: Testing apply_perm failure on missing target..."
out=$(sh -c '
    '"$LOAD_INSTALLER_FUNCS"'
    apply_perm "/tmp/nonexistent_target_$$" 0 0 0644
' 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "missing"; then
    pass "apply_perm aborted with code 2 on missing target"
else
    fail "apply_perm failed to abort on missing target: code=$code, output=$out"
fi

# 10. Test apply_perm mandatory chmod failure
echo "[*] Test 10: Testing apply_perm abort on mandatory chmod failure..."
TEST_PERM_FILE="$SANDBOX/perm_fail_test"
touch "$TEST_PERM_FILE"
out=$(sh -c '
    '"$LOAD_INSTALLER_FUNCS"'
    chmod() { return 1; }
    apply_perm "'"$TEST_PERM_FILE"'" 0 0 0755
' 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Mandatory permission failure"; then
    pass "apply_perm aborted on mandatory chmod failure"
else
    fail "apply_perm failed to abort on chmod failure: code=$code, output=$out"
fi

# 11. Test apply_perm SELinux context failure handling (distinguish from mandatory permission)
echo "[*] Test 11: Testing apply_perm non-fatal handling of unsupported SELinux context..."
TEST_CON_FILE="$SANDBOX/con_test"
touch "$TEST_CON_FILE"
out=$(sh -c '
    '"$LOAD_INSTALLER_FUNCS"'
    chcon() { return 1; }
    apply_perm "'"$TEST_CON_FILE"'" 0 0 0644 "u:object_r:system_file:s0"
' 2>&1)
code=$?
if [ "$code" -eq 0 ] && echo "$out" | grep -q "SELinux context not supported or failed"; then
    pass "apply_perm warned but did not abort on unsupported SELinux context"
else
    fail "apply_perm failed SELinux context handling: code=$code, output=$out"
fi

# Helper to populate complete valid mock module hierarchy for verification tests
create_mock_valid_module() {
    _d="$1"
    rm -rf "$_d" 2>/dev/null
    mkdir -p "$_d/core" "$_d/webroot" "$SANDBOX/data/mock_data/logs"
    chmod 755 "$_d" "$_d/core" "$_d/webroot"
    chmod 700 "$SANDBOX/data/mock_data" "$SANDBOX/data/mock_data/logs"
    
    for f in post-fs-data.sh service.sh action.sh uninstall.sh; do
        touch "$_d/$f"
        chmod 755 "$_d/$f"
    done
    for f in matrix_env.sh matrix_store.sh matrix_log.sh matrix_health.sh; do
        touch "$_d/core/$f"
        chmod 755 "$_d/core/$f"
    done
    touch "$_d/module.prop"
    chmod 644 "$_d/module.prop"
    for f in index.html app.css main.js; do
        touch "$_d/webroot/$f"
        chmod 644 "$_d/webroot/$f"
    done
}

# 12. Test verify_installed_permissions failure on excessively permissive script (0777)
echo "[*] Test 12: Testing verify_installed_permissions abort on overly permissive script (0777)..."
MOCK_VERIFY_DIR="$SANDBOX/mock_verify_mod"
create_mock_valid_module "$MOCK_VERIFY_DIR"
chmod 777 "$MOCK_VERIFY_DIR/service.sh"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    MODPATH="'"$MOCK_VERIFY_DIR"'"
    DATA_DIR="'"$SANDBOX/data/mock_data"'"
    verify_installed_permissions
' 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Exact mode mismatch"; then
    pass "verify_installed_permissions aborted on 0777 service.sh"
else
    fail "verify_installed_permissions failed to reject 0777: code=$code, output=$out"
fi

# 13. Test verify_installed_permissions failure on restrictive script (0644)
echo "[*] Test 13: Testing verify_installed_permissions abort on non-executable script (0644)..."
create_mock_valid_module "$MOCK_VERIFY_DIR"
chmod 644 "$MOCK_VERIFY_DIR/service.sh"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    MODPATH="'"$MOCK_VERIFY_DIR"'"
    DATA_DIR="'"$SANDBOX/data/mock_data"'"
    verify_installed_permissions
' 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Exact mode mismatch"; then
    pass "verify_installed_permissions aborted on 0644 service.sh"
else
    fail "verify_installed_permissions failed to reject 0644: code=$code, output=$out"
fi

# 14. Test verify_installed_permissions failure on incorrect metadata mode (0600)
echo "[*] Test 14: Testing verify_installed_permissions abort on incorrect metadata mode (0600)..."
create_mock_valid_module "$MOCK_VERIFY_DIR"
chmod 600 "$MOCK_VERIFY_DIR/module.prop"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    MODPATH="'"$MOCK_VERIFY_DIR"'"
    DATA_DIR="'"$SANDBOX/data/mock_data"'"
    verify_installed_permissions
' 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Exact mode mismatch"; then
    pass "verify_installed_permissions aborted on 0600 module.prop"
else
    fail "verify_installed_permissions failed to reject 0600 module.prop: code=$code, output=$out"
fi

# 15. Test verify_installed_permissions failure on incorrect directory mode (0700)
echo "[*] Test 15: Testing verify_installed_permissions abort on incorrect directory mode (0700)..."
create_mock_valid_module "$MOCK_VERIFY_DIR"
chmod 700 "$MOCK_VERIFY_DIR"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    MODPATH="'"$MOCK_VERIFY_DIR"'"
    DATA_DIR="'"$SANDBOX/data/mock_data"'"
    verify_installed_permissions
' 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Exact mode mismatch"; then
    pass "verify_installed_permissions aborted on 0700 root directory"
else
    fail "verify_installed_permissions failed to reject 0700 directory: code=$code, output=$out"
fi

# 16. Test verify_installed_permissions failure on incorrect persistent directory mode (0755)
echo "[*] Test 16: Testing verify_installed_permissions abort on incorrect persistent data mode (0755)..."
create_mock_valid_module "$MOCK_VERIFY_DIR"
chmod 755 "$SANDBOX/data/mock_data"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    MODPATH="'"$MOCK_VERIFY_DIR"'"
    DATA_DIR="'"$SANDBOX/data/mock_data"'"
    verify_installed_permissions
' 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Exact mode mismatch"; then
    pass "verify_installed_permissions aborted on 0755 persistent data directory"
else
    fail "verify_installed_permissions failed to reject 0755 persistent dir: code=$code, output=$out"
fi

# 17. Test apply_perm mandatory root chown failure abort when running as root
echo "[*] Test 17: Testing apply_perm abort on mandatory root chown failure..."
TEST_CHOWN_FILE="$SANDBOX/chown_fail_test"
touch "$TEST_CHOWN_FILE"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    id() { echo 0; }
    chown() { return 1; }
    apply_perm "'"$TEST_CHOWN_FILE"'" 0 0 0644
' 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Mandatory ownership failure"; then
    pass "apply_perm aborted on mandatory root chown failure"
else
    fail "apply_perm failed to abort on root chown failure: code=$code, output=$out"
fi

# 18. Test apply_perm set_perm success and verification path
echo "[*] Test 18: Testing apply_perm set_perm success path..."
TEST_SETPERM_FILE="$SANDBOX/setperm_success_test"
touch "$TEST_SETPERM_FILE"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    set_perm() { chmod "$4" "$1"; return 0; }
    apply_perm "'"$TEST_SETPERM_FILE"'" 0 0 0755
' 2>&1)
code=$?
perm_res=$(get_perm "$TEST_SETPERM_FILE")
if [ "$code" -eq 0 ] && [ "$perm_res" = "755" ]; then
    pass "apply_perm set_perm success path applied and verified exact mode 755"
else
    fail "apply_perm set_perm success test failed: code=$code, perm=$perm_res, output=$out"
fi

# 19. Test apply_perm set_perm failure fallback path
echo "[*] Test 19: Testing apply_perm set_perm failure fallback path..."
TEST_SETPERM_FALLBACK="$SANDBOX/setperm_fallback_test"
touch "$TEST_SETPERM_FALLBACK"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    set_perm() { return 1; }
    apply_perm "'"$TEST_SETPERM_FALLBACK"'" 0 0 0644
' 2>&1)
code=$?
perm_fallback_res=$(get_perm "$TEST_SETPERM_FALLBACK")
if [ "$code" -eq 0 ] && [ "$perm_fallback_res" = "644" ] && echo "$out" | grep -q "using fallback"; then
    pass "apply_perm safely fell back to POSIX and applied mode 644 on set_perm failure"
else
    fail "apply_perm set_perm fallback test failed: code=$code, perm=$perm_fallback_res, output=$out"
fi

# 20. Test apply_perm_recursive set_perm_recursive failure fallback path
echo "[*] Test 20: Testing apply_perm_recursive fallback on set_perm_recursive failure..."
TEST_REC_DIR="$SANDBOX/rec_fallback_test"
mkdir -p "$TEST_REC_DIR/subdir"
touch "$TEST_REC_DIR/file1" "$TEST_REC_DIR/subdir/file2"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    set_perm_recursive() { return 1; }
    apply_perm_recursive "'"$TEST_REC_DIR"'" 0 0 0755 0644
' 2>&1)
code=$?
d_perm=$(get_perm "$TEST_REC_DIR/subdir")
f_perm=$(get_perm "$TEST_REC_DIR/subdir/file2")
if [ "$code" -eq 0 ] && [ "$d_perm" = "755" ] && [ "$f_perm" = "644" ] && echo "$out" | grep -q "using fallback"; then
    pass "apply_perm_recursive safely fell back to POSIX find on set_perm_recursive failure"
else
    fail "apply_perm_recursive fallback failed: code=$code, d_perm=$d_perm, f_perm=$f_perm, output=$out"
fi

# 21. Test verify_installed_permissions root ownership check failure
echo "[*] Test 21: Testing verify_installed_permissions abort on root ownership mismatch..."
create_mock_valid_module "$MOCK_VERIFY_DIR"
out=$(sh -c "$LOAD_INSTALLER_FUNCS"'
    id() { echo 0; }
    get_file_owner() { echo "1000:1000"; }
    MODPATH="'"$MOCK_VERIFY_DIR"'"
    DATA_DIR="'"$SANDBOX/data/mock_data"'"
    verify_installed_permissions
' 2>&1)
code=$?
if [ "$code" -eq 2 ] && echo "$out" | grep -q "Ownership mismatch"; then
    pass "verify_installed_permissions aborted on root ownership mismatch"
else
    fail "verify_installed_permissions failed to abort on ownership mismatch: code=$code, output=$out"
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
