#!/system/bin/sh
# Play Integrity engine adapter — PlayIntegrityFork.
#
# The shared module scripts never touch a pif file directly; they go through the
# functions here. build.sh overlays exactly one adapter per build, so action.sh,
# service.sh, pif_native_fetch.sh and customize.sh are identical in both.
#
# Fork's zygisk reads custom.pif.prop, which only its own migrate.sh can produce
# from a pif.prop. Its spoof flags are numeric.

ENGINE=fork
ENGINE_NAME="PlayIntegrityFork"

# Upstream files (from the PIF zip) that customize.sh installs.
ENGINE_FILES="autopif4.sh killpi.sh migrate.sh common_setup.sh example.pif.prop app_replace_list.txt"

# Prop files the STRONG flags are enforced on, module dir first.
engine_pif_targets() {
    echo "$MODPATH/custom.pif.prop $MODPATH/pif.prop \
          $CONFIG_DIR/custom.pif.prop $CONFIG_DIR/pif.prop"
}

# STRONG spoof defaults, in this engine's naming (Fork uses numeric 1/0).
#   spoofProvider=0        leave the keystore provider alone — TEESimulator
#                          supplies the hardware-attested one STRONG needs.
#   spoofVendingFinger=1   Play Store build spoof.
# Any of these can be overridden per-key from the WebUI Advanced tab, which
# writes `key=value` lines into /data/adb/tricky_store/alwaysstrong/spoof.conf. Some wallet /
# banking apps only pass with a flag flipped (e.g. spoofProps=0 on a Poco F8
# Pro). engine_enforce_spoof re-applies these on every boot/hourly pass, so an
# override in spoof.conf survives — without it a flipped flag would silently
# revert an hour after boot.
engine_spoof_defaults() {
    # spoofVendingFinger spoofs the Play Store (Vending) fingerprint. On Android
    # 10–12L (device's REAL sdk ≤ 32) it breaks Play Integrity / GMS instead of
    # helping — AlwaysStrong wouldn't pass there — so it defaults OFF on those
    # releases; on Android 13+ (sdk 33+) it stays ON, it's part of reaching STRONG.
    # Keyed on the real android version, never the spoofed one. spoof.conf can still
    # override it per device (WebUI Advanced tab).
    _svf=1
    _sdk=$(getprop ro.build.version.sdk 2>/dev/null)
    case "$_sdk" in ''|*[!0-9]*) : ;; *) [ "$_sdk" -le 32 ] && _svf=0 ;; esac
    echo "spoofProvider=0 spoofVendingFinger=$_svf spoofBuild=1 spoofProps=1 spoofSignature=0 spoofVendingSdk=0"
}

# Effective value for a spoof key: the spoof.conf override if present, else the
# STRONG default passed in $2.
engine_spoof_val() {
    _ov=$(sed -n "s/^$1=//p" "$CONFIG_DIR/alwaysstrong/spoof.conf" 2>/dev/null | head -1 | tr -d ' \t\r')
    [ -z "$_ov" ] && _ov=$(sed -n "s/^$1=//p" "$CONFIG_DIR/spoof.conf" 2>/dev/null | head -1 | tr -d ' \t\r')
    [ -n "$_ov" ] && echo "$_ov" || echo "$2"
}

# Space-separated key=value list with overrides applied (for engine_enforce_spoof).
engine_spoof_kv() {
    _out=""
    for _kv in $(engine_spoof_defaults); do
        _out="$_out ${_kv%=*}=$(engine_spoof_val "${_kv%=*}" "${_kv#*=}")"
    done
    echo $_out
}

# Same list, one per line — appended to a freshly fetched fingerprint.
engine_spoof_block() {
    for _kv in $(engine_spoof_kv); do echo "$_kv"; done
}

# engine_install_pif SRC — put a fingerprint where the zygisk reads it.
# Non-zero when this engine can't consume SRC, so callers fall through to the
# next fingerprint source instead of reporting a success that never landed.
engine_install_pif() {
    _src="$1"
    [ -s "$_src" ] || return 1
    [ -f "$MODPATH/migrate.sh" ] || return 1
    cp -f "$_src" "$MODPATH/pif.prop" 2>/dev/null
    rm -f "$MODPATH/custom.pif.prop" "$MODPATH/custom.pif.json" 2>/dev/null
    # A file that is already a finished custom.pif.prop comes in two shapes,
    # and upstream migrate.sh refuses BOTH with "No migration required" (exit 1,
    # writes nothing) — which surfaced as "engine rejected the fingerprint":
    #   1. the advanced style, with *api_level / *.build.id System-Property lines
    #   2. the plain style that already carries populated ro.* System Properties
    #      (ro.build.fingerprint=google/… etc.) — the layout of example.pif.prop
    #      and of the canary-miner / Pixel-beta pif.prop files the WebUI imports.
    # Either way the Fork zygisk reads it verbatim, so use it as-is. Only run
    # migrate.sh for a raw pif.prop/json that still lacks the ro.* lines (what
    # pif_native_fetch.sh / a bare pif.json produces); an EMPTY ro.build.fingerprint=
    # (the blank template) does not count as finished, hence the [^[:space:]] guard.
    if grep -qE '^[[:space:]]*#?[[:space:]]*\*(api_level|\.build\.id)=' "$MODPATH/pif.prop" 2>/dev/null \
       || grep -qE '^[[:space:]]*ro\.build\.fingerprint=[^[:space:]]' "$MODPATH/pif.prop" 2>/dev/null; then
        cp -f "$MODPATH/pif.prop" "$MODPATH/custom.pif.prop" 2>/dev/null
    else
        sh "$MODPATH/migrate.sh" -i -a "$MODPATH/pif.prop" >/dev/null 2>&1
    fi
    [ -s "$MODPATH/custom.pif.prop" ] || return 1
    # migrate.sh writes spoofProvider=1 / spoofVendingFinger=0, a WEAK config
    # that breaks STRONG. Enforce here so every caller is correct without
    # needing its own enforce step.
    engine_enforce_spoof
    return 0
}

# engine_autopif — upstream's own fetcher; the fallback when our native crawl
# fails. Leaves the engine's prop file in place. 0 on success.
engine_autopif() {
    [ -f "$MODPATH/autopif4.sh" ] || return 1
    sh "$MODPATH/autopif4.sh" -s -m || return 1
    [ -s "$MODPATH/custom.pif.prop" ] || return 1
    engine_enforce_spoof
    return 0
}

# Resolve the native asfetch binary for this device's ABI (empty if there is
# none — e.g. the build shipped no prebuilt for it, or the exec bit isn't set
# yet during install). Its `enforce-spoof` subcommand does the whole rewrite in
# ONE process; pure local file I/O, so it needs no watchdog/timeout.
_engine_asfetch() {
    case "$(uname -m 2>/dev/null)" in
        aarch64)        _ea_abi=arm64-v8a ;;
        armv7*|armv8l)  _ea_abi=armeabi-v7a ;;
        x86_64)         _ea_abi=x86_64 ;;
        i?86|i686)      _ea_abi=x86 ;;
        *)              return 1 ;;
    esac
    [ -x "$MODPATH/bin/$_ea_abi/asfetch" ] && echo "$MODPATH/bin/$_ea_abi/asfetch"
}

# Apply the STRONG flags to every prop file this engine may read.
engine_enforce_spoof() {
    # engine_spoof_kv is deterministic (it reads the real sdk + spoof.conf, never
    # the target file), so compute it ONCE, not once per target file.
    _kvs=$(engine_spoof_kv)
    [ -n "$_kvs" ] || return 0
    # Fast path: one native asfetch process replaces+appends every key across all
    # target files (vs a sed + grep spawned per file). Same result as the shell
    # fallback below on the prop files this module writes; on a file with no final
    # newline it is actually safer (sed's append would glue onto the last line).
    _af=$(_engine_asfetch 2>/dev/null)
    if [ -n "$_af" ] && "$_af" enforce-spoof --kv "$_kvs" $(engine_pif_targets) 2>/dev/null; then
        return 0
    fi
    # Shell fallback (no prebuilt for this ABI, or the native call failed): ONE sed
    # pass per file (one -e each) instead of a grep+sed per key, then append any
    # key the file lacked (ONE grep per file + a spawn-free check). Idempotent, so
    # re-running after a partial native pass is harmless.
    _sed=${SED_I:-sed -i}
    _script=""
    for _kv in $_kvs; do
        _script="$_script -e s|^${_kv%=*}=.*|${_kv%=*}=${_kv#*=}|"
    done
    for _f in $(engine_pif_targets); do
        [ -f "$_f" ] || continue
        $_sed $_script "$_f"
        _have=$(grep -oE '^[A-Za-z][A-Za-z0-9_]*=' "$_f" 2>/dev/null | tr -d '\n')
        for _kv in $_kvs; do
            case "$_have" in *"${_kv%=*}="*) ;; *) echo "$_kv" >> "$_f" ;; esac
        done
    done
}

# Seconds before the native crawl / upstream fetcher are killed. Generous on
# purpose: both fetchers time out on their own when nothing arrives (idle
# timeouts / a no-progress watchdog), so these only backstop a stuck process —
# a slow 2G link that is still delivering bytes must not be cut off here.
ENGINE_NATIVE_TIMEOUT=240
ENGINE_AUTOPIF_TIMEOUT=180
