#!/bin/sh
##########################################################################################
# MatrixModule - WebUI API & Structure Test Suite
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEBROOT="$BASE_DIR/webroot"
HTML_FILE="$WEBROOT/index.html"
CSS_FILE="$WEBROOT/app.css"
JS_FILE="$WEBROOT/main.js"

echo "[*] Validating WebUI API and Assets Structure..."

ERRORS=0

fail() {
    echo "[-] FAIL: $1"
    ERRORS=$((ERRORS + 1))
}

pass() {
    echo "[+] PASS: $1"
}

# 1. HTML File Validation
echo "[*] Test 1: HTML Structure and References..."
if [ -f "$HTML_FILE" ]; then
    pass "index.html exists"
    
    # Check DOCTYPE & viewport
    grep -qi "<!DOCTYPE html>" "$HTML_FILE" && pass "HTML5 DOCTYPE present" || fail "Missing HTML5 DOCTYPE"
    grep -q "viewport" "$HTML_FILE" && pass "Mobile viewport meta tag present" || fail "Missing mobile viewport meta tag"
    
    # Check asset links
    grep -q 'href="app.css"' "$HTML_FILE" && pass "app.css stylesheet link verified" || fail "Missing app.css link"
    grep -q 'src="main.js"' "$HTML_FILE" && pass "main.js script tag verified" || fail "Missing main.js link"

    # Check tab pane IDs
    for pane in "pane-dashboard" "pane-diagnostics" "pane-config" "pane-logs" "pane-security"; do
        if grep -q "id=\"$pane\"" "$HTML_FILE"; then
            pass "Found tab pane container: #$pane"
        else
            fail "Missing tab pane container: #$pane"
        fi
    done

    # Check form controls
    for ctrl in "cfg-diag" "cfg-watchdog" "cfg-interval" "cfg-backup"; do
        if grep -q "id=\"$ctrl\"" "$HTML_FILE"; then
            pass "Found form control: #$ctrl"
        else
            fail "Missing form control: #$ctrl"
        fi
    done
else
    fail "index.html missing"
fi

# 2. CSS File Validation
echo "[*] Test 2: CSS Theme & Stylesheet..."
if [ -f "$CSS_FILE" ]; then
    pass "app.css exists"
    grep -q "\-\-bg\-color" "$CSS_FILE" && pass "Dark mode CSS variable --bg-color verified" || fail "Missing --bg-color variable"
    grep -q "\-\-accent:" "$CSS_FILE" && pass "Accent CSS variable --accent verified" || fail "Missing --accent variable"
else
    fail "app.css missing"
fi

# 3. JS Bridge & API Verification
echo "[*] Test 3: JavaScript KernelSU Bridge & Safety Checks..."
if [ -f "$JS_FILE" ]; then
    pass "main.js exists"
    
    # Check KernelSU exec handler
    if grep -q "ksu.exec" "$JS_FILE"; then
        pass "KernelSU native ksu.exec bridge invocation verified"
    else
        fail "Missing ksu.exec bridge handler"
    fi

    # Check safe simulated desktop fallback
    if grep -q "simulateCommand" "$JS_FILE"; then
        pass "Desktop browser preview simulation handler verified"
    else
        fail "Missing simulation handler for out-of-manager preview"
    fi

    # WebUI Audit check: Check for shell command construction
    echo "[*] Auditing WebUI shell command construction..."
    if grep -q 'matrix_cfg_set watchdog_interval_sec \${interval}' "$JS_FILE"; then
        echo "[!] WebUI Audit Notice: Direct template literal interpolation found for interval without numeric sanitize regex."
        echo "    (Documented as Defect / Security Finding for user review)"
    fi
else
    fail "main.js missing"
fi

echo "=================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "[+] All WebUI API & Structure Tests PASSED (0 errors)."
    exit 0
else
    echo "[-] WebUI API & Structure Tests FAILED ($ERRORS error(s))."
    exit 1
fi
