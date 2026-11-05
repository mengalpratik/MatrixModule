#!/bin/sh
##########################################################################################
# MatrixModule - Centralized Atomic Store Test Suite (Hardened & Expanded)
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="$BASE_DIR/core"
SANDBOX="/tmp/matrix_store_test_$$"

cleanup() {
    rm -rf "$SANDBOX" 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "[*] Initializing Centralized Store Test Sandbox: $SANDBOX"
mkdir -p "$SANDBOX"

# Source store engine
. "$CORE_DIR/matrix_store.sh"

# Point store targets to sandboxed paths
MATRIX_DATA_DIR="$SANDBOX"
MATRIX_CONF_FILE="$MATRIX_DATA_DIR/config"
MATRIX_BAK_FILE="$MATRIX_DATA_DIR/config.bak"
MATRIX_STATE_FILE="$MATRIX_DATA_DIR/state"

ERRORS=0

fail() {
    echo "[-] FAIL: $1"
    ERRORS=$((ERRORS + 1))
}

pass() {
    echo "[+] PASS: $1"
}

# 1. Test Store Initialization & Defaults
echo "[*] Test 1: Store Initialization & Default Generation..."
if matrix_store_init; then
    if [ -f "$MATRIX_CONF_FILE" ] && [ -f "$MATRIX_BAK_FILE" ]; then
        pass "Defaults created (config and config.bak exist)"
    else
        fail "Default config files not created"
    fi
else
    fail "matrix_store_init returned non-zero"
fi

# 2. Test Default Values Retrieval
echo "[*] Test 2: Reading Default Configuration Keys..."
val=$(matrix_cfg_get "watchdog_interval_sec" "999")
if [ "$val" = "300" ]; then
    pass "matrix_cfg_get retrieved correct default watchdog_interval_sec=300"
else
    fail "matrix_cfg_get expected 300, got: '$val'"
fi

val_missing=$(matrix_cfg_get "non_existent_key" "default_fallback")
if [ "$val_missing" = "default_fallback" ]; then
    pass "matrix_cfg_get fallback value returned correctly for missing key"
else
    fail "matrix_cfg_get fallback failed, got: '$val_missing'"
fi

# 3. Test Setting & Updating Keys (Atomic Write)
echo "[*] Test 3: Setting Configuration Key..."
if matrix_cfg_set "watchdog_interval_sec" "120"; then
    val_updated=$(matrix_cfg_get "watchdog_interval_sec" "999")
    if [ "$val_updated" = "120" ]; then
        pass "matrix_cfg_set successfully updated watchdog_interval_sec=120"
    else
        fail "matrix_cfg_get expected 120 after update, got: '$val_updated'"
    fi
    
    # Check no duplicate lines
    line_count=$(grep -c "^watchdog_interval_sec=" "$MATRIX_CONF_FILE")
    if [ "$line_count" -eq 1 ]; then
        pass "Configuration deduplication verified (exactly 1 occurrence)"
    else
        fail "Duplicate configuration keys detected: count=$line_count"
    fi
else
    fail "matrix_cfg_set returned non-zero"
fi

# 4. Test Deleting Keys
echo "[*] Test 4: Deleting Configuration Key..."
matrix_cfg_set "temp_key" "test_value"
matrix_cfg_del "temp_key"
del_val=$(matrix_cfg_get "temp_key" "DELETED")
if [ "$del_val" = "DELETED" ]; then
    pass "matrix_cfg_del successfully deleted temp_key"
else
    fail "matrix_cfg_del failed to remove key, got: '$del_val'"
fi

# 5. Test State Management
echo "[*] Test 5: State Key-Value Persistence..."
matrix_state_set "boot_stage" "post-fs-data"
matrix_state_set "boot_count" "5"

state_stage=$(matrix_state_get "boot_stage" "none")
state_count=$(matrix_state_get "boot_count" "0")

if [ "$state_stage" = "post-fs-data" ] && [ "$state_count" = "5" ]; then
    pass "matrix_state_set and matrix_state_get verified"
else
    fail "State retrieval mismatch: stage='$state_stage', count='$state_count'"
fi

# 6. Test Backup & Restore (direct mutation test)
echo "[*] Test 6: Configuration Backup & Restore..."
matrix_cfg_set "feature_x" "original_state"
matrix_cfg_backup

# Directly mutate config file (simulating out-of-band edit)
echo "feature_x=mutated_state" >> "$MATRIX_CONF_FILE"
mutated_val=$(matrix_cfg_get "feature_x" "")

if [ "$mutated_val" = "mutated_state" ]; then
    matrix_cfg_restore
    restored_val=$(matrix_cfg_get "feature_x" "")
    if [ "$restored_val" = "original_state" ]; then
        pass "matrix_cfg_restore successfully restored pre-mutation state from backup"
    else
        fail "matrix_cfg_restore failed, got: '$restored_val'"
    fi
else
    fail "Direct mutation check failed before restore test"
fi

# 7. Test Corrupted Config Auto-Recovery on Missing File
echo "[*] Test 7: Auto-Recovery from Backup on Missing Config..."
rm -f "$MATRIX_CONF_FILE"
matrix_store_init
recovered_val=$(matrix_cfg_get "feature_x" "")
if [ "$recovered_val" = "original_state" ]; then
    pass "matrix_store_init recovered config from config.bak automatically"
else
    fail "Auto-recovery failed, got: '$recovered_val'"
fi

# 8. Test MM-DEF-02: Backup Preservation Across Multiple Writes
echo "[*] Test 8: MM-DEF-02 - Verifying config.bak is NOT eagerly overwritten on writes..."
matrix_cfg_set "watchdog_interval_sec" "200"
matrix_cfg_backup
bak_before=$(grep "^watchdog_interval_sec=" "$MATRIX_BAK_FILE" | cut -d= -f2)

# Perform multiple writes
matrix_cfg_set "watchdog_interval_sec" "600"
matrix_cfg_set "diagnostics_enabled" "0"
bak_after=$(grep "^watchdog_interval_sec=" "$MATRIX_BAK_FILE" | cut -d= -f2)

if [ "$bak_before" = "200" ] && [ "$bak_after" = "200" ]; then
    pass "MM-DEF-02 verified: config.bak preserved last-known-good state (200), not overwritten by 600"
else
    fail "MM-DEF-02 violation: config.bak was modified during matrix_cfg_set (before=$bak_before, after=$bak_after)"
fi

# 9. Test MM-DEF-01: Shell Injection & Metacharacter Rejection
echo "[*] Test 9: MM-DEF-01 - Testing rejection of malicious inputs & metacharacters..."
INJECTION_BLOCKED=0

# Semicolon command injection
if ! matrix_cfg_set "watchdog_interval_sec" "300; reboot"; then
    INJECTION_BLOCKED=$((INJECTION_BLOCKED + 1))
fi

# Backtick command substitution
if ! matrix_cfg_set "watchdog_interval_sec" '`id`'; then
    INJECTION_BLOCKED=$((INJECTION_BLOCKED + 1))
fi

# Dollar command substitution
if ! matrix_cfg_set "watchdog_interval_sec" '$(id)'; then
    INJECTION_BLOCKED=$((INJECTION_BLOCKED + 1))
fi

# Pipe & redirection
if ! matrix_cfg_set "watchdog_interval_sec" "300 | cat /etc/passwd"; then
    INJECTION_BLOCKED=$((INJECTION_BLOCKED + 1))
fi

# Below minimum interval (< 60)
if ! matrix_cfg_set "watchdog_interval_sec" "10"; then
    INJECTION_BLOCKED=$((INJECTION_BLOCKED + 1))
fi

# Above maximum interval (> 3600)
if ! matrix_cfg_set "watchdog_interval_sec" "99999"; then
    INJECTION_BLOCKED=$((INJECTION_BLOCKED + 1))
fi

# Non-numeric interval
if ! matrix_cfg_set "watchdog_interval_sec" "invalid_number"; then
    INJECTION_BLOCKED=$((INJECTION_BLOCKED + 1))
fi

# Invalid boolean
if ! matrix_cfg_set "diagnostics_enabled" "true"; then
    INJECTION_BLOCKED=$((INJECTION_BLOCKED + 1))
fi

# Invalid key with spaces and metacharacters
if ! matrix_cfg_set "bad key; id" "1"; then
    INJECTION_BLOCKED=$((INJECTION_BLOCKED + 1))
fi

if [ "$INJECTION_BLOCKED" -eq 9 ]; then
    pass "MM-DEF-01 verified: All 9 malicious / invalid inputs were rejected (0 executed)"
else
    fail "MM-DEF-01 failure: Only $INJECTION_BLOCKED of 9 malicious inputs were rejected"
fi

# 10. Test Corrupted Active Config Auto-Rollback
echo "[*] Test 10: Auto-Rollback when active config is corrupted..."
echo "CORRUPTED_ENTRY_WITHOUT_EQUALS" >> "$MATRIX_CONF_FILE"
matrix_store_init
if matrix_cfg_validate_file "$MATRIX_CONF_FILE"; then
    pass "matrix_store_init successfully rolled back corrupted config to valid backup"
else
    fail "Rollback failed: active config remains corrupted"
fi

# 11. Test Total Corruption Fallback to Defaults
echo "[*] Test 11: Total corruption fallback when both config and backup are corrupt..."
echo "CORRUPTED_CONFIG" > "$MATRIX_CONF_FILE"
echo "CORRUPTED_BACKUP" > "$MATRIX_BAK_FILE"
matrix_store_init
if matrix_cfg_validate_file "$MATRIX_CONF_FILE" && matrix_cfg_validate_file "$MATRIX_BAK_FILE"; then
    pass "matrix_store_init generated clean defaults when both config and backup were corrupted"
else
    fail "Total corruption recovery failed"
fi

echo "=================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "[+] All Centralized Store Tests PASSED (0 errors)."
    exit 0
else
    echo "[-] Centralized Store Tests FAILED ($ERRORS error(s))."
    exit 1
fi
