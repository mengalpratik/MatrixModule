#!/system/bin/sh
# MatrixModule - keybox multi-provider auto-fetch & revocation protection.
#
# Downloads, decodes (supporting raw XML, base64, and Specter substitution cipher),
# verifies XML structure, extracts ASN.1 certificate serial number, checks Google
# Play Integrity Revocation Status API (https://android.googleapis.com/attestation/status?encrypted=0),
# and atomically replaces the target keybox file.
#
# Supported providers:
#   auto      - Smart failover (MeowDump -> Specter Catalog -> Evoker -> Specter Fallback -> Yurikey)
#               prioritizing non-revoked keys.
#   meowdump  - MeowDump Megatron (https://github.com/MeowDump/Integrity-Box/releases/download/archive/Megatron)
#   evoker    - Evoker direct key mirror (https://evoker.qzz.io/key)
#   specter   - Specter Rawbin Catalog (https://rawbin.dpejoh.com/catalog)
#   yurikey   - Yurikey GitHub raw mirror (https://raw.githubusercontent.com/Yurii0307/yurikey/main/key)
#   custom    - User configured URL (custom_keybox_url)
#
# Exit codes:
#   0  keybox updated (new content written)
#   2  no change (already up to date)
#   1  fetch / verify failed (existing keybox preserved)

PRIMARY_URL="${KEYBOX_BASE_URL:-https://evoker.qzz.io/key}"
FALLBACK_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"
SPECTER_CATALOG_URL="https://rawbin.dpejoh.com/catalog"
SPECTER_KEY_BASE="https://rawbin.dpejoh.com/key"
SPECTER_FALLBACK_URL="https://rawbin.dpejoh.com/key/Yuri/8"
MEOWDUMP_URL="https://github.com/MeowDump/Integrity-Box/releases/download/archive/Megatron"
GOOGLE_REVOCATION_URL="https://android.googleapis.com/attestation/status?encrypted=0"

STD_ALPHABET="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
SHUFFLED_ALPHABET="1dgWnocayqxU3r6vA5lCIPYfHmkV08b4tz+KMsp2NQ9LRXihODwSj7BEFJ/ZuGTe"

CONFIG_DIR=/data/adb/tricky_store
TARGET="$CONFIG_DIR/keybox.xml"
MODPATH="${MODPATH:-/data/adb/modules/tricky_store}"

log() { echo "keybox_fetch: $*"; }

if [ -f "$MODPATH/as_store.sh" ]; then
    . "$MODPATH/as_store.sh"
elif [ -f "$CONFIG_DIR/as_store.sh" ]; then
    . "$CONFIG_DIR/as_store.sh"
else
    log "as_store.sh missing - refusing to touch the keybox."
    exit 1
fi

# Custom-keybox mode: the user manages keybox.xml themselves via the WebUI -
# never fetch or overwrite it.
if as_on custom_keybox; then
    log "custom keybox active - skipping fetch."
    exit 2
fi

# Resolve tools
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

# bounded SECS cmd... - run cmd under a hard wall-clock cap.
TO=""
if timeout -k 1 5 true >/dev/null 2>&1; then TO="timeout -k 3"
elif timeout 5 true >/dev/null 2>&1; then TO="timeout"
elif [ -n "$BB" ] && "$BB" timeout -k 1 5 true >/dev/null 2>&1; then TO="$BB timeout -k 3"
elif [ -n "$BB" ] && "$BB" timeout 5 true >/dev/null 2>&1; then TO="$BB timeout"
fi
bounded() { _bs="$1"; shift; if [ -n "$TO" ]; then $TO "$_bs" "$@"; else "$@"; fi; }

# run_engine NAME OUTFILE URL - one download attempt with named engine.
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

# download_url OUTFILE URL - downloads URL using available engines
download_url() {
    _out="$1"
    _url="$2"
    _fe=$(st_get kb_engine)
    for _eng in "$_fe" asfetch bb curl wget; do
        [ -z "$_eng" ] && continue
        if run_engine "$_eng" "$_out" "$_url"; then
            [ "$_eng" != "$_fe" ] && st_set kb_engine "$_eng"
            return 0
        fi
    done
    return 1
}

# decode_megatron IN_FILE OUT_FILE - decodes MeowDump Megatron (10x Base64 -> Hex -> ROT13)
decode_megatron() {
    _m_in="$1"
    _m_out="$2"
    [ -s "$_m_in" ] || return 1
    _m_cur="$_m_in"
    _m_pfx="$TMP/mgt_$$"
    for _m_i in 1 2 3 4 5 6 7 8 9 10; do
        _m_next="${_m_pfx}_${_m_i}"
        $B64DEC < "$_m_cur" > "$_m_next" 2>/dev/null || { rm -f "${_m_pfx}"_* 2>/dev/null; return 1; }
        [ -s "$_m_next" ] || { rm -f "${_m_pfx}"_* 2>/dev/null; return 1; }
        [ "$_m_cur" != "$_m_in" ] && rm -f "$_m_cur" 2>/dev/null
        _m_cur="$_m_next"
    done
    _m_hex="${_m_pfx}_hex"
    if command -v xxd >/dev/null 2>&1; then
        xxd -r -p < "$_m_cur" > "$_m_hex" 2>/dev/null || { rm -f "${_m_pfx}"_* 2>/dev/null; return 1; }
    elif [ -x /system/bin/xxd ]; then
        /system/bin/xxd -r -p < "$_m_cur" > "$_m_hex" 2>/dev/null || { rm -f "${_m_pfx}"_* 2>/dev/null; return 1; }
    else
        rm -f "${_m_pfx}"_* 2>/dev/null
        return 1
    fi
    rm -f "$_m_cur" 2>/dev/null
    tr 'A-Za-z' 'N-ZA-Mn-za-m' < "$_m_hex" > "$_m_out" 2>/dev/null || { rm -f "${_m_pfx}"_* 2>/dev/null; return 1; }
    rm -f "$_m_hex" 2>/dev/null
    head -c 1024 "$_m_out" 2>/dev/null | grep -qi "<Keybox" || head -c 1024 "$_m_out" 2>/dev/null | grep -qi "<AndroidAttestation"
}

# decode_payload IN_FILE OUT_FILE - handles raw XML, standard Base64, Specter cipher, and MeowDump Megatron
decode_payload() {
    _in="$1"
    _out="$2"
    rm -f "$_out"
    [ -s "$_in" ] || return 1

    # 1. Plain XML
    if head -c 1024 "$_in" | grep -qi "<AndroidAttestation" || head -c 1024 "$_in" | grep -qi "<Keybox"; then
        cp -f "$_in" "$_out"
        return 0
    fi

    # 2. Plain Base64
    $B64DEC < "$_in" > "$_out" 2>/dev/null || :
    if head -c 1024 "$_out" 2>/dev/null | grep -qi "<Keybox" || head -c 1024 "$_out" 2>/dev/null | grep -qi "<AndroidAttestation"; then
        return 0
    fi

    # 3. Specter substitution-cipher scrambled Base64
    tr "$SHUFFLED_ALPHABET" "$STD_ALPHABET" < "$_in" 2>/dev/null | $B64DEC > "$_out" 2>/dev/null || :
    if head -c 1024 "$_out" 2>/dev/null | grep -qi "<Keybox" || head -c 1024 "$_out" 2>/dev/null | grep -qi "<AndroidAttestation"; then
        return 0
    fi

    # 4. MeowDump Megatron (10x Base64 -> Hex -> ROT13)
    if head -c 16 "$_in" 2>/dev/null | grep -q "Vm0w"; then
        decode_megatron "$_in" "$_out" && return 0
    fi
    decode_megatron "$_in" "$_out" 2>/dev/null && return 0

    return 1
}

# Parse ASN.1 DER certificate serial from hex string (portable across dash/ash/mksh)
_parse_serial() {
    [ -n "$1" ] || return 1
    printf '%s' "$1" | awk '
    function h2d(s,   i,c,v,n) {
        s = tolower(s); n = length(s); v = 0
        for (i = 1; i <= n; i++) {
            c = index("0123456789abcdef", substr(s, i, 1)) - 1
            if (c < 0) return -1
            v = v * 16 + c
        }
        return v
    }
    function skip_tl(h, pos,   tag,l,nbytes) {
        tag = tolower(substr(h, pos, 2))
        l = h2d(substr(h, pos + 2, 2))
        if (l < 0) return -1
        if (l >= 128) {
            nbytes = l - 128
            return pos + 4 + nbytes * 2
        }
        return pos + 4
    }
    {
        h = $0
        if (tolower(substr(h, 1, 2)) != "30") exit 1
        p = skip_tl(h, 1); if (p < 0) exit 1
        if (tolower(substr(h, p, 2)) != "30") exit 1
        p = skip_tl(h, p); if (p < 0) exit 1
        if (tolower(substr(h, p, 2)) == "a0") {
            ctx_len = h2d(substr(h, p + 2, 2))
            if (ctx_len < 0) exit 1
            p = p + 4 + ctx_len * 2
        }
        if (tolower(substr(h, p, 2)) != "02") exit 1
        l = h2d(substr(h, p + 2, 2))
        if (l < 0) exit 1
        if (l >= 128) {
            nb = l - 128
            sl = h2d(substr(h, p + 4, nb * 2))
            if (sl < 0) exit 1
            ser = substr(h, p + 4 + nb * 2, sl * 2)
        } else {
            ser = substr(h, p + 4, l * 2)
        }
        sub(/^0+/, "", ser)
        if (ser == "") ser = "0"
        print tolower(ser)
    }'
}

decode_keybox_serial() {
    _b64=$(sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p; /-----END CERTIFICATE-----/q" "$1" 2>/dev/null | grep -v "CERTIFICATE" | sed "s/^[[:space:]]*//" | tr -d "\n\r")
    [ -z "$_b64" ] && return 1
    _hex=$(echo "$_b64" | $B64DEC 2>/dev/null | od -v -tx1 | awk "BEGIN{ORS=\"\"} {for(i=2;i<=NF;i++) printf \"%s\", \$i}")
    [ -z "$_hex" ] && return 1
    _parse_serial "$_hex"
}

check_google_revocation() {
    _ser="$1"
    _rev_f="$2"
    [ -z "$_ser" ] && return 2
    [ -s "$_rev_f" ] || return 2
    if grep -qi "\"$_ser\"" "$_rev_f" 2>/dev/null; then
        return 0 # REVOKED
    fi
    return 1 # NOT REVOKED
}

validate_keybox() {
    _vf="$1"
    [ -s "$_vf" ] || return 1
    if head -c 4096 "$_vf" | grep -qi "<Keybox" && \
       grep -q "<PrivateKey" "$_vf" && \
       grep -q "<Certificate" "$_vf"; then
        return 0
    fi
    return 1
}

# Parse arguments
FORCE=0
CLI_PROV=""
CUSTOM_URL=""
while [ $# -gt 0 ]; do
    case "$1" in
        force) FORCE=1 ;;
        custom_url|url)
            CLI_PROV="custom_url"
            CUSTOM_URL="$2"
            shift
            ;;
        auto|evoker|yurikey|specter|rawbin|meowdump|megatron|custom) CLI_PROV="$1" ;;
    esac
    shift
done

KB_PROVIDER="${CLI_PROV:-$(as_get keybox_provider auto)}"
case "$KB_PROVIDER" in
    rawbin) KB_PROVIDER="specter" ;;
    megatron) KB_PROVIDER="meowdump" ;;
esac

# try_candidate CAND_NAME URL OUT_XML REV_FILE
try_candidate() {
    _cname="$1"
    _curl="$2"
    _out_xml="$3"
    _rev_f="$4"

    _raw="$TMP/cand.raw"
    _dec="$TMP/cand.xml"
    rm -f "$_raw" "$_dec"

    if ! download_url "$_raw" "$_curl"; then
        log "candidate $_cname: download failed"
        return 1
    fi

    if ! decode_payload "$_raw" "$_dec"; then
        log "candidate $_cname: decoding failed"
        return 1
    fi

    if ! validate_keybox "$_dec"; then
        log "candidate $_cname: invalid keybox XML structure"
        return 1
    fi

    _ser=$(decode_keybox_serial "$_dec" 2>/dev/null || echo "")
    _rev_status=0
    if [ -n "$_ser" ]; then
        check_google_revocation "$_ser" "$_rev_f"
        _rc=$?
        if [ $_rc -eq 0 ]; then
            log "candidate $_cname (serial $_ser): REVOKED by Google"
            cp -f "$_dec" "$TMP/last_revoked.xml" 2>/dev/null || :
            printf '%s' "$_cname" > "$TMP/last_revoked.src" 2>/dev/null || :
            printf '%s' "$_ser" > "$TMP/last_revoked.ser" 2>/dev/null || :
            return 2 # REVOKED
        elif [ $_rc -eq 1 ]; then
            log "candidate $_cname (serial $_ser): valid & NOT revoked"
            _rev_status=0
        else
            log "candidate $_cname (serial $_ser): revocation status unknown [*]"
            _rev_status=0
        fi
    else
        log "candidate $_cname: serial could not be extracted, assumed active"
    fi

    cp -f "$_dec" "$_out_xml"
    st_set kb_source "$_cname"
    [ -n "$_ser" ] && st_set kb_serial "$_ser"
    st_set kb_revoked "$_rev_status"
    return 0
}

try_fetch() {
    _o="$1"
    _rev_cache="$CONFIG_DIR/alwaysstrong/tmp/revocation.json"
    [ -d "$CONFIG_DIR/alwaysstrong/tmp" ] || _rev_cache="$TMP/revocation.json"

    REV_FILE=""
    if download_url "$TMP/revocation.json" "$GOOGLE_REVOCATION_URL"; then
        REV_FILE="$TMP/revocation.json"
        cp -f "$REV_FILE" "$_rev_cache" 2>/dev/null || :
    elif [ -s "$_rev_cache" ]; then
        REV_FILE="$_rev_cache"
    elif [ -s "$MODPATH/revocation.json" ]; then
        REV_FILE="$MODPATH/revocation.json"
    elif [ -s "$(dirname "$0")/revocation.json" ]; then
        REV_FILE="$(dirname "$0")/revocation.json"
    fi

    case "$KB_PROVIDER" in
        custom_url)
            [ -n "$CUSTOM_URL" ] || CUSTOM_URL=$(as_get custom_keybox_url)
            log "targeted provider: Community Repo ($CUSTOM_URL)"
            if [ -z "$CUSTOM_URL" ]; then
                log "error: no custom url specified"
                return 1
            fi
            if try_candidate "Community Repo" "$CUSTOM_URL" "$_o" "$REV_FILE"; then
                return 0
            elif [ -s "$TMP/last_revoked.xml" ]; then
                cp -f "$TMP/last_revoked.xml" "$_o"
                st_set kb_source "Community Repo"
                st_set kb_serial "$(cat "$TMP/last_revoked.ser" 2>/dev/null || echo "")"
                st_set kb_revoked "1"
                log "warning: installed Community Repo keybox is marked revoked by Google"
                return 0
            fi
            return 1
            ;;
        meowdump)
            log "targeted provider: MeowDump Megatron ($MEOWDUMP_URL)"
            if try_candidate "MeowDump" "$MEOWDUMP_URL" "$_o" "$REV_FILE"; then
                return 0
            elif [ -s "$TMP/last_revoked.xml" ]; then
                cp -f "$TMP/last_revoked.xml" "$_o"
                st_set kb_source "MeowDump"
                st_set kb_serial "$(cat "$TMP/last_revoked.ser" 2>/dev/null || echo "")"
                st_set kb_revoked "1"
                log "warning: installed MeowDump keybox is marked revoked by Google"
                return 0
            fi
            return 1
            ;;
        evoker)
            log "targeted provider: Evoker mirror ($PRIMARY_URL)"
            if try_candidate "Evoker" "$PRIMARY_URL" "$_o" "$REV_FILE"; then
                return 0
            elif [ -s "$TMP/last_revoked.xml" ]; then
                cp -f "$TMP/last_revoked.xml" "$_o"
                st_set kb_source "Evoker"
                st_set kb_serial "$(cat "$TMP/last_revoked.ser" 2>/dev/null || echo "")"
                st_set kb_revoked "1"
                log "warning: installed Evoker keybox is marked revoked by Google"
                return 0
            fi
            return 1
            ;;
        yurikey)
            log "targeted provider: Yurikey mirror ($FALLBACK_URL)"
            if try_candidate "Yurikey" "$FALLBACK_URL" "$_o" "$REV_FILE"; then
                return 0
            elif [ -s "$TMP/last_revoked.xml" ]; then
                cp -f "$TMP/last_revoked.xml" "$_o"
                st_set kb_source "Yurikey"
                st_set kb_serial "$(cat "$TMP/last_revoked.ser" 2>/dev/null || echo "")"
                st_set kb_revoked "1"
                log "warning: installed Yurikey keybox is marked revoked by Google"
                return 0
            fi
            return 1
            ;;
        specter)
            log "targeted provider: Specter Rawbin Catalog"
            _sp_url=""
            _sp_label="Specter"
            if download_url "$TMP/catalog.json" "$SPECTER_CATALOG_URL"; then
                _w_src=$(grep -o '"working":{[^}]*"source":"[^"]*"' "$TMP/catalog.json" | sed 's/.*"source":"\([^"]*\)".*/\1/')
                _w_ver=$(grep -o '"working":{[^}]*"version":"[^"]*"' "$TMP/catalog.json" | sed 's/.*"version":"\([^"]*\)".*/\1/')
                if [ -n "$_w_src" ] && [ -n "$_w_ver" ]; then
                    _sp_url="$SPECTER_KEY_BASE/$_w_src/$_w_ver"
                    _sp_label="Specter ($_w_src/$_w_ver)"
                fi
            fi
            [ -z "$_sp_url" ] && _sp_url="$SPECTER_FALLBACK_URL" && _sp_label="Specter (Yuri/8)"
            if try_candidate "$_sp_label" "$_sp_url" "$_o" "$REV_FILE"; then
                return 0
            elif [ -s "$TMP/last_revoked.xml" ]; then
                cp -f "$TMP/last_revoked.xml" "$_o"
                st_set kb_source "$_sp_label"
                st_set kb_serial "$(cat "$TMP/last_revoked.ser" 2>/dev/null || echo "")"
                st_set kb_revoked "1"
                log "warning: installed Specter keybox is marked revoked by Google"
                return 0
            fi
            return 1
            ;;
        custom)
            _custom_url=$(as_get custom_keybox_url)
            [ -z "$_custom_url" ] && { log "custom keybox URL empty"; return 1; }
            log "targeted provider: Custom URL ($_custom_url)"
            if try_candidate "Custom" "$_custom_url" "$_o" "$REV_FILE"; then
                return 0
            elif [ -s "$TMP/last_revoked.xml" ]; then
                cp -f "$TMP/last_revoked.xml" "$_o"
                st_set kb_source "Custom"
                st_set kb_serial "$(cat "$TMP/last_revoked.ser" 2>/dev/null || echo "")"
                st_set kb_revoked "1"
                return 0
            fi
            return 1
            ;;
        *) # auto
            log "auto mode: finding working non-revoked keybox..."

            # 1. Try MeowDump (GitHub release archive)
            if try_candidate "MeowDump" "$MEOWDUMP_URL" "$_o" "$REV_FILE"; then
                return 0
            fi

            # 2. Try Specter Catalog working entry
            if download_url "$TMP/catalog.json" "$SPECTER_CATALOG_URL"; then
                _w_src=$(grep -o '"working":{[^}]*"source":"[^"]*"' "$TMP/catalog.json" | sed 's/.*"source":"\([^"]*\)".*/\1/')
                _w_ver=$(grep -o '"working":{[^}]*"version":"[^"]*"' "$TMP/catalog.json" | sed 's/.*"version":"\([^"]*\)".*/\1/')
                if [ -n "$_w_src" ] && [ -n "$_w_ver" ]; then
                    if try_candidate "Specter ($_w_src/$_w_ver)" "$SPECTER_KEY_BASE/$_w_src/$_w_ver" "$_o" "$REV_FILE"; then
                        return 0
                    fi
                fi
            fi

            # 3. Try Evoker mirror
            if try_candidate "Evoker" "$PRIMARY_URL" "$_o" "$REV_FILE"; then
                return 0
            fi

            # 4. Try Specter Yuri/8 fallback
            if try_candidate "Specter (Yuri/8)" "$SPECTER_FALLBACK_URL" "$_o" "$REV_FILE"; then
                return 0
            fi

            # 5. Try Yurikey mirror
            if try_candidate "Yurikey" "$FALLBACK_URL" "$_o" "$REV_FILE"; then
                return 0
            fi

            # If all candidates were marked revoked by Google, but at least one downloaded:
            if [ -s "$TMP/last_revoked.xml" ]; then
                cp -f "$TMP/last_revoked.xml" "$_o"
                _last_src=$(cat "$TMP/last_revoked.src" 2>/dev/null || echo "Keybox")
                st_set kb_source "$_last_src"
                st_set kb_serial "$(cat "$TMP/last_revoked.ser" 2>/dev/null || echo "")"
                st_set kb_revoked "1"
                log "warning: all available online keyboxes are revoked by Google; installed $_last_src as fallback"
                return 0
            fi

            log "all providers failed to download or validate."
            return 1
            ;;
    esac
}

# Fetch Executionmkdir -p "$CONFIG_DIR"
TMP=$(as_tmp "keybox.$$")
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 143' TERM
trap 'rm -rf "$TMP"; exit 130' INT

try_fetch "$TMP/keybox.xml" || { log "download failed on all mirrors and engines - keeping existing keybox intact."; exit 1; }

if [ ! -s "$TMP/keybox.xml" ]; then
    log "downloaded keybox is empty - keeping existing keybox intact."
    exit 1
fi

if ! validate_keybox "$TMP/keybox.xml"; then
    log "decoded payload does not contain complete valid keybox structure - keeping existing keybox intact."
    exit 1
fi

NEW_XML_HASH=$($SHA256 < "$TMP/keybox.xml" | awk '{print tolower($1)}')
DISK_HASH=""
[ -s "$TARGET" ] && DISK_HASH=$($SHA256 < "$TARGET" | awk '{print tolower($1)}')

# Change detection
if [ "$FORCE" != "1" ] && [ -n "$DISK_HASH" ] && [ "$DISK_HASH" = "$NEW_XML_HASH" ]; then
    log "already up to date."
    exit 2
fi

# Atomic replace
mv -f "$TMP/keybox.xml" "$TARGET" || { log "mv to $TARGET failed."; exit 1; }
chmod 600 "$TARGET"
log "$TARGET updated ($(wc -c < "$TARGET") bytes)."

_md=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -f "$_md/attest.sh" ] || _md=/data/adb/modules/tricky_store
if [ -f "$_md/attest.sh" ]; then
    ( MODPATH="$_md"; . "$_md/attest.sh" 2>/dev/null
      command -v attest_notify >/dev/null 2>&1 && attest_notify ) >/dev/null 2>&1
fi
if [ -f "$_md/status_fetch.sh" ]; then
    ( MODPATH="$_md"; sh "$_md/status_fetch.sh" manual 2>/dev/null ) >/dev/null 2>&1 || :
fi
exit 0
