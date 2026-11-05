#!/bin/sh
##########################################################################################
# MatrixModule - WebUI API & Structure Test Suite (Hardened & Expanded)
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEBROOT="$BASE_DIR/webroot"
HTML_FILE="$WEBROOT/index.html"
CSS_FILE="$WEBROOT/app.css"
JS_FILE="$WEBROOT/main.js"

echo "[*] Validating WebUI API, Structure, and Dynamic Bridge..."

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

    # Check status badge element
    if grep -q 'id="module-status-badge"' "$HTML_FILE"; then
        pass "Found module status badge: #module-status-badge"
    else
        fail "Missing module status badge: #module-status-badge"
    fi
else
    fail "index.html missing"
fi

# 2. CSS File Validation
echo "[*] Test 2: CSS Theme & Stylesheet..."
if [ -f "$CSS_FILE" ]; then
    pass "app.css exists"
    grep -q "\-\-bg\-color" "$CSS_FILE" && pass "Dark mode CSS variable --bg-color verified" || fail "Missing --bg-color variable"
    grep -q "\-\-accent:" "$CSS_FILE" && pass "Accent CSS variable --accent verified" || fail "Missing --accent variable"
    grep -q "badge-healthy" "$CSS_FILE" && pass "Badge healthy state CSS class verified" || fail "Missing .badge-healthy class"
    grep -q "badge-warning" "$CSS_FILE" && pass "Badge warning state CSS class verified" || fail "Missing .badge-warning class"
    grep -q "badge-error" "$CSS_FILE" && pass "Badge error state CSS class verified" || fail "Missing .badge-error class"
    grep -q "badge-unknown" "$CSS_FILE" && pass "Badge unknown state CSS class verified" || fail "Missing .badge-unknown class"
else
    fail "app.css missing"
fi

# 3. Static Bridge & Injection Auditing
echo "[*] Test 3: Static JavaScript Security & Parameter Validation Checks..."
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

    # Check updateStatusBadge function
    if grep -q "updateStatusBadge" "$JS_FILE"; then
        pass "Honest status badge updater updateStatusBadge present in main.js"
    else
        fail "Missing updateStatusBadge function in main.js"
    fi

    # Check stale version cleanup in preview logs
    if grep -q "MatrixModule v1.0.2" "$JS_FILE"; then
        fail "Found stale MatrixModule v1.0.2 text in main.js preview logs"
    else
        pass "Stale MatrixModule v1.0.2 text eliminated from main.js"
    fi

    # Check MM-DEF-01 fix: direct unvalidated interpolation must NOT exist
    if grep -q 'matrix_cfg_set watchdog_interval_sec \${interval}' "$JS_FILE"; then
        fail "MM-DEF-01 violation: Found unvalidated direct \${interval} interpolation"
    else
        pass "MM-DEF-01 verified: Raw \${interval} interpolation successfully eliminated"
    fi

    # Check numeric regex enforcement
    if grep -F '/^\d+$/' "$JS_FILE" >/dev/null; then
        pass "MM-DEF-01 verified: Strict numeric integer regex validation present in main.js"
    else
        fail "Missing numeric regex validation in main.js"
    fi
else
    fail "main.js missing"
fi

# 4. Dynamic Bridge Testing in Node.js VM (MM-DEF-03 Verification)
echo "[*] Test 4: Dynamic Bridge Execution in Node.js VM..."
if command -v node >/dev/null 2>&1; then
    NODE_OUT=$(node -e '
        const fs = require("fs");
        const vm = require("vm");
        const code = fs.readFileSync("'"$JS_FILE"'", "utf8");

        async function runBridgeTests() {
            // Test 4.1: Asynchronous Promise resolution with structured object
            const ctx1 = vm.createContext({
                document: { addEventListener: () => {}, querySelectorAll: () => [], getElementById: () => null },
                ksu: {
                    exec: (cmd) => Promise.resolve({ errno: 0, stdout: "ASYNC_SUCCESS", stderr: "" })
                }
            });
            vm.runInContext(code, ctx1);
            const res1 = await ctx1.execCommand("test_async");
            if (res1.code !== 0 || res1.stdout !== "ASYNC_SUCCESS") {
                throw new Error("Failed async Promise resolution: " + JSON.stringify(res1));
            }

            // Test 4.2: Asynchronous Promise rejection
            const ctx2 = vm.createContext({
                document: { addEventListener: () => {}, querySelectorAll: () => [], getElementById: () => null },
                ksu: {
                    exec: (cmd) => Promise.reject(new Error("Bridge permission denied"))
                }
            });
            vm.runInContext(code, ctx2);
            const res2 = await ctx2.execCommand("test_rejected");
            if (res2.code !== 1 || !res2.stderr.includes("Bridge permission denied")) {
                throw new Error("Failed rejected Promise handling: " + JSON.stringify(res2));
            }

            // Test 4.3: Legacy synchronous string return
            const ctx3 = vm.createContext({
                document: { addEventListener: () => {}, querySelectorAll: () => [], getElementById: () => null },
                ksu: {
                    exec: (cmd) => "SYNC_SUCCESS"
                }
            });
            vm.runInContext(code, ctx3);
            const res3 = await ctx3.execCommand("test_sync");
            if (res3.code !== 0 || res3.stdout !== "SYNC_SUCCESS") {
                throw new Error("Failed synchronous string return: " + JSON.stringify(res3));
            }

            // Test 4.4: Desktop simulation fallback (no ksu object)
            const ctx4 = vm.createContext({
                document: { addEventListener: () => {}, querySelectorAll: () => [], getElementById: () => null }
            });
            vm.runInContext(code, ctx4);
            const res4 = await ctx4.execCommand("matrix_env.sh");
            if (res4.code !== 0 || !res4.stdout.includes("KernelSU (Simulated)")) {
                throw new Error("Failed simulation fallback: " + JSON.stringify(res4));
            }

            // Test 4.5: KernelSU Manager asynchronous callback pattern
            const ctx5 = vm.createContext({
                document: { addEventListener: () => {}, querySelectorAll: () => [], getElementById: () => null },
                ksu: {
                    exec: (cmd, opts, cbName) => {
                        // Simulates Java WebView asynchronous callback
                        setTimeout(() => {
                            if (typeof ctx5[cbName] === "function") {
                                ctx5[cbName](0, "CALLBACK_SUCCESS", "");
                            }
                        }, 5);
                    }
                }
            });
            vm.runInContext(code, ctx5);
            const res5 = await ctx5.execCommand("test_callback");
            if (res5.code !== 0 || res5.stdout !== "CALLBACK_SUCCESS") {
                throw new Error("Failed async callback handling: " + JSON.stringify(res5));
            }

            // Helper for mock DOM elements supporting classList and className
            function createMockEl(id) {
                const classes = new Set();
                return {
                    id,
                    textContent: "INITIAL",
                    get className() { return Array.from(classes).join(" "); },
                    set className(val) {
                        classes.clear();
                        if (val) val.split(/\s+/).filter(Boolean).forEach(c => classes.add(c));
                    },
                    classList: {
                        add(c) { classes.add(c); },
                        remove(c) { classes.delete(c); },
                        contains(c) { return classes.has(c); }
                    }
                };
            }

            // Test 4.6: Device diagnostics integration with mocked healthy device data
            const domElements6 = {};
            const getOrCreateEl6 = (id) => {
                if (!domElements6[id]) domElements6[id] = createMockEl(id);
                return domElements6[id];
            };
            const mockDeviceJson = JSON.stringify({
                timestamp: "2026-11-05 21:00:00",
                root_manager: "KernelSU (Official)",
                architecture: "arm64-v8a",
                sdk_level: 34,
                device_model: "Pixel 8 Pro (Mock)",
                zygisk_host: "Zygisk Next v1.1.0",
                selinux_mode: "Enforcing",
                boot_stage: "completed",
                boot_duration_sec: 14,
                active_conflicts: "None",
                ksu_manager_code: 11950,
                ksu_kernel_code: 11950,
                ksu_version_match: 1,
                status: "HEALTHY"
            });
            const ctx6 = vm.createContext({
                document: {
                    addEventListener: () => {},
                    querySelectorAll: () => [],
                    getElementById: (id) => getOrCreateEl6(id)
                },
                ksu: {
                    exec: (cmd) => Promise.resolve({ errno: 0, stdout: mockDeviceJson, stderr: "" })
                }
            });
            vm.runInContext(code, ctx6);
            await ctx6.refreshDiagnostics();

            if (domElements6["val-root"].textContent !== "KernelSU (Official)") {
                throw new Error("Failed device diagnostics root value: " + domElements6["val-root"].textContent);
            }
            if (domElements6["diag-model"].textContent !== "Pixel 8 Pro (Mock)") {
                throw new Error("Failed device diagnostics model: " + domElements6["diag-model"].textContent);
            }
            if (!domElements6["diag-ksu-kernel"].textContent.includes("Synchronized (v11950)")) {
                throw new Error("Failed verified KSU synchronized kernel text: " + domElements6["diag-ksu-kernel"].textContent);
            }
            if (!domElements6["diag-ksu-app"].textContent.includes("Synchronized (v11950)")) {
                throw new Error("Failed verified KSU synchronized app text: " + domElements6["diag-ksu-app"].textContent);
            }
            if (domElements6["module-status-badge"].textContent !== "HEALTHY" || !domElements6["module-status-badge"].classList.contains("badge-healthy")) {
                throw new Error("Failed status badge healthy transition: " + domElements6["module-status-badge"].textContent);
            }

            // Test 4.7: Diagnostics command failure in Manager (must show unavailable/error, NEVER fake data)
            const domElements7 = {};
            const ctx7 = vm.createContext({
                document: {
                    addEventListener: () => {},
                    querySelectorAll: () => [],
                    getElementById: (id) => {
                        if (!domElements7[id]) domElements7[id] = createMockEl(id);
                        return domElements7[id];
                    }
                },
                ksu: {
                    exec: (cmd) => Promise.resolve({ errno: 1, stdout: "", stderr: "Permission denied" })
                }
            });
            vm.runInContext(code, ctx7);
            await ctx7.refreshDiagnostics();

            if (domElements7["val-root"].textContent !== "Unavailable") {
                throw new Error("Expected 'Unavailable' on failure, got: " + domElements7["val-root"].textContent);
            }
            if (domElements7["diag-root"].textContent !== "Unavailable") {
                throw new Error("Expected 'Unavailable' for diag-root on failure, got: " + domElements7["diag-root"].textContent);
            }
            if (domElements7["diag-ksu-kernel"].textContent !== "Unverified") {
                throw new Error("Expected 'Unverified' for diag-ksu-kernel on failure, got: " + domElements7["diag-ksu-kernel"].textContent);
            }
            if (domElements7["module-status-badge"].textContent !== "ERROR" || !domElements7["module-status-badge"].classList.contains("badge-error")) {
                throw new Error("Expected ERROR badge on failure, got: " + domElements7["module-status-badge"].textContent);
            }

            // Test 4.8: Malformed JSON diagnostics payload handling
            const domElements8 = {};
            const ctx8 = vm.createContext({
                document: {
                    addEventListener: () => {},
                    querySelectorAll: () => [],
                    getElementById: (id) => {
                        if (!domElements8[id]) domElements8[id] = createMockEl(id);
                        return domElements8[id];
                    }
                },
                ksu: {
                    exec: (cmd) => Promise.resolve({ errno: 0, stdout: "MALFORMED_NON_JSON", stderr: "" })
                }
            });
            vm.runInContext(code, ctx8);
            await ctx8.refreshDiagnostics();

            if (!domElements8["diag-model"].textContent.includes("Failed to parse diagnostics JSON")) {
                throw new Error("Expected JSON parse failure message, got: " + domElements8["diag-model"].textContent);
            }
            if (domElements8["val-root"].textContent !== "Unavailable") {
                throw new Error("Expected 'Unavailable' on malformed JSON, got: " + domElements8["val-root"].textContent);
            }
            if (domElements8["module-status-badge"].textContent !== "ERROR" || !domElements8["module-status-badge"].classList.contains("badge-error")) {
                throw new Error("Expected ERROR badge on malformed JSON, got: " + domElements8["module-status-badge"].textContent);
            }

            // Test 4.9: WARNING status badge transition
            const domElements9 = {};
            const ctx9 = vm.createContext({
                document: {
                    addEventListener: () => {},
                    querySelectorAll: () => [],
                    getElementById: (id) => {
                        if (!domElements9[id]) domElements9[id] = createMockEl(id);
                        return domElements9[id];
                    }
                },
                ksu: {
                    exec: (cmd) => Promise.resolve({
                        errno: 0,
                        stdout: JSON.stringify({ status: "WARNING", root_manager: "KernelSU", sdk_level: 34 }),
                        stderr: ""
                    })
                }
            });
            vm.runInContext(code, ctx9);
            await ctx9.refreshDiagnostics();
            if (domElements9["module-status-badge"].textContent !== "WARNING" || !domElements9["module-status-badge"].classList.contains("badge-warning")) {
                throw new Error("Expected WARNING badge, got: " + domElements9["module-status-badge"].textContent);
            }

            // Test 4.10: UNKNOWN status badge transition
            const domElements10 = {};
            const ctx10 = vm.createContext({
                document: {
                    addEventListener: () => {},
                    querySelectorAll: () => [],
                    getElementById: (id) => {
                        if (!domElements10[id]) domElements10[id] = createMockEl(id);
                        return domElements10[id];
                    }
                },
                ksu: {
                    exec: (cmd) => Promise.resolve({
                        errno: 0,
                        stdout: JSON.stringify({ status: "UNKNOWN", root_manager: "Unknown" }),
                        stderr: ""
                    })
                }
            });
            vm.runInContext(code, ctx10);
            await ctx10.refreshDiagnostics();
            if (domElements10["module-status-badge"].textContent !== "UNKNOWN" || !domElements10["module-status-badge"].classList.contains("badge-unknown")) {
                throw new Error("Expected UNKNOWN badge, got: " + domElements10["module-status-badge"].textContent);
            }

            // Test 4.11: Desktop preview log version validation
            const previewLog = ctx4.simulateCommand("tail -n 100 /data/adb/matrix_module/logs/matrix.log");
            if (!previewLog.stdout.includes("MatrixModule v1.0.6")) {
                throw new Error("Preview log missing updated version v1.0.6: " + previewLog.stdout);
            }
            if (previewLog.stdout.includes("v1.0.2") || previewLog.stdout.includes("v1.0.3") || previewLog.stdout.includes("v1.0.4") || previewLog.stdout.includes("v1.0.5")) {
                throw new Error("Preview log contains stale version string: " + previewLog.stdout);
            }

            console.log("ALL_BRIDGE_TESTS_OK");
        }

        runBridgeTests().catch(err => {
            console.error("NODE_ERROR:", err.message);
            process.exit(1);
        });
    ' 2>&1)
    
    if echo "$NODE_OUT" | grep -q "ALL_BRIDGE_TESTS_OK"; then
        pass "MM-DEF-03 verified: Async Promises, rejections, legacy strings, and simulation fallback all PASSED"
    else
        fail "Node.js dynamic bridge tests failed: $NODE_OUT"
    fi
else
    echo "[!] Node.js not detected, skipping dynamic VM bridge test"
fi

echo "=================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "[+] All WebUI API & Structure Tests PASSED (0 errors)."
    exit 0
else
    echo "[-] WebUI API & Structure Tests FAILED ($ERRORS error(s))."
    exit 1
fi
