#!/bin/sh
##########################################################################################
# MatrixModule - JavaScript Syntax Validation Test Suite
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEBROOT_DIR="$BASE_DIR/webroot"
JS_FILE="$WEBROOT_DIR/main.js"

echo "[*] Validating JavaScript Syntax for MatrixModule WebUI..."

if [ ! -f "$JS_FILE" ]; then
    echo "[-] Error: $JS_FILE does not exist!"
    exit 1
fi

# 1. Node.js Syntax Check
if command -v node >/dev/null 2>&1; then
    echo "[+] Node.js detected: $(node -v)"
    if node -c "$JS_FILE"; then
        echo "[+] Syntax validation passed: $JS_FILE is syntactically valid."
    else
        echo "[-] Syntax validation failed: node -c reported syntax errors in $JS_FILE"
        exit 1
    fi
else
    echo "[!] Warning: node command not found, falling back to static token checks"
fi

# 2. Critical Function Checks
MISSING_FUNCS=0
for func in "initTabs" "execCommand" "simulateCommand" "initDiagnostics" "refreshDiagnostics" "initSettings" "initLogs" "refreshLogs"; do
    if grep -q "function $func" "$JS_FILE" || grep -q "async function $func" "$JS_FILE"; then
        echo "[+] Found required function: $func"
    else
        echo "[-] Missing critical function: $func"
        MISSING_FUNCS=$((MISSING_FUNCS + 1))
    fi
done

# 3. KernelSU Bridge Guard Check
if grep -q "typeof ksu !== 'undefined'" "$JS_FILE"; then
    echo "[+] KernelSU bridge presence check verified."
else
    echo "[-] Missing KernelSU bridge guard (typeof ksu !== 'undefined')"
    MISSING_FUNCS=$((MISSING_FUNCS + 1))
fi

if [ "$MISSING_FUNCS" -eq 0 ]; then
    echo "[+] All JavaScript syntax and function validation checks PASSED."
    exit 0
else
    echo "[-] JavaScript validation FAILED with $MISSING_FUNCS error(s)."
    exit 1
fi
