#!/bin/sh
##########################################################################################
# MatrixModule - JSON Escaping & Round-Trip Oracle Test Suite
# Tests matrix_json_escape() against Python JSON parsing oracle for 100% data fidelity
##########################################################################################

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HEALTH_SH="$BASE_DIR/core/matrix_health.sh"

echo "[*] Running JSON Escaping Round-Trip Verification Suite..."

ERRORS=0

fail() {
    echo "[-] FAIL: $1"
    ERRORS=$((ERRORS + 1))
}

pass() {
    echo "[+] PASS: $1"
}

if [ ! -f "$HEALTH_SH" ]; then
    fail "core/matrix_health.sh not found"
    exit 1
fi

# Verify Python 3 is available as the test oracle
if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 required as test oracle"
    exit 1
fi

# Source core dependencies and health library
[ -f "$BASE_DIR/core/matrix_env.sh" ] && . "$BASE_DIR/core/matrix_env.sh"
[ -f "$BASE_DIR/core/matrix_store.sh" ] && . "$BASE_DIR/core/matrix_store.sh"
. "$HEALTH_SH"

# Python round-trip validator script
PYTHON_ORACLE=$(cat << 'EOF'
import sys, json

def verify(name, original, escaped):
    json_doc = '{"val": "' + escaped + '"}'
    try:
        parsed = json.loads(json_doc)
        decoded = parsed["val"]
        if decoded == original:
            print(f"PASS|{name}")
            return True
        else:
            print(f"FAIL|{name}|Mismatch: original={repr(original)} decoded={repr(decoded)} escaped={repr(escaped)}")
            return False
    except Exception as e:
        print(f"FAIL|{name}|JSON parse error: {e} | doc={repr(json_doc)}")
        return False

# Read test data from stdin: format is pairs of lines (original, escaped) with length prefixes
# Read length-prefixed chunks
data = sys.stdin.buffer.read()
# Protocol: [4-byte name len][name][4-byte orig len][orig][4-byte esc len][esc]
offset = 0
all_ok = True
while offset < len(data):
    # Name
    n_len = int.from_bytes(data[offset:offset+4], 'big')
    offset += 4
    name = data[offset:offset+n_len].decode('utf-8', errors='replace')
    offset += n_len
    
    # Original
    o_len = int.from_bytes(data[offset:offset+4], 'big')
    offset += 4
    orig = data[offset:offset+o_len].decode('utf-8', errors='replace')
    offset += o_len

    # Escaped
    e_len = int.from_bytes(data[offset:offset+4], 'big')
    offset += 4
    esc = data[offset:offset+e_len].decode('utf-8', errors='replace')
    offset += e_len

    if not verify(name, orig, esc):
        all_ok = False

if not all_ok:
    sys.exit(1)
EOF
)

run_test_case() {
    _tc_name="$1"
    _tc_val="$2"
    _escaped=$(matrix_json_escape "$_tc_val")

    # Run Python validation single-shot for clarity
    _result=$(python3 -c '
import sys, json
name = sys.argv[1]
orig = sys.argv[2]
esc = sys.argv[3]
doc = "{\"val\": \"" + esc + "\"}"
try:
    decoded = json.loads(doc)["val"]
    if decoded == orig:
        print("OK")
    else:
        print(f"MISMATCH: orig={repr(orig)} != decoded={repr(decoded)}")
except Exception as e:
    print(f"ERROR: {e} doc={repr(doc)}")
' "$_tc_name" "$_tc_val" "$_escaped")

    if [ "$_result" = "OK" ]; then
        pass "Test Oracle Round-Trip: $_tc_name"
    else
        fail "Test Oracle Round-Trip: $_tc_name ($_result)"
    fi
}

echo "[*] Executing Target Round-Trip Test Cases (Standard Shell)..."

# 1. Single backslash
run_test_case "Single backslash (\)" '\'

# 2. Consecutive backslashes (2)
run_test_case "Two consecutive backslashes (\\)" '\\'

# 3. Consecutive backslashes (3)
run_test_case "Three consecutive backslashes (\\\)" '\\\'

# 4. Consecutive backslashes (4)
run_test_case "Four consecutive backslashes (\\\\)" '\\\\'

# 5. Double quotes
run_test_case "Single double quote (\")" '"'
run_test_case "Double quotes in string (\"hello world\")" 'echo "hello world"'

# 6. Tabs
_tab_val="col1	col2	col3"
run_test_case "Tab characters in string" "$_tab_val"

# 7. Newlines
_nl_val="line1
line2
line3"
run_test_case "Newline characters in string" "$_nl_val"

# 8. Carriage returns
_cr_val=$(printf "cr1\rcr2\r")
run_test_case "Carriage return characters in string" "$_cr_val"

# 9. CRLF sequences
_crlf_val=$(printf "line1\r\nline2\r\n")
run_test_case "CRLF newline sequences" "$_crlf_val"

# 10. Trailing newlines
_tr_nl_val=$(printf "trailing newline\n")
run_test_case "Trailing newline" "$_tr_nl_val"

# 11. Multiple trailing newlines
_mtr_nl_val=$(printf "multiple trailing\n\n\n")
run_test_case "Multiple trailing newlines" "$_mtr_nl_val"

# 12. Only newlines
_only_nl_val=$(printf "\n\n")
run_test_case "String containing only newlines" "$_only_nl_val"

# 13. C0 Control Character: Backspace (\b, 0x08)
_bs_val=$(printf "before\bafter")
run_test_case "C0 Control Character: Backspace (\b / 0x08)" "$_bs_val"

# 14. C0 Control Character: Form Feed (\f, 0x0C)
_ff_val=$(printf "page1\fpage2")
run_test_case "C0 Control Character: Form Feed (\f / 0x0C)" "$_ff_val"

# 15. C0 Control Character: Bell / Alert (\a, 0x07 -> \u0007)
_bel_val=$(printf "alert\aalert")
run_test_case "C0 Control Character: Bell (\a / 0x07 -> \u0007)" "$_bel_val"

# 16. C0 Control Character: Vertical Tab (\v, 0x0B -> \u000b)
_vt_val=$(printf "row1\vrow2")
run_test_case "C0 Control Character: Vertical Tab (\v / 0x0B -> \u000b)" "$_vt_val"

# 17. C0 Control Character: Escape (\033, 0x1B -> \u001b)
_esc_val=$(printf "\033[31mRed Text\033[0m")
run_test_case "C0 Control Character: ANSI Escape (\033 / 0x1B -> \u001b)" "$_esc_val"

# 18. C0 Control Characters: Low octal codes (\001 SOH, \004 EOT, \037 US)
_soh_val=$(printf "start\001data\004end\037unit")
run_test_case "C0 Control Characters: Low octals (\001, \004, \037)" "$_soh_val"

# 19. C0 Control Characters: Full 31-character C0 sweep (0x01 through 0x1F)
_c0_all=$(python3 -c 'import sys; sys.stdout.write("".join(chr(i) for i in range(1, 32)))')
run_test_case "C0 Control Characters: Full 31-character sweep (0x01-0x1F)" "$_c0_all"

# 20. Complex mixed payload
_complex_val=$(printf "Path\\to\\\"file\"\twith\r\nnewlines and \\\\double slashes\\\\ and \"quotes\" and \a\b\v\f\033")
run_test_case "Complex mixed special characters payload" "$_complex_val"

# 21. Real-world Android property simulation
_prop_val='Samsung "Galaxy" S24 \ Ultra (SM-S928B\DS)	Build/UP1A.231005.007'
run_test_case "Real-world Android model string with quotes and slashes" "$_prop_val"

# Test 15: Android BusyBox Ash Compatibility
echo "[*] Test 15: Android BusyBox Ash Standalone Compatibility..."
if command -v busybox >/dev/null 2>&1; then
    _bb_result=$(busybox sh -c '
    . "'"$HEALTH_SH"'"
    val="BusyBox \"Test\" with \\single\\ and \\\\double\\\\ slashes,	tabs and
newlines"
    esc=$(matrix_json_escape "$val")
    python3 -c "import sys, json; doc = \"{\\\"val\\\": \\\"\" + sys.argv[2] + \"\\\"}\"; sys.exit(0 if json.loads(doc)[\"val\"] == sys.argv[1] else 1)" "$val" "$esc"
    ' 2>&1)
    
    if [ $? -eq 0 ]; then
        pass "BusyBox ash shell round-trip parity verified"
    else
        fail "BusyBox ash shell round-trip failed: $_bb_result"
    fi
else
    echo "[!] BusyBox not found on system; skipped BusyBox test"
fi

# Test 16: Verify Generated Health Report Parses Cleanly in Python
echo "[*] Test 16: Full Generated Health Report JSON Validation..."
TMP_HEALTH_FILE="/tmp/matrix_test_health_$$.json"
export MATRIX_HEALTH_FILE="$TMP_HEALTH_FILE"
matrix_health_generate_report

if [ -f "$TMP_HEALTH_FILE" ]; then
    if python3 -m json.tool "$TMP_HEALTH_FILE" >/dev/null 2>&1; then
        pass "matrix_health_generate_report generates strictly valid JSON"
    else
        fail "matrix_health_generate_report generated invalid JSON:"
        cat "$TMP_HEALTH_FILE"
    fi
    rm -f "$TMP_HEALTH_FILE"
else
    fail "Health report file not created at $TMP_HEALTH_FILE"
fi

echo "=================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "[+] All JSON Round-Trip & Oracle Tests PASSED (0 errors)."
    exit 0
else
    echo "[-] JSON Round-Trip & Oracle Tests FAILED ($ERRORS error(s))."
    exit 1
fi
