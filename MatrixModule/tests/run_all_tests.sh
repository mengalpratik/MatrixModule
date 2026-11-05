#!/bin/sh
##########################################################################################
# MatrixModule - Master Test Runner
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTS_DIR="$BASE_DIR/tests"

echo "=================================================="
echo "          MatrixModule Static Test Suite          "
echo "=================================================="
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Testing Directory: $BASE_DIR"
echo "=================================================="

TOTAL=0
PASSED=0
FAILED=0

run_test() {
    name="$1"
    script="$2"
    TOTAL=$((TOTAL + 1))
    echo ""
    echo ">>> Running Test Suite: $name"
    echo "--------------------------------------------------"
    if sh "$script"; then
        echo ">>> Result: PASS"
        PASSED=$((PASSED + 1))
    else
        echo ">>> Result: FAIL"
        FAILED=$((FAILED + 1))
    fi
}

run_test "Shell Syntax Validation" "$TESTS_DIR/test_syntax.sh"
run_test "Structure & Metadata Validation" "$TESTS_DIR/test_structure.sh"
run_test "File Permissions Validation" "$TESTS_DIR/test_permissions.sh"
run_test "Packaging & ZIP Integrity Validation" "$TESTS_DIR/test_packaging.sh"
run_test "JavaScript Syntax Validation" "$TESTS_DIR/test_js_syntax.sh"
run_test "Centralized Configuration Store" "$TESTS_DIR/test_config_store.sh"
run_test "Boot Lifecycle Mock & Safety" "$TESTS_DIR/test_boot_mock.sh"
run_test "Uninstall Boundaries & Isolation" "$TESTS_DIR/test_uninstall_boundaries.sh"
run_test "Installer Failure Scenarios" "$TESTS_DIR/test_installer_failures.sh"
run_test "WebUI API & Structure Validation" "$TESTS_DIR/test_webui_api.sh"
run_test "Action Interface & Dynamic Paths" "$TESTS_DIR/test_action_dynamic.sh"
run_test "JSON Escaping Round-Trip Oracle" "$TESTS_DIR/test_json_roundtrip.sh"

echo ""
echo "=================================================="
echo "                  Test Summary                    "
echo "=================================================="
echo " Total Suites: $TOTAL"
echo " Passed:       $PASSED"
echo " Failed:       $FAILED"
echo " Status:       $([ "$FAILED" -eq 0 ] && echo "ALL TESTS PASSED" || echo "TEST FAILURES DETECTED")"
echo "=================================================="

exit "$FAILED"
