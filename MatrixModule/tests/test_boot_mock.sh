#!/bin/sh
##########################################################################################
# MatrixModule - Boot Script Mock Environment Test Suite
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="/tmp/matrix_boot_mock_$$"

cleanup() {
    rm -rf "$SANDBOX" 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "[*] Setting up Boot Mock Sandbox: $SANDBOX"
mkdir -p "$SANDBOX/bin" "$SANDBOX/data/adb/modules/matrix_module" "$SANDBOX/data/adb/matrix_module"

# Copy module to sandbox
cp -r "$BASE_DIR"/* "$SANDBOX/data/adb/modules/matrix_module/" 2>/dev/null || true

MOCK_MODDIR="$SANDBOX/data/adb/modules/matrix_module"
MOCK_DATADIR="$SANDBOX/data/adb/matrix_module"

# Configure sandboxed data directories in the sandbox scripts
for f in "$MOCK_MODDIR/core/"*.sh; do
    sed -i "s|/data/adb/matrix_module|$MOCK_DATADIR|g" "$f" 2>/dev/null
done
sed -i "s|/data/adb/matrix_module|$MOCK_DATADIR|g" "$MOCK_MODDIR/post-fs-data.sh" 2>/dev/null
sed -i "s|/data/adb/matrix_module|$MOCK_DATADIR|g" "$MOCK_MODDIR/service.sh" 2>/dev/null

# Mock Android commands
PROPS_FILE="$SANDBOX/props"
touch "$PROPS_FILE"

cat << 'EOF' > "$SANDBOX/bin/getprop"
#!/bin/sh
KEY="$1"
PROPS_FILE="${SANDBOX_PROPS:-/tmp/props_default}"
if [ -f "$PROPS_FILE" ]; then
    grep "^${KEY}=" "$PROPS_FILE" 2>/dev/null | cut -d= -f2-
fi
EOF
chmod +x "$SANDBOX/bin/getprop"

cat << 'EOF' > "$SANDBOX/bin/log"
#!/bin/sh
# Mock logcat bridge
exit 0
EOF
chmod +x "$SANDBOX/bin/log"

cat << 'EOF' > "$SANDBOX/bin/sleep"
#!/bin/sh
if [ -n "$SLEEP_COUNT_FILE" ]; then
    _cnt=$(cat "$SLEEP_COUNT_FILE" 2>/dev/null || echo 0)
    _next=$((_cnt + 1))
    echo "$_next" > "$SLEEP_COUNT_FILE"
    if [ -n "$TRIGGER_BOOT_COMPLETE_AT_SLEEP" ] && [ "$_next" -eq "$TRIGGER_BOOT_COMPLETE_AT_SLEEP" ]; then
        if [ -n "$SANDBOX_PROPS" ] && [ -f "$SANDBOX_PROPS" ]; then
            grep -v "^sys.boot_completed=" "$SANDBOX_PROPS" 2>/dev/null > "$SANDBOX_PROPS.tmp" || true
            echo "sys.boot_completed=1" >> "$SANDBOX_PROPS.tmp"
            mv -f "$SANDBOX_PROPS.tmp" "$SANDBOX_PROPS"
        fi
    fi
fi
exit 0
EOF
chmod +x "$SANDBOX/bin/sleep"

cat << 'EOF' > "$SANDBOX/bin/fast_sleep"
#!/bin/sh
exit 0
EOF
chmod +x "$SANDBOX/bin/fast_sleep"

cat << 'EOF' > "$SANDBOX/bin/getenforce"
#!/bin/sh
echo "Enforcing"
EOF
chmod +x "$SANDBOX/bin/getenforce"

export PATH="$SANDBOX/bin:$PATH"
export SANDBOX_PROPS="$PROPS_FILE"
export KSU=true
export SELINUX_MODE=Enforcing

ERRORS=0

fail() {
    echo "[-] FAIL: $1"
    ERRORS=$((ERRORS + 1))
}

pass() {
    echo "[+] PASS: $1"
}

# 1. Test post-fs-data Normal Boot
echo "[*] Test 1: post-fs-data.sh normal boot execution..."
echo "ro.boot.mode=normal" > "$PROPS_FILE"
echo "ro.build.version.sdk=34" >> "$PROPS_FILE"
echo "ro.product.model=MockPhone" >> "$PROPS_FILE"

if sh "$MOCK_MODDIR/post-fs-data.sh"; then
    pass "post-fs-data.sh executed with exit code 0"
    
    # Verify state was created
    if [ -f "$MOCK_DATADIR/state" ]; then
        stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
        if [ "$stage" = "post-fs-data" ]; then
            pass "State file successfully recorded boot_stage=post-fs-data"
        else
            fail "Expected boot_stage=post-fs-data, got: '$stage'"
        fi
    else
        fail "State file $MOCK_DATADIR/state was not generated"
    fi
else
    fail "post-fs-data.sh failed with non-zero exit code"
fi

# 2. Test post-fs-data Recovery Mode Detection
echo "[*] Test 2: post-fs-data.sh in recovery mode..."
echo "ro.boot.mode=recovery" > "$PROPS_FILE"
rm -f "$MOCK_DATADIR/state"

if sh "$MOCK_MODDIR/post-fs-data.sh"; then
    pass "post-fs-data.sh safely exited 0 in recovery mode"
    if [ -f "$MOCK_DATADIR/state" ]; then
        stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
        if [ "$stage" = "aborted" ]; then
            pass "Verified: recovery mode recorded boot_stage=aborted"
        else
            fail "Expected boot_stage=aborted, got: '$stage'"
        fi
    else
        fail "State file was not generated to record aborted stage"
    fi
else
    fail "post-fs-data.sh failed in recovery mode"
fi

# 3a. Test service.sh Normal Boot Completion
echo "[*] Test 3a: service.sh boot completion (sys.boot_completed=1)..."
echo "ro.boot.mode=normal" > "$PROPS_FILE"
echo "sys.boot_completed=1" >> "$PROPS_FILE"
echo "ro.build.version.sdk=34" >> "$PROPS_FILE"
echo "ro.product.model=MockPhone" >> "$PROPS_FILE"

# Pre-populate state with start time
echo "boot_start_time=1000" > "$MOCK_DATADIR/state"
echo "boot_stage=post-fs-data" >> "$MOCK_DATADIR/state"

# Disable background watchdog during test to prevent lingering background subshell
echo "health_watchdog_enabled=0" >> "$MOCK_DATADIR/config"

if sh "$MOCK_MODDIR/service.sh"; then
    pass "service.sh completed with exit code 0"
    
    final_stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
    if [ "$final_stage" = "completed" ]; then
        pass "service.sh successfully updated boot_stage=completed on sys.boot_completed=1"
    else
        fail "Expected boot_stage=completed, got: '$final_stage'"
    fi

    # Check health.json generation
    if [ -f "$MOCK_DATADIR/health.json" ]; then
        pass "Health metrics report health.json generated"
    else
        fail "health.json was not generated by service.sh"
    fi
else
    fail "service.sh failed with non-zero exit code"
fi

# 3b. Boundary Regression Tests (Tests A, B, C, D)
# Test A: sys.boot_completed remains 0 across all 150 sleeps -> exactly 150 sleeps, boot_stage=timeout
echo "[*] Test 3b-A (Boundary Test A): sys.boot_completed remains 0 across all 150 sleeps..."
echo "ro.boot.mode=normal" > "$PROPS_FILE"
echo "sys.boot_completed=0" >> "$PROPS_FILE"
echo "ro.build.version.sdk=34" >> "$PROPS_FILE"
echo "ro.product.model=MockPhone" >> "$PROPS_FILE"

echo "boot_start_time=1000" > "$MOCK_DATADIR/state"
echo "boot_stage=post-fs-data" >> "$MOCK_DATADIR/state"
echo "boot_failure_count=0" >> "$MOCK_DATADIR/state"
rm -f "$MOCK_DATADIR/health.json"

SLEEP_COUNT_FILE="$SANDBOX/sleep_count_3ba"
rm -f "$SLEEP_COUNT_FILE"
unset TRIGGER_BOOT_COMPLETE_AT_SLEEP
export SLEEP_COUNT_FILE

if sh "$MOCK_MODDIR/service.sh"; then
    pass "Boundary Test A: service.sh completed with exit code 0"
    
    ticks_counted=$(cat "$SLEEP_COUNT_FILE" 2>/dev/null || echo 0)
    if [ "$ticks_counted" -eq 150 ]; then
        pass "Boundary Test A: verified exactly 150 timeout ticks (300s) consumed"
    else
        fail "Boundary Test A: expected exactly 150 ticks, got: '$ticks_counted'"
    fi

    timeout_stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
    timeout_reason=$(grep "^boot_timeout_reason=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2-)
    if [ "$timeout_stage" = "timeout" ]; then
        pass "Boundary Test A: persisted boot_stage=timeout"
    else
        fail "Boundary Test A: expected boot_stage=timeout, got: '$timeout_stage'"
    fi

    if [ -n "$timeout_reason" ]; then
        pass "Boundary Test A: persisted timeout reason: $timeout_reason"
    else
        fail "Boundary Test A: missing boot_timeout_reason on timeout"
    fi

    timeout_fail_count=$(grep "^boot_failure_count=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
    if [ "$timeout_fail_count" = "0" ]; then
        pass "Boundary Test A: boot_failure_count remained 0"
    else
        fail "Boundary Test A: expected boot_failure_count=0, got: '$timeout_fail_count'"
    fi

    timeout_status=$(python3 -c "import json; print(json.load(open('$MOCK_DATADIR/health.json'))['status'])" 2>/dev/null)
    if [ "$timeout_status" = "WARNING" ]; then
        pass "Boundary Test A: health.json status is WARNING (never HEALTHY)"
    else
        fail "Boundary Test A: expected status WARNING, got: '$timeout_status'"
    fi
else
    fail "Boundary Test A: service.sh failed on timeout"
fi
unset SLEEP_COUNT_FILE

# Test B: sys.boot_completed becomes 1 during the 150th sleep interval -> exactly 150 sleeps, boot_stage=completed, boot_failure_count=0, no timeout reason
echo "[*] Test 3b-B (Boundary Test B): sys.boot_completed becomes 1 during 150th sleep..."
echo "ro.boot.mode=normal" > "$PROPS_FILE"
echo "sys.boot_completed=0" >> "$PROPS_FILE"
echo "ro.build.version.sdk=34" >> "$PROPS_FILE"
echo "ro.product.model=MockPhone" >> "$PROPS_FILE"

echo "boot_start_time=1000" > "$MOCK_DATADIR/state"
echo "boot_stage=post-fs-data" >> "$MOCK_DATADIR/state"
echo "boot_failure_count=0" >> "$MOCK_DATADIR/state"
rm -f "$MOCK_DATADIR/health.json"

SLEEP_COUNT_FILE="$SANDBOX/sleep_count_3bb"
rm -f "$SLEEP_COUNT_FILE"
export SLEEP_COUNT_FILE
export TRIGGER_BOOT_COMPLETE_AT_SLEEP=150

if sh "$MOCK_MODDIR/service.sh"; then
    pass "Boundary Test B: service.sh completed with exit code 0"

    ticks_counted=$(cat "$SLEEP_COUNT_FILE" 2>/dev/null || echo 0)
    if [ "$ticks_counted" -eq 150 ]; then
        pass "Boundary Test B: verified exactly 150 sleeps executed (no 151st sleep)"
    else
        fail "Boundary Test B: expected exactly 150 sleeps, got: '$ticks_counted'"
    fi

    b_stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
    if [ "$b_stage" = "completed" ]; then
        pass "Boundary Test B: final poll caught completion -> boot_stage=completed"
    else
        fail "Boundary Test B: expected boot_stage=completed, got: '$b_stage'"
    fi

    b_fail_count=$(grep "^boot_failure_count=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
    if [ "$b_fail_count" = "0" ]; then
        pass "Boundary Test B: boot_failure_count is 0"
    else
        fail "Boundary Test B: expected boot_failure_count=0, got: '$b_fail_count'"
    fi

    b_timeout_reason=$(grep "^boot_timeout_reason=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2-)
    if [ -z "$b_timeout_reason" ]; then
        pass "Boundary Test B: boot_timeout_reason was NOT written"
    else
        fail "Boundary Test B: unexpected boot_timeout_reason present: '$b_timeout_reason'"
    fi

    b_status=$(python3 -c "import json; print(json.load(open('$MOCK_DATADIR/health.json'))['status'])" 2>/dev/null)
    if [ "$b_status" = "HEALTHY" ]; then
        pass "Boundary Test B: health.json status is HEALTHY"
    else
        fail "Boundary Test B: expected status HEALTHY, got: '$b_status'"
    fi
else
    fail "Boundary Test B: service.sh failed"
fi
unset SLEEP_COUNT_FILE
unset TRIGGER_BOOT_COMPLETE_AT_SLEEP

# Test C: sys.boot_completed becomes 1 earlier (tick 5) -> early completion, < 150 sleeps consumed
echo "[*] Test 3b-C (Boundary Test C): sys.boot_completed becomes 1 earlier (sleep 5)..."
echo "ro.boot.mode=normal" > "$PROPS_FILE"
echo "sys.boot_completed=0" >> "$PROPS_FILE"
echo "ro.build.version.sdk=34" >> "$PROPS_FILE"
echo "ro.product.model=MockPhone" >> "$PROPS_FILE"

echo "boot_start_time=1000" > "$MOCK_DATADIR/state"
echo "boot_stage=post-fs-data" >> "$MOCK_DATADIR/state"
echo "boot_failure_count=0" >> "$MOCK_DATADIR/state"
rm -f "$MOCK_DATADIR/health.json"

SLEEP_COUNT_FILE="$SANDBOX/sleep_count_3bc"
rm -f "$SLEEP_COUNT_FILE"
export SLEEP_COUNT_FILE
export TRIGGER_BOOT_COMPLETE_AT_SLEEP=5

if sh "$MOCK_MODDIR/service.sh"; then
    pass "Boundary Test C: service.sh completed with exit code 0"

    ticks_counted=$(cat "$SLEEP_COUNT_FILE" 2>/dev/null || echo 0)
    if [ "$ticks_counted" -eq 5 ]; then
        pass "Boundary Test C: verified early exit consuming < 150 sleeps (exactly 5 sleeps)"
    else
        fail "Boundary Test C: expected exactly 5 sleeps, got: '$ticks_counted'"
    fi

    c_stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
    if [ "$c_stage" = "completed" ]; then
        pass "Boundary Test C: early completion recorded boot_stage=completed"
    else
        fail "Boundary Test C: expected boot_stage=completed, got: '$c_stage'"
    fi

    c_status=$(python3 -c "import json; print(json.load(open('$MOCK_DATADIR/health.json'))['status'])" 2>/dev/null)
    if [ "$c_status" = "HEALTHY" ]; then
        pass "Boundary Test C: health.json status is HEALTHY"
    else
        fail "Boundary Test C: expected status HEALTHY, got: '$c_status'"
    fi
else
    fail "Boundary Test C: service.sh failed"
fi
unset SLEEP_COUNT_FILE
unset TRIGGER_BOOT_COMPLETE_AT_SLEEP

# Test D: sys.boot_completed remains empty/unset -> timeout recorded, health status WARNING, never HEALTHY
echo "[*] Test 3b-D (Boundary Test D): sys.boot_completed empty/unset through final poll..."
echo "ro.boot.mode=normal" > "$PROPS_FILE"
echo "ro.build.version.sdk=34" >> "$PROPS_FILE"
echo "ro.product.model=MockPhone" >> "$PROPS_FILE"

echo "boot_start_time=1000" > "$MOCK_DATADIR/state"
echo "boot_stage=post-fs-data" >> "$MOCK_DATADIR/state"
echo "boot_failure_count=0" >> "$MOCK_DATADIR/state"
rm -f "$MOCK_DATADIR/health.json"

SLEEP_COUNT_FILE="$SANDBOX/sleep_count_3bd"
rm -f "$SLEEP_COUNT_FILE"
unset TRIGGER_BOOT_COMPLETE_AT_SLEEP
export SLEEP_COUNT_FILE

if sh "$MOCK_MODDIR/service.sh"; then
    pass "Boundary Test D: service.sh completed with exit code 0"

    ticks_counted=$(cat "$SLEEP_COUNT_FILE" 2>/dev/null || echo 0)
    if [ "$ticks_counted" -eq 150 ]; then
        pass "Boundary Test D: verified exactly 150 timeout ticks consumed for unset property"
    else
        fail "Boundary Test D: expected 150 ticks, got: '$ticks_counted'"
    fi

    d_stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
    if [ "$d_stage" = "timeout" ]; then
        pass "Boundary Test D: unset property correctly persisted boot_stage=timeout"
    else
        fail "Boundary Test D: expected boot_stage=timeout, got: '$d_stage'"
    fi

    d_status=$(python3 -c "import json; print(json.load(open('$MOCK_DATADIR/health.json'))['status'])" 2>/dev/null)
    if [ "$d_status" = "WARNING" ]; then
        pass "Boundary Test D: health.json status is WARNING (never HEALTHY)"
    else
        fail "Boundary Test D: expected status WARNING, got: '$d_status'"
    fi
else
    fail "Boundary Test D: service.sh failed on timeout"
fi
unset SLEEP_COUNT_FILE

# 3c. Test Lifecycle Failure Recording & Deduplication
echo "[*] Test 3c: Lifecycle failure recording and deduplication within same stage..."
sh -c '
    MATRIX_HEALTH_FILE="'"$MOCK_DATADIR"'/health_fail.json"
    MATRIX_DATA_DIR="'"$MOCK_DATADIR"'"
    MATRIX_STATE_FILE="'"$MOCK_DATADIR"'/state"
    . "'"$MOCK_MODDIR"'/core/matrix_env.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_store.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_health.sh"
    
    matrix_state_set "boot_stage" "post-fs-data"
    matrix_state_set "boot_failure_count" "0"
    matrix_health_mark_boot_failed "simulated component crash"
'
fail_count=$(grep "^boot_failure_count=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
fail_stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
fail_reason=$(grep "^boot_failure_reason=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2-)

if [ "$fail_count" = "1" ] && [ "$fail_stage" = "failed" ] && [ "$fail_reason" = "simulated component crash" ]; then
    pass "matrix_health_mark_boot_failed correctly recorded failure count=1 and reason"
else
    fail "matrix_health_mark_boot_failed failed: count=$fail_count, stage=$fail_stage, reason=$fail_reason"
fi

# Same-stage deduplication check: second call in same failed stage must NOT double increment
sh -c '
    MATRIX_HEALTH_FILE="'"$MOCK_DATADIR"'/health_fail.json"
    MATRIX_DATA_DIR="'"$MOCK_DATADIR"'"
    MATRIX_STATE_FILE="'"$MOCK_DATADIR"'/state"
    . "'"$MOCK_MODDIR"'/core/matrix_env.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_store.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_health.sh"
    matrix_health_mark_boot_failed "second simulated crash in same failure event"
'
fail_count_dedup=$(grep "^boot_failure_count=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
if [ "$fail_count_dedup" = "1" ]; then
    pass "Deduplication verified: failure count remained 1 on repeated failure in same failed stage"
else
    fail "Deduplication failed: Expected boot_failure_count=1, got: '$fail_count_dedup'"
fi

# 3d. Test Multi-stage Failure Increment across boot cycles
echo "[*] Test 3d: Failure increment on new boot lifecycle attempt..."
sh -c '
    MATRIX_HEALTH_FILE="'"$MOCK_DATADIR"'/health_fail.json"
    MATRIX_DATA_DIR="'"$MOCK_DATADIR"'"
    MATRIX_STATE_FILE="'"$MOCK_DATADIR"'/state"
    . "'"$MOCK_MODDIR"'/core/matrix_env.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_store.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_health.sh"
    # New boot stage initiated
    matrix_state_set "boot_stage" "post-fs-data"
    matrix_health_mark_boot_failed "failure in subsequent boot cycle"
'
fail_count2=$(grep "^boot_failure_count=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
if [ "$fail_count2" = "2" ]; then
    pass "matrix_health_mark_boot_failed correctly incremented failure count to 2 across boot cycles"
else
    fail "Expected boot_failure_count=2, got: '$fail_count2'"
fi

# 3e. Test Production Lifecycle Script Fatal Exit Handlers
echo "[*] Test 3e: Production lifecycle script execution on fatal storage / recovery failure..."
out_pfs=$(MATRIX_DATA_DIR="/dev/null/matrix_module" sh "$MOCK_MODDIR/post-fs-data.sh" 2>&1)
code_pfs=$?
if [ "$code_pfs" -eq 1 ]; then
    pass "post-fs-data.sh exited with code 1 upon fatal storage initialization failure"
else
    fail "post-fs-data.sh failed to exit 1 on storage failure: code=$code_pfs, out=$out_pfs"
fi

out_svc=$(MATRIX_DATA_DIR="/dev/null/matrix_module" sh "$MOCK_MODDIR/service.sh" 2>&1)
code_svc=$?
if [ "$code_svc" -eq 1 ]; then
    pass "service.sh exited with code 1 upon fatal storage initialization failure"
else
    fail "service.sh failed to exit 1 on storage failure: code=$code_svc, out=$out_svc"
fi

# 3e-loginit. Test Production Failure Handler Integration (Failing Log Init with Writable State)
echo "[*] Test 3e-loginit: Production failure handler integration on log init failure..."
echo "boot_start_time=1000" > "$MOCK_DATADIR/state"
echo "boot_stage=post-fs-data" >> "$MOCK_DATADIR/state"
echo "boot_failure_count=0" >> "$MOCK_DATADIR/state"
rm -f "$MOCK_DATADIR/health.json"

out_log_svc=$(MATRIX_DATA_DIR="$MOCK_DATADIR" MATRIX_LOG_DIR="/dev/null/matrix_logs" sh "$MOCK_MODDIR/service.sh" 2>&1)
code_log_svc=$?
if [ "$code_log_svc" -eq 1 ]; then
    pass "service.sh exited with code 1 upon fatal log subsystem initialization failure"
else
    fail "service.sh failed to exit 1 on log failure: code=$code_log_svc, out=$out_log_svc"
fi

log_fail_stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
if [ "$log_fail_stage" = "failed" ]; then
    pass "Production failure handler persisted boot_stage=failed"
else
    fail "Expected boot_stage=failed, got: '$log_fail_stage'"
fi

log_fail_count=$(grep "^boot_failure_count=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
if [ "$log_fail_count" = "1" ]; then
    pass "Production failure handler incremented boot_failure_count=1"
else
    fail "Expected boot_failure_count=1, got: '$log_fail_count'"
fi

log_fail_reason=$(grep "^boot_failure_reason=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2-)
if [ "$log_fail_reason" = "log subsystem initialization failed during late boot stage" ]; then
    pass "Production failure handler persisted exact failure reason: '$log_fail_reason'"
else
    fail "Expected exact failure reason, got: '$log_fail_reason'"
fi

if [ -f "$MOCK_DATADIR/health.json" ]; then
    log_fail_status=$(python3 -c "import json; print(json.load(open('$MOCK_DATADIR/health.json'))['status'])" 2>/dev/null)
    if [ "$log_fail_status" = "ERROR" ]; then
        pass "Production failure handler generated health.json with status ERROR"
    else
        fail "Expected health.json status ERROR on failure, got: '$log_fail_status'"
    fi
else
    fail "health.json was not generated on production failure"
fi

# 3f. Test Self-Healing / Failure Reset on Successful Boot Completion
echo "[*] Test 3f: Self-healing failure count reset on successful boot completion..."
echo "ro.boot.mode=normal" > "$PROPS_FILE"
echo "sys.boot_completed=1" >> "$PROPS_FILE"
echo "boot_stage=post-fs-data" > "$MOCK_DATADIR/state"
echo "boot_failure_count=3" >> "$MOCK_DATADIR/state"

if sh "$MOCK_MODDIR/service.sh"; then
    pass "service.sh successfully recovered and executed on boot completion"
    healed_stage=$(grep "^boot_stage=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
    healed_count=$(grep "^boot_failure_count=" "$MOCK_DATADIR/state" 2>/dev/null | cut -d= -f2)
    if [ "$healed_stage" = "completed" ] && [ "$healed_count" = "0" ]; then
        pass "Self-healing verified: boot_stage=completed and boot_failure_count reset to 0"
    else
        fail "Self-healing failed: stage=$healed_stage, count=$healed_count"
    fi
else
    fail "service.sh recovery execution failed"
fi

# 4. Test MM-DEF-06: Unusual Property Values & Robust JSON Escaping
echo "[*] Test 4: MM-DEF-06 - Testing health.json generation with unusual properties..."
printf "%s\n" 'ro.boot.mode=normal' > "$PROPS_FILE"
printf "%s\n" 'sys.boot_completed=1' >> "$PROPS_FILE"
printf "%s\n" 'ro.build.version.sdk=34' >> "$PROPS_FILE"
printf "%s\n" 'ro.product.model=OEM "ProPhone" \Model-X\	Tabbed' >> "$PROPS_FILE"

# Re-run health report generation
sh -c '
    MATRIX_HEALTH_FILE="'"$MOCK_DATADIR"'/health.json"
    MATRIX_DATA_DIR="'"$MOCK_DATADIR"'"
    MATRIX_STATE_FILE="'"$MOCK_DATADIR"'/state"
    . "'"$MOCK_MODDIR"'/core/matrix_env.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_store.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_health.sh"
    matrix_health_generate_report
'
if [ -f "$MOCK_DATADIR/health.json" ]; then
    if python3 -m json.tool < "$MOCK_DATADIR/health.json" >/dev/null 2>&1; then
        pass "MM-DEF-06 verified: health.json with quotes, tabs, and backslashes parsed successfully"
    else
        fail "MM-DEF-06 failure: health.json emitted malformed JSON"
    fi
else
    fail "health.json missing after report generation"
fi

# 5. Test Honest Health Status Transitions (HEALTHY, WARNING, ERROR, UNKNOWN)
echo "[*] Test 5: Testing Honest Health Status State Machine Transitions..."
echo "boot_stage=completed" > "$MOCK_DATADIR/state"
echo "boot_failure_count=0" >> "$MOCK_DATADIR/state"

HEALTH_TEST_ENV='
    MATRIX_HEALTH_FILE="'"$MOCK_DATADIR"'/health_test.json"
    MATRIX_DATA_DIR="'"$MOCK_DATADIR"'"
    MATRIX_STATE_FILE="'"$MOCK_DATADIR"'/state"
    . "'"$MOCK_MODDIR"'/core/matrix_env.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_store.sh"
    . "'"$MOCK_MODDIR"'/core/matrix_health.sh"
'

# 5a. Healthy baseline
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "completed" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "HEALTHY" ] || { echo "Expected HEALTHY, got $st"; exit 1; }
' && pass "Health state transition 5a: Healthy baseline -> HEALTHY" || fail "Health transition 5a failed"

# 5b. Warning on active conflicts
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "completed" "tricky_store" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "WARNING" ] || { echo "Expected WARNING, got $st"; exit 1; }
' && pass "Health state transition 5b: Active conflicts -> WARNING" || fail "Health transition 5b failed"

# 5c. Warning on KernelSU version mismatch
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "completed" "" "0" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "WARNING" ] || { echo "Expected WARNING, got $st"; exit 1; }
' && pass "Health state transition 5c: KernelSU driver/manager mismatch -> WARNING" || fail "Health transition 5c failed"

# 5d. Warning on incomplete boot stage (post-fs-data)
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "post-fs-data" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "WARNING" ] || { echo "Expected WARNING, got $st"; exit 1; }
' && pass "Health state transition 5d: Incomplete boot stage -> WARNING" || fail "Health transition 5d failed"

# 5e. Warning on boot completion timeout (timeout)
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "timeout" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "WARNING" ] || { echo "Expected WARNING, got $st"; exit 1; }
' && pass "Health state transition 5e: Boot completion timeout -> WARNING" || fail "Health transition 5e failed"

# 5f. Error on recovery mode
sh -c "$HEALTH_TEST_ENV"'
    matrix_health_check_recovery_mode() { return 0; }
    st=$(matrix_health_determine_status "KernelSU" "completed" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "ERROR" ] || { echo "Expected ERROR, got $st"; exit 1; }
' && pass "Health state transition 5f: Recovery mode -> ERROR" || fail "Health transition 5f failed"

# 5g. Error on aborted or failed boot stage
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "failed" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "ERROR" ] || { echo "Expected ERROR, got $st"; exit 1; }
' && pass "Health state transition 5g: Failed boot stage -> ERROR" || fail "Health transition 5g failed"

# 5h. Error on aborted boot stage
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "aborted" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "ERROR" ] || { echo "Expected ERROR, got $st"; exit 1; }
' && pass "Health state transition 5h: Aborted boot stage -> ERROR" || fail "Health transition 5h failed"

# 5i. Error on boot_failure_count > 0
sh -c "$HEALTH_TEST_ENV"'
    matrix_state_set "boot_failure_count" "1"
    st=$(matrix_health_determine_status "KernelSU" "completed" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "ERROR" ] || { echo "Expected ERROR, got $st"; exit 1; }
' && pass "Health state transition 5i: Failure count > 0 -> ERROR" || fail "Health transition 5i failed"

# 5j. Error on unsupported architecture
sh -c "$HEALTH_TEST_ENV"'
    matrix_state_set "boot_failure_count" "0"
    st=$(matrix_health_determine_status "KernelSU" "completed" "" "1" "Enforcing" "unsupported" "34")
    [ "$st" = "ERROR" ] || { echo "Expected ERROR, got $st"; exit 1; }
' && pass "Health state transition 5j: Unsupported architecture -> ERROR" || fail "Health transition 5j failed"

# 5k. Unknown on uninitialized / missing state file
sh -c "$HEALTH_TEST_ENV"'
    rm -f "$MATRIX_STATE_FILE"
    st=$(matrix_health_determine_status "KernelSU")
    [ "$st" = "UNKNOWN" ] || { echo "Expected UNKNOWN, got $st"; exit 1; }
' && pass "Health state transition 5k: Missing/uninitialized state -> UNKNOWN" || fail "Health transition 5k failed"

# 5l. Unknown on boot_stage=unknown
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "unknown" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "UNKNOWN" ] || { echo "Expected UNKNOWN, got $st"; exit 1; }
' && pass "Health state transition 5l: boot_stage=unknown -> UNKNOWN" || fail "Health transition 5l failed"

# 5m. Unknown on empty boot_stage
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "UNKNOWN" ] || { echo "Expected UNKNOWN, got $st"; exit 1; }
' && pass "Health state transition 5m: Empty boot_stage -> UNKNOWN" || fail "Health transition 5m failed"

# 5n. Unknown on unavailable root probe
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "Unknown" "completed" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "UNKNOWN" ] || { echo "Expected UNKNOWN, got $st"; exit 1; }
' && pass "Health state transition 5n: Unknown root probe -> UNKNOWN" || fail "Health transition 5n failed"

# 5o. Unknown on unavailable SELinux probe
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "completed" "" "1" "Unknown" "arm64-v8a" "34")
    [ "$st" = "UNKNOWN" ] || { echo "Expected UNKNOWN, got $st"; exit 1; }
' && pass "Health state transition 5o: Unknown SELinux probe -> UNKNOWN" || fail "Health transition 5o failed"

# 5p. Unknown on missing SDK level
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "completed" "" "1" "Enforcing" "arm64-v8a" "0")
    [ "$st" = "UNKNOWN" ] || { echo "Expected UNKNOWN, got $st"; exit 1; }
' && pass "Health state transition 5p: Zero/missing SDK probe -> UNKNOWN" || fail "Health transition 5p failed"

# 5q. Precedence: Recovery Mode (ERROR) > Unknown Root (UNKNOWN)
sh -c "$HEALTH_TEST_ENV"'
    matrix_health_check_recovery_mode() { return 0; }
    st=$(matrix_health_determine_status "Unknown" "completed" "" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "ERROR" ] || { echo "Expected ERROR, got $st"; exit 1; }
' && pass "Precedence 5q: Recovery Mode (ERROR) > Unknown Root (UNKNOWN) -> ERROR" || fail "Precedence 5q failed"

# 5r. Precedence: Failed Boot (ERROR) > Conflicts (WARNING)
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "failed" "tricky_store" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "ERROR" ] || { echo "Expected ERROR, got $st"; exit 1; }
' && pass "Precedence 5r: Failed Boot (ERROR) > Conflicts (WARNING) -> ERROR" || fail "Precedence 5r failed"

# 5s. Precedence: Unknown boot_stage (UNKNOWN) > Conflicts (WARNING)
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "unknown" "tricky_store" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "UNKNOWN" ] || { echo "Expected UNKNOWN, got $st"; exit 1; }
' && pass "Precedence 5s: Unknown boot_stage (UNKNOWN) > Conflicts (WARNING) -> UNKNOWN" || fail "Precedence 5s failed"

# 5t. Precedence: Unknown root (UNKNOWN) > Conflicts (WARNING)
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "Unknown" "completed" "tricky_store" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "UNKNOWN" ] || { echo "Expected UNKNOWN, got $st"; exit 1; }
' && pass "Precedence 5t: Unknown root (UNKNOWN) > Conflicts (WARNING) -> UNKNOWN" || fail "Precedence 5t failed"

# 5u. Warning combination: Timeout + Conflicts
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "timeout" "tricky_store" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "WARNING" ] || { echo "Expected WARNING, got $st"; exit 1; }
' && pass "Precedence 5u: Timeout + Conflicts -> WARNING" || fail "Precedence 5u failed"

# 5v. Warning combination: Post-fs-data + Conflicts
sh -c "$HEALTH_TEST_ENV"'
    st=$(matrix_health_determine_status "KernelSU" "post-fs-data" "tricky_store" "1" "Enforcing" "arm64-v8a" "34")
    [ "$st" = "WARNING" ] || { echo "Expected WARNING, got $st"; exit 1; }
' && pass "Precedence 5v: Post-fs-data + Conflicts -> WARNING" || fail "Precedence 5v failed"

# 5w. JSON report status field verification
sh -c "$HEALTH_TEST_ENV"'
    echo "boot_stage=completed" > "$MATRIX_STATE_FILE"
    echo "boot_failure_count=0" >> "$MATRIX_STATE_FILE"
    matrix_detect_root() { echo "KernelSU"; }
    matrix_get_arch() { echo "arm64-v8a"; }
    matrix_get_sdk() { echo "34"; }
    matrix_get_selinux() { echo "Enforcing"; }
    matrix_get_ksu_versions() { echo "11950 10940 0"; }
    matrix_health_generate_report
'
_rep_status=$(python3 -c "import json; print(json.load(open('$MOCK_DATADIR/health_test.json'))['status'])" 2>/dev/null)
if [ "$_rep_status" = "WARNING" ]; then
    pass "Health JSON report accurately reflects dynamic status: WARNING"
else
    fail "Health JSON report status mismatch: expected WARNING, got '$_rep_status'"
fi

echo "=================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "[+] All Boot Mock Tests PASSED (0 errors)."
    exit 0
else
    echo "[-] Boot Mock Tests FAILED ($ERRORS error(s))."
    exit 1
fi
