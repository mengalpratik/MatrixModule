#!/system/bin/sh
# AlwaysStrong - HMA Hiding Backend & Sync Engine
#
# Bridges AlwaysStrong's WebUI ("Target apps" & "Apps to hide") with the
# Hide MyAppList (HMA) hiding architecture:
#   1. "Apps to hide" -> Blacklist Template (templates.blacklist.appList)
#   2. "Target apps"  -> HMA Managed Scope (scope[pkg] -> applies blacklist)
#
# Generates and synchronizes config.json for HMA Zygisk module and AlwaysStrong.

AS_CFG_ROOT="${AS_CFG_ROOT:-/data/adb/tricky_store}"
AS_DIR="$AS_CFG_ROOT/alwaysstrong"
AS_HIDDEN="$AS_DIR/hidden_apps"
AS_HMA_CONF="$AS_DIR/config.json"
TGT="${2:-$AS_CFG_ROOT/target.txt}"

# Default recommended apps to hide (root managers, su binaries, detectors)
DEFAULT_HIDDEN="
com.topjohnwu.magisk
io.github.vvb2060.magisk
io.github.huskydg.magisk
me.weishu.kernelsu
com.rifsxd.ksunext
com.sukisu.ultra
me.bmax.apatch
me.garfieldhan.apatch.next
org.lsposed.manager
com.solohsu.android.edxp.manager
org.meowcat.edxposed.manager
de.robv.android.xposed.installer
bin.mt.plus
bin.mt.plus.canary
com.termux
io.github.a13e300.ksuwebui
moe.shizuku.privileged.api
com.dergoogler.mmrl
com.dergoogler.mmrl.wx
"

init_defaults() {
    mkdir -p "$AS_DIR" 2>/dev/null || :
    if [ ! -s "$AS_HIDDEN" ]; then
        for p in $DEFAULT_HIDDEN; do
            [ -n "$p" ] && echo "$p"
        done | sort -u > "$AS_HIDDEN.tmp" 2>/dev/null && mv -f "$AS_HIDDEN.tmp" "$AS_HIDDEN" 2>/dev/null || :
        chmod 600 "$AS_HIDDEN" 2>/dev/null || :
    fi
}

get_hidden() {
    [ -f "$AS_HIDDEN" ] && cat "$AS_HIDDEN" || { init_defaults && cat "$AS_HIDDEN" 2>/dev/null; }
}

sync_config() {
    target_file="${1:-$TGT}"
    mkdir -p "$AS_DIR" 2>/dev/null || :
    [ -f "$AS_HIDDEN" ] || init_defaults

    # Temporary files for awk input
    mkdir -p /data/adb/modules/tricky_store/temp 2>/dev/null || :
    _tmp_hidden="/data/adb/modules/tricky_store/temp/hma_hidden.tmp"
    _tmp_target="/data/adb/modules/tricky_store/temp/hma_target.tmp"
    _tmp_json="/data/adb/modules/tricky_store/temp/hma_config.json.tmp"

    # Clean hidden apps list
    if [ -f "$AS_HIDDEN" ]; then
        sed 's/[[:space:]]//g' "$AS_HIDDEN" 2>/dev/null | grep -vE '^(#|$)' | sort -u > "$_tmp_hidden"
    else
        : > "$_tmp_hidden"
    fi

    # Clean target apps list
    if [ -f "$target_file" ]; then
        sed 's/[[:space:]]//g' "$target_file" 2>/dev/null | grep -vE '^(#|\[|$)' | sed 's/[!?]*$//' | sort -u > "$_tmp_target"
    else
        : > "$_tmp_target"
    fi

    # Generate HMA JsonConfig
    awk '
    BEGIN {
        h_cnt = 0;
        t_cnt = 0;
    }
    FNR == NR {
        if ($0 != "") hidden[h_cnt++] = $0;
        next;
    }
    {
        if ($0 != "") targets[t_cnt++] = $0;
    }
    END {
        print "{";
        print "  \"configVersion\": 1,";
        print "  \"detailLog\": false,";
        print "  \"errorOnlyLog\": false,";
        print "  \"maxLogSize\": 512,";
        print "  \"forceMountData\": true,";
        print "  \"disableActivityLaunchProtection\": false,";
        print "  \"altAppDataIsolation\": false,";
        print "  \"altVoldAppDataIsolation\": false,";
        print "  \"skipSystemAppDataIsolation\": true,";
        print "  \"webViewProtection\": true,";
        print "  \"ignoreBrandProtections\": false,";
        print "  \"templates\": {";
        print "    \"blacklist\": {";
        print "      \"isWhitelist\": false,";
        printf "      \"appList\": [";
        for (i = 0; i < h_cnt; i++) {
            printf "%s\"%s\"", (i > 0 ? ", " : ""), hidden[i];
        }
        print "]";
        print "    }";
        print "  },";
        print "  \"settingsTemplates\": {},";
        print "  \"disabledHooks\": [],";
        print "  \"scope\": {";
        for (i = 0; i < t_cnt; i++) {
            p = targets[i];
            print "    \"" p "\": {";
            print "      \"useWhitelist\": false,";
            print "      \"excludeSystemApps\": true,";
            print "      \"applyTemplates\": [\"blacklist\"],";
            print "      \"applySettingTemplates\": [],";
            print "      \"extraTargetList\": [],";
            print "      \"interceptPackageInfo\": true,";
            print "      \"interceptPackageName\": true,";
            print "      \"interceptApplicationInfo\": true,";
            print "      \"interceptIntent\": true,";
            print "      \"interceptPermission\": true";
            printf "    }%s\n", (i < t_cnt - 1 ? "," : "");
        }
        print "  }";
        print "}";
    }' "$_tmp_hidden" "$_tmp_target" > "$_tmp_json" 2>/dev/null

    rm -f /data/adb/modules/tricky_store/temp/hma_hidden.tmp /data/adb/modules/tricky_store/temp/hma_target.tmp 2>/dev/null || :

    if [ -s /data/adb/modules/tricky_store/temp/hma_config.json.tmp ]; then
        mv -f /data/adb/modules/tricky_store/temp/hma_config.json.tmp /data/adb/tricky_store/alwaysstrong/config.json 2>/dev/null
        chmod 644 /data/adb/tricky_store/alwaysstrong/config.json 2>/dev/null || :

        # Sync to any HMA service directories on device
        for d in /data/misc/hide_my_applist_* /data/system/hide_my_applist_*; do
            if [ -d "$d" ]; then
                cp -f /data/adb/tricky_store/alwaysstrong/config.json "$d/config.json" 2>/dev/null || :
                chmod 666 "$d/config.json" 2>/dev/null || :
            fi
        done
        # Ensure a default directory exists if none found
        if ! ls -d /data/misc/hide_my_applist_* >/dev/null 2>&1; then
            mkdir -p /data/misc/hide_my_applist_alwaysstrong 2>/dev/null || :
            chmod 777 /data/misc/hide_my_applist_alwaysstrong 2>/dev/null || :
            cp -f /data/adb/tricky_store/alwaysstrong/config.json /data/misc/hide_my_applist_alwaysstrong/config.json 2>/dev/null || :
            chmod 666 /data/misc/hide_my_applist_alwaysstrong/config.json 2>/dev/null || :
        fi
    else
        rm -f /data/adb/modules/tricky_store/temp/hma_config.json.tmp 2>/dev/null || :
    fi
}

case "$1" in
    get_hidden|get)
        get_hidden
        ;;
    init_defaults|init)
        init_defaults
        ;;
    sync|"")
        shift 2>/dev/null || :
        sync_config "$@"
        ;;
    toggle_hidden|toggle)
        pkg="$2"
        [ -n "$pkg" ] || exit 0
        mkdir -p "$AS_DIR" 2>/dev/null || :
        [ -f "$AS_HIDDEN" ] || init_defaults
        if grep -qxF "$pkg" "$AS_HIDDEN" 2>/dev/null; then
            grep -vxF "$pkg" "$AS_HIDDEN" 2>/dev/null > "$AS_HIDDEN.tmp" || :
            mv -f "$AS_HIDDEN.tmp" "$AS_HIDDEN" 2>/dev/null || :
        else
            echo "$pkg" >> "$AS_HIDDEN"
        fi
        sync_config "$3"
        ;;
    set_hidden|set)
        mkdir -p "$AS_DIR" 2>/dev/null || :
        cat > "$AS_HIDDEN.tmp"
        mv -f "$AS_HIDDEN.tmp" "$AS_HIDDEN" 2>/dev/null || :
        sync_config "$2"
        ;;
    *)
        echo "Usage: $0 {sync|get|set|toggle|init}"
        exit 1
        ;;
esac
