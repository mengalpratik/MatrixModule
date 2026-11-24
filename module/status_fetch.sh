#!/system/bin/sh
# Fetch the keybox status and prepend it to module.prop's description line
# so KSU/APatch/MMRL show the current health at a glance.
#
# Format: "description=[Valid 💚] [Provider] <base>"
# Or:     "description=[Revoked ❤️🩹] [Provider] <base>"
# Base text is the canonical line from description.txt.
#
# Called from action.sh (every press) and service.sh (hourly + first boot).
# Idempotent: only rewrites module.prop if the prefix actually changed.

MODPATH="${MODPATH:-/data/adb/modules/tricky_store}"
PROP="$MODPATH/module.prop"
BASE_FILE="$MODPATH/description.txt"
CONFIG_DIR=/data/adb/tricky_store
[ -f "$MODPATH/as_store.sh" ] && . "$MODPATH/as_store.sh"

# mode: "manual" (action button — always writes module.prop)
#       "auto"   (service.sh hourly — skips the write when status_indicator=0)
#       "strip"  (WebUI indicator OFF — rewrite description to base, no fetch)
MODE="${1:-auto}"

[ -f "$PROP" ] || exit 1
[ -f "$BASE_FILE" ] || exit 1

get_status_prefix() {
    _rev=""
    if command -v st_get >/dev/null 2>&1; then
        _is_rev=$(st_get kb_revoked 2>/dev/null)
        if [ "$_is_rev" = "0" ]; then
            _rev="[Valid 💚]"
        elif [ "$_is_rev" = "1" ]; then
            _rev="[Revoked ❤️🩹]"
        fi
    fi
    [ -z "$_rev" ] && _rev="[Valid 💚]"
    echo "$_rev"
}

get_key_label() {
    _label=""
    if [ -f "$CONFIG_DIR/as_store.sh" ] || [ -f "$MODPATH/as_store.sh" ]; then
        if as_on custom_keybox 2>/dev/null; then
            _label="Custom"
        fi
    fi
    if [ -z "$_label" ]; then
        command -v st_get >/dev/null 2>&1 && _label=$(st_get kb_source 2>/dev/null)
    fi
    if [ -z "$_label" ]; then
        _devid=$(grep -oiE 'DeviceID="[^"]*"' "$CONFIG_DIR/keybox.xml" 2>/dev/null | cut -d'"' -f2)
        _yk=$(echo "$_devid" | grep -oiE 'yurikey[0-9]*' | head -1)
        if [ -n "$_yk" ]; then
            _label="$_yk"
        elif echo "$_devid" | grep -qi 'evoker'; then
            _label="Evoker"
        elif [ -s "$CONFIG_DIR/keybox.xml" ] && grep -qi 'kowx712' "$CONFIG_DIR/keybox.xml"; then
            _label="TAKR"
        fi
    fi
    [ -z "$_label" ] && _label="Keybox"
    echo "$_label"
}

base=$(head -1 "$BASE_FILE" | tr -d '\r\n')
[ -z "$base" ] && exit 4

# Strip mode: restore description= to the canonical base text from
# description.txt, removing any status prefix. Used by the WebUI when the
# user disables the indicator.
if [ "$MODE" = "strip" ]; then
    want="description=${base}"
    have=$(grep -m1 '^description=' "$PROP")
    [ "$have" = "$want" ] && exit 0
    tmp="${PROP}.tmp"
    awk -v new="$want" '
        !done && /^description=/ { print new; done=1; next }
        { print }
    ' "$PROP" > "$tmp" && mv -f "$tmp" "$PROP"
    exit 0
fi

# Auto path + user opted out of indicator → exit without touching module.prop.
if [ "$MODE" != "manual" ] && ! as_on status_indicator; then
    exit 0
fi

status_prefix=$(get_status_prefix)
key_tag="[$(get_key_label)]"
want="description=${status_prefix} ${key_tag} ${base}"
have=$(grep -m1 '^description=' "$PROP")

[ "$have" = "$want" ] && exit 0

# Atomic rewrite: produce full file in tmp, swap in.
tmp="${PROP}.tmp"
awk -v new="$want" '
    !done && /^description=/ { print new; done=1; next }
    { print }
' "$PROP" > "$tmp" && mv -f "$tmp" "$PROP"
exit 0
