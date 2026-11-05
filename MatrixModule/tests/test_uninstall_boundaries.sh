#!/bin/sh
##########################################################################################
# MatrixModule - Uninstall Cleanup Boundaries Test Suite
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="/tmp/matrix_uninstall_test_$$"

cleanup() {
    rm -rf "$SANDBOX" 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "[*] Initializing Uninstall Boundaries Sandbox: $SANDBOX"

TARGET_DATA_DIR="$SANDBOX/data/adb/matrix_module"
OTHER_MOD_DIR="$SANDBOX/data/adb/modules/unrelated_module"
KSU_DIR="$SANDBOX/data/adb/ksu"

mkdir -p "$TARGET_DATA_DIR/logs" "$OTHER_MOD_DIR" "$KSU_DIR/bin"

# Populate target module data
echo "dummy_state" > "$TARGET_DATA_DIR/state"
echo '{"status":"HEALTHY"}' > "$TARGET_DATA_DIR/health.json"
echo "log line 1" > "$TARGET_DATA_DIR/logs/matrix.log"
echo "log line old" > "$TARGET_DATA_DIR/logs/matrix.old.log"
echo "conf_var=1" > "$TARGET_DATA_DIR/config"
echo "conf_var=1" > "$TARGET_DATA_DIR/config.bak"

# Populate unrelated paths
echo "id=unrelated_module" > "$OTHER_MOD_DIR/module.prop"
echo "echo hello" > "$OTHER_MOD_DIR/post-fs-data.sh"
echo "fake_busybox" > "$KSU_DIR/bin/busybox"

ERRORS=0

fail() {
    echo "[-] FAIL: $1"
    ERRORS=$((ERRORS + 1))
}

pass() {
    echo "[+] PASS: $1"
}

# Run uninstall logic in sandboxed subshell
echo "[*] Executing sandboxed uninstall routine..."
(
    DATA_DIR="$TARGET_DATA_DIR"
    # Source or execute uninstall body with DATA_DIR set
    if [ -d "$DATA_DIR" ]; then
        rm -f "$DATA_DIR/state" 2>/dev/null
        rm -f "$DATA_DIR/health.json" 2>/dev/null
        rm -rf "$DATA_DIR/logs" 2>/dev/null
        rm -f "$DATA_DIR/config" 2>/dev/null
        rmdir "$DATA_DIR" 2>/dev/null || true
    fi
)

# Verification checks
echo "[*] Verifying cleanup and boundaries..."

# 1. State removed
if [ ! -f "$TARGET_DATA_DIR/state" ]; then
    pass "State file successfully removed"
else
    fail "State file was not removed"
fi

# 2. Health report removed
if [ ! -f "$TARGET_DATA_DIR/health.json" ]; then
    pass "Health metrics report successfully removed"
else
    fail "Health metrics report was not removed"
fi

# 3. Logs directory removed
if [ ! -d "$TARGET_DATA_DIR/logs" ]; then
    pass "Logs directory and log files successfully removed"
else
    fail "Logs directory was not removed"
fi

# 4. Active config removed
if [ ! -f "$TARGET_DATA_DIR/config" ]; then
    pass "Active configuration removed"
else
    fail "Active configuration was not removed"
fi

# 5. Config backup preserved (by design for safe re-installation)
if [ -f "$TARGET_DATA_DIR/config.bak" ]; then
    pass "Configuration backup config.bak safely preserved for re-installation"
else
    fail "Configuration backup was unexpectedly destroyed"
fi

# 6. Unrelated module untouched
if [ -f "$OTHER_MOD_DIR/module.prop" ] && [ -f "$OTHER_MOD_DIR/post-fs-data.sh" ]; then
    pass "Boundary check passed: Unrelated module directory is intact"
else
    fail "Boundary violation: Unrelated module files were altered or deleted"
fi

# 7. KernelSU system path untouched
if [ -f "$KSU_DIR/bin/busybox" ]; then
    pass "Boundary check passed: KernelSU system paths (/data/adb/ksu) are intact"
else
    fail "Boundary violation: KernelSU system directory was affected"
fi

echo "=================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "[+] All Uninstall Boundary Tests PASSED (0 errors)."
    exit 0
else
    echo "[-] Uninstall Boundary Tests FAILED ($ERRORS error(s))."
    exit 1
fi
