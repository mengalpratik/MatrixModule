#!/system/bin/sh
# MatrixModule - HMA-OSS Zygisk Hook Engine Auto-Updater
# Checks upstream release from https://furkank.net/hma_oss_update_checker.json
# Extracts ONLY required engine files (classes.dex, zygisk/*.so, module.prop)
# Discards manager.apk, action.sh, etc. and wipes temporary zip immediately.

HMA_MODDIR="${HMA_MODDIR:-/data/adb/modules/matrixmodule_hiding_engine}"
AS_DIR="${AS_DIR:-/data/adb/tricky_store/alwaysstrong}"
CHECK_URL="https://furkank.net/hma_oss_update_checker.json"
TMP_DIR="/data/local/tmp"

MODPATH="${MODPATH:-/data/adb/modules/tricky_store}"
case "$(uname -m)" in
    aarch64)        _ABI=arm64-v8a ;;
    armv7*|armv8l)  _ABI=armeabi-v7a ;;
    x86_64)         _ABI=x86_64 ;;
    i?86)           _ABI=x86 ;;
    *)              _ABI="" ;;
esac
ASFETCH="$MODPATH/bin/$_ABI/asfetch"
BB=""
for _bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox \
           /data/adb/modules/busybox-ndk/system/*/busybox "$(command -v busybox 2>/dev/null)"; do
    [ -n "$_bb" ] && [ -x "$_bb" ] && BB="$_bb" && break
done

get_local_ver() {
    [ -f "$HMA_MODDIR/module.prop" ] || { echo "unknown"; return; }
    grep '^version=' "$HMA_MODDIR/module.prop" 2>/dev/null | cut -d= -f2
}

get_local_vcode() {
    [ -f "$HMA_MODDIR/module.prop" ] || { echo "0"; return; }
    grep '^versionCode=' "$HMA_MODDIR/module.prop" 2>/dev/null | cut -d= -f2
}

fetch_remote_info() {
    if [ -n "$_ABI" ] && [ -x "$ASFETCH" ]; then
        "$ASFETCH" -T 12 "$CHECK_URL" 2>/dev/null && return 0
    fi
    if [ -n "$BB" ]; then
        "$BB" wget -q -T 12 -O - "$CHECK_URL" 2>/dev/null && return 0
    fi
    _curl=""
    if [ -x "/system/bin/curl" ]; then
        _curl="/system/bin/curl"
    elif command -v curl >/dev/null 2>&1; then
        _curl="curl"
    fi

    if [ -n "$_curl" ]; then
        "$_curl" -sL --connect-timeout 5 -m 12 "$CHECK_URL" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 8 -O - "$CHECK_URL" 2>/dev/null
    fi
}

check_update() {
    _local_ver=$(get_local_ver)
    _local_code=$(get_local_vcode)
    
    _json=$(fetch_remote_info)
    if [ -z "$_json" ]; then
        echo "{\"status\":\"offline\",\"local_version\":\"$_local_ver\",\"local_versionCode\":$_local_code}"
        return 1
    fi

    _remote_ver=$(echo "$_json" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    _remote_code=$(echo "$_json" | sed -n 's/.*"versionCode"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
    _remote_url=$(echo "$_json" | sed -n 's/.*"zipUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 's/\\//g')

    if [ -z "$_remote_code" ]; then
        echo "{\"status\":\"error\",\"message\":\"Failed to parse upstream response\",\"local_version\":\"$_local_ver\"}"
        return 1
    fi

    if [ "$_remote_code" -gt "$_local_code" ] 2>/dev/null; then
        echo "{\"status\":\"update_available\",\"local_version\":\"$_local_ver\",\"local_versionCode\":$_local_code,\"latest_version\":\"$_remote_ver\",\"latest_versionCode\":$_remote_code,\"url\":\"$_remote_url\"}"
        return 0
    else
        echo "{\"status\":\"up_to_date\",\"local_version\":\"$_local_ver\",\"local_versionCode\":$_local_code,\"latest_version\":\"$_remote_ver\",\"latest_versionCode\":$_remote_code}"
        return 0
    fi
}

perform_update() {
    _force=0
    [ "$1" = "force" ] || [ "$2" = "force" ] && _force=1
    _check=$(check_update)
    _status=$(echo "$_check" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ "$_status" = "offline" ]; then
        echo "{\"status\":\"offline\",\"message\":\"No internet connection\"}"
        return 1
    elif [ "$_status" = "up_to_date" ] && [ "$_force" -ne 1 ]; then
        _lver=$(echo "$_check" | sed -n 's/.*"local_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        echo "{\"status\":\"up_to_date\",\"version\":\"$_lver\",\"message\":\"HMA engine is already up to date ($_lver)\"}"
        return 0
    elif [ "$_status" != "update_available" ] && [ "$_force" -ne 1 ]; then
        echo "$_check"
        return 1
    fi

    _remote_url=$(echo "$_check" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    _remote_ver=$(echo "$_check" | sed -n 's/.*"latest_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    _tmp_zip="$TMP_DIR/hma_auto_update.$$.zip"

    _curl=""
    [ -x "/system/bin/curl" ] && _curl="/system/bin/curl"
    [ -z "$_curl" ] && command -v curl >/dev/null 2>&1 && _curl="curl"

    _dl_ok=0
    if [ -n "$_ABI" ] && [ -x "$ASFETCH" ] && "$ASFETCH" -T 30 -o "$_tmp_zip" "$_remote_url" 2>/dev/null && [ -s "$_tmp_zip" ]; then
        _dl_ok=1
    elif [ -n "$BB" ] && "$BB" wget -q -T 30 -O "$_tmp_zip" "$_remote_url" 2>/dev/null && [ -s "$_tmp_zip" ]; then
        _dl_ok=1
    elif [ -n "$_curl" ]; then
        "$_curl" -sL --connect-timeout 8 -m 60 "$_remote_url" -o "$_tmp_zip" 2>/dev/null && _dl_ok=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 15 -O "$_tmp_zip" "$_remote_url" 2>/dev/null && _dl_ok=1
    fi

    if [ "$_dl_ok" -ne 1 ] || [ ! -s "$_tmp_zip" ]; then
        rm -f "$_tmp_zip" 2>/dev/null || :
        echo "{\"status\":\"download_failed\",\"error\":\"Could not download release package\"}"
        return 1
    fi

    if ! unzip -t "$_tmp_zip" >/dev/null 2>&1; then
        rm -f "$_tmp_zip" 2>/dev/null || :
        echo "{\"status\":\"corrupt_zip\",\"error\":\"Downloaded zip is corrupted\"}"
        return 1
    fi

    # Deploy ONLY required hook components (NO manager.apk, NO action.sh)
    mkdir -p "$HMA_MODDIR/zygisk" "$HMA_MODDIR/packages" 2>/dev/null
    unzip -qqjo "$_tmp_zip" "classes.dex" -d "$HMA_MODDIR" 2>/dev/null || :
    unzip -qqjo "$_tmp_zip" "module.prop" -d "$HMA_MODDIR" 2>/dev/null || :
    unzip -qqjo "$_tmp_zip" "packages/android" -d "$HMA_MODDIR/packages" 2>/dev/null || :
    touch "$HMA_MODDIR/packages/android" 2>/dev/null || :
    
    unzip -qqjo "$_tmp_zip" "zygisk/arm64-v8a.so" -d "$HMA_MODDIR/zygisk" 2>/dev/null || :
    unzip -qqjo "$_tmp_zip" "zygisk/armeabi-v7a.so" -d "$HMA_MODDIR/zygisk" 2>/dev/null || :
    
    # Permissions
    chmod 755 "$HMA_MODDIR" "$HMA_MODDIR/zygisk" "$HMA_MODDIR/packages" 2>/dev/null || :
    chmod 644 "$HMA_MODDIR/classes.dex" "$HMA_MODDIR/module.prop" "$HMA_MODDIR/zygisk"/*.so 2>/dev/null || :
    chmod 644 "$HMA_MODDIR/packages/android" 2>/dev/null || :

    # Enforce SELinux contexts for the sub-module directory so Zygote doesn't crash
    chcon -R u:object_r:system_file:s0 "$HMA_MODDIR" 2>/dev/null || :
    chcon -R u:object_r:system_lib_file:s0 "$HMA_MODDIR/zygisk" 2>/dev/null || :

    # Re-apply MatrixModule branding to module.prop
    sed -i 's/^id=.*/id=matrixmodule_hiding_engine/' "$HMA_MODDIR/module.prop" 2>/dev/null || :
    sed -i 's/^name=.*/name=MatrixModule - Hiding Engine/' "$HMA_MODDIR/module.prop" 2>/dev/null || :
    sed -i 's/^author=.*/author=Pratik Mengal (feat. HMA-OSS)/' "$HMA_MODDIR/module.prop" 2>/dev/null || :
    sed -i '/^updateJson=/d' "$HMA_MODDIR/module.prop" 2>/dev/null || :
    grep -q '^banner=' "$HMA_MODDIR/module.prop" 2>/dev/null || echo "banner=banner.png" >> "$HMA_MODDIR/module.prop"
    if [ ! -f "$HMA_MODDIR/banner.png" ] && [ -f "/data/adb/modules/tricky_store/banner.png" ]; then
        cp -f "/data/adb/modules/tricky_store/banner.png" "$HMA_MODDIR/banner.png" 2>/dev/null || :
        chmod 644 "$HMA_MODDIR/banner.png" 2>/dev/null || :
    fi

    # Refresh description status
    [ -f "$HMA_MODDIR/update_desc.sh" ] && sh "$HMA_MODDIR/update_desc.sh" 2>/dev/null || :

    # Ensure manager.apk or action.sh are never left, and clear update flags
    rm -f "$HMA_MODDIR/manager.apk" "$HMA_MODDIR/action.sh" "$HMA_MODDIR/action.sh.bak" "$HMA_MODDIR/update" 2>/dev/null || :
    
    # Wipe the downloaded zip immediately
    rm -f "$_tmp_zip" 2>/dev/null || :

    echo "{\"status\":\"updated\",\"new_version\":\"$_remote_ver\",\"message\":\"HMA engine updated to $_remote_ver. Reboot required to apply.\"}"
    return 0
}

case "$1" in
    check)
        check_update
        ;;
    update|apply)
        shift 2>/dev/null || :
        perform_update "$@"
        ;;
    force)
        perform_update force
        ;;
    auto)
        _check=$(check_update 2>/dev/null)
        if echo "$_check" | grep -q '"update_available"'; then
            perform_update >/dev/null 2>&1
        fi
        ;;
    info|status|"")
        echo "Installed: $(get_local_ver) ($(get_local_vcode))"
        ;;
esac
