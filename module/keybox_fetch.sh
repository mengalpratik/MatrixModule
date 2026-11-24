#!/system/bin/sh
# AlwaysStrong — keybox auto-fetch.
#
# Downloads a base64-encoded keybox from the project's keybox mirror
# ($BASE_URL/key), hashes the downloaded bytes locally to detect whether
# anything changed since the last apply, decodes, validates that the payload
# looks like a keybox, then atomically replaces the target file. Override the
# source endpoint with the KEYBOX_BASE_URL env var.
#
# Exit codes:
#   0  keybox updated (new content written)
#   2  no change (already up to date)
#   1  fetch / verify failed (existing keybox preserved)

PRIMARY_URL="${KEYBOX_BASE_URL:-https://evoker.qzz.io/key}"
FALLBACK_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"

CONFIG_DIR=/data/adb/tricky_store
TARGET="$CONFIG_DIR/keybox.xml"
MODPATH="${MODPATH:-/data/adb/modules/tricky_store}"

log() { echo "keybox_fetch: $*"; }

# The custom-keybox switch lives in the store, and without it we cannot tell
# whether the user manages keybox.xml themselves - guessing wrong overwrites
# their file, so this fails closed rather than fetching blind.
if [ -f "$MODPATH/as_store.sh" ]; then
    . "$MODPATH/as_store.sh"
else
    log "as_store.sh missing - refusing to touch the keybox."
    exit 1
fi

# Custom-keybox mode: the user manages keybox.xml themselves via the WebUI —
# never fetch or overwrite it. (Defensive; action.sh/service.sh also gate on this.)
if as_on custom_keybox; then
    log "custom keybox active — skipping fetch."
    exit 2
fi

if [ -z "$PRIMARY_URL" ]; then
    log "no KEYBOX_BASE_URL configured — skipping."
    exit 1
fi

# ---- Resolve tools ----
# No single downloader works on every device: busybox wget's built-in TLS
# stalls mid-stream on the keybox mirror CDN on some devices, while our bundled
# rustls fetcher (asfetch) fails to connect on others. So we try each available
# engine in turn (asfetch → busybox wget → curl → system wget) and keep the
# first that actually returns bytes — never trust one tool to always work.
SELF_DIR=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -z "$SELF_DIR" ] && SELF_DIR=/data/adb/modules/tricky_store
case "$(uname -m)" in
    aarch64)        ABI=arm64-v8a ;;
    armv7*|armv8l)  ABI=armeabi-v7a ;;
    x86_64)         ABI=x86_64 ;;
    i?86)           ABI=x86 ;;
    *)              ABI="" ;;
esac
ASFETCH="$SELF_DIR/bin/$ABI/asfetch"
BB=""
for bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox \
          /data/adb/modules/busybox-ndk/system/*/busybox "$(command -v busybox 2>/dev/null)"; do
    [ -n "$bb" ] && [ -x "$bb" ] && BB="$bb" && break
done

# bounded SECS cmd... — run cmd under a hard wall-clock cap.
TO=""
if timeout -k 1 5 true >/dev/null 2>&1; then TO="timeout -k 3"
elif timeout 5 true >/dev/null 2>&1; then TO="timeout"
elif [ -n "$BB" ] && "$BB" timeout -k 1 5 true >/dev/null 2>&1; then TO="$BB timeout -k 3"
elif [ -n "$BB" ] && "$BB" timeout 5 true >/dev/null 2>&1; then TO="$BB timeout"
fi
bounded() { _bs="$1"; shift; if [ -n "$TO" ]; then $TO "$_bs" "$@"; else "$@"; fi; }

# run_engine NAME OUTFILE URL — one download attempt with the named engine.
# Enforce -L (follow redirects) and 15s timeout across all engines.
run_engine() {
    rm -f "$2"
    case "$1" in
        asfetch) [ -n "$ABI" ] && [ -f "$ASFETCH" ] && { [ -x "$ASFETCH" ] || chmod 0755 "$ASFETCH" 2>/dev/null; } && bounded 30 "$ASFETCH" -T 15 -o "$2" "$3" 2>/dev/null ;;
        bb)      [ -n "$BB" ] && bounded 30 "$BB" wget -q -T 15 -O "$2" "$3" 2>/dev/null ;;
        curl)    command -v curl >/dev/null 2>&1 && bounded 30 curl -fsSL --connect-timeout 15 --speed-limit 1 --speed-time 15 --max-time 30 -o "$2" "$3" 2>/dev/null ;;
        wget)    command -v wget >/dev/null 2>&1 && bounded 30 wget -q --max-redirect=5 --timeout=15 -T 15 -O "$2" "$3" 2>/dev/null ;;
    esac
    [ -s "$2" ]
}

# Parse arguments
FORCE=0
CLI_PROV=""
for arg in "$@"; do
    case "$arg" in
        force) FORCE=1 ;;
        auto|evoker|yurikey|custom) CLI_PROV="$arg" ;;
    esac
done

KB_PROVIDER="${CLI_PROV:-$(as_get keybox_provider auto)}"

# try_fetch OUTFILE — fetches keybox based on selected provider (auto, evoker, yurikey, custom)
try_fetch() {
    _o="$1"
    _first=$(st_get kb_engine)

    case "$KB_PROVIDER" in
        evoker)
            log "targeted provider: Evoker mirror ($PRIMARY_URL)"
            for _e in "$_first" asfetch bb curl wget; do
                [ -z "$_e" ] && continue
                if run_engine "$_e" "$_o" "$PRIMARY_URL"; then
                    [ "$_e" != "$_first" ] && st_set kb_engine "$_e"
                    st_set kb_source "Evoker"
                    log "downloaded keybox from Evoker using $_e"
                    return 0
                fi
            done
            return 1
            ;;
        yurikey)
            log "targeted provider: Yurikey mirror ($FALLBACK_URL)"
            for _e in "$_first" asfetch bb curl wget; do
                [ -z "$_e" ] && continue
                if run_engine "$_e" "$_o" "$FALLBACK_URL"; then
                    [ "$_e" != "$_first" ] && st_set kb_engine "$_e"
                    st_set kb_source "Yurikey"
                    log "downloaded keybox from Yurikey using $_e"
                    return 0
                fi
            done
            return 1
            ;;
        custom)
            _custom_url=$(as_get custom_keybox_url)
            [ -z "$_custom_url" ] && { log "custom keybox URL empty"; return 1; }
            log "targeted provider: Custom URL ($_custom_url)"
            for _e in "$_first" asfetch bb curl wget; do
                [ -z "$_e" ] && continue
                if run_engine "$_e" "$_o" "$_custom_url"; then
                    [ "$_e" != "$_first" ] && st_set kb_engine "$_e"
                    st_set kb_source "Custom"
                    log "downloaded keybox from Custom URL using $_e"
                    return 0
                fi
            done
            return 1
            ;;
        *) # auto (default failover: Evoker first, then Yurikey)
            for _e in "$_first" asfetch bb curl wget; do
                [ -z "$_e" ] && continue
                if run_engine "$_e" "$_o" "$PRIMARY_URL"; then
                    [ "$_e" != "$_first" ] && st_set kb_engine "$_e"
                    st_set kb_source "Evoker"
                    log "downloaded keybox from primary mirror (Evoker) using $_e"
                    return 0
                fi
            done

            log "primary mirror failed; switching to secondary failover mirror (Yurikey)..."
            for _e in "$_first" asfetch bb curl wget; do
                [ -z "$_e" ] && continue
                if run_engine "$_e" "$_o" "$FALLBACK_URL"; then
                    [ "$_e" != "$_first" ] && st_set kb_engine "$_e"
                    st_set kb_source "Yurikey"
                    log "downloaded keybox from secondary failover mirror (Yurikey) using $_e"
                    return 0
                fi
            done
            return 1
            ;;
    esac
}

B64DEC=""
if echo dGVzdA== | base64 -d >/dev/null 2>&1; then
    B64DEC="base64 -d"
else
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$bb" ] && echo dGVzdA== | "$bb" base64 -d >/dev/null 2>&1; then
            B64DEC="$bb base64 -d"; break
        fi
    done
fi
[ -z "$B64DEC" ] && { log "no base64 decoder available."; exit 1; }

SHA256=""
if command -v sha256sum >/dev/null 2>&1; then
    SHA256="sha256sum"
else
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$bb" ] && echo x | "$bb" sha256sum >/dev/null 2>&1; then
            SHA256="$bb sha256sum"; break
        fi
    done
fi
[ -z "$SHA256" ] && { log "no sha256sum available."; exit 1; }

# ---- Fetch ----
mkdir -p "$CONFIG_DIR"
TMP=$(as_tmp "keybox.$$")
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM

try_fetch "$TMP/key" || { log "download failed on all mirrors and engines — keeping existing keybox intact."; exit 1; }

if [ ! -s "$TMP/key" ]; then
    log "downloaded payload is empty — keeping existing keybox intact."
    exit 1
fi

# ---- Decode & Safeguard Validation ----
# Always decode the downloaded payload into a temporary file first. The active
# on-disk keybox ($TARGET) is NEVER modified, deleted, or truncated unless the
# downloaded keybox is 100% complete and verified with full key/cert structure.
$B64DEC < "$TMP/key" > "$TMP/keybox.xml" 2>/dev/null
if [ ! -s "$TMP/keybox.xml" ]; then
    log "base64 decode produced empty output — keeping existing keybox intact."
    exit 1
fi

# Verify complete XML structure (root tag, ECDSA private key, certificate chain)
if ! head -c 4096 "$TMP/keybox.xml" | grep -q "Keybox" || \
   ! grep -q "<PrivateKey" "$TMP/keybox.xml" || \
   ! grep -q "<Certificate" "$TMP/keybox.xml"; then
    log "decoded payload does not contain complete valid keybox structure — keeping existing keybox intact."
    exit 1
fi

NEW_XML_HASH=$($SHA256 < "$TMP/keybox.xml" | awk '{print tolower($1)}')
DISK_HASH=""
[ -s "$TARGET" ] && DISK_HASH=$($SHA256 < "$TARGET" | awk '{print tolower($1)}')

# ---- Change detection (compare actual on-disk XML, not a side-state) ---
if [ "$FORCE" != "1" ] && [ -n "$DISK_HASH" ] && [ "$DISK_HASH" = "$NEW_XML_HASH" ]; then
    log "already up to date."
    exit 2
fi

# ---- Atomic replace ----
mv -f "$TMP/keybox.xml" "$TARGET" || { log "mv to $TARGET failed."; exit 1; }
chmod 600 "$TARGET"
log "$TARGET updated ($(wc -c < "$TARGET") bytes)."

# Tell the attestation engine the keybox changed. TEESimulator-RS and
# TrickyStoreOSS watch this directory themselves; JingMatrix TEESimulator only
# watches /data/adb/teesim, where our keybox is a symlink into here, and inotify
# never sees a write to a symlink's target — its adapter rewrites config.json so
# the daemon re-reads the keybox. No-op on the other engines. Subshell so the
# adapter's variables don't leak into this script.
_md=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -f "$_md/attest.sh" ] || _md=/data/adb/modules/tricky_store
if [ -f "$_md/attest.sh" ]; then
    ( MODPATH="$_md"; . "$_md/attest.sh" 2>/dev/null
      command -v attest_notify >/dev/null 2>&1 && attest_notify ) >/dev/null 2>&1
fi
exit 0
