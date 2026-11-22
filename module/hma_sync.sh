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
AS_GRANTED="$AS_DIR/granted_apps"
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
com.originsu.manager
com.resukisu.resukisu
com.ntjmdja
catch_.me_.if_.you_.can_
org.frknkrc44.hma_oss
com.agy
"

# Curated UPI, banking, and financial apps that should always be scoped in HMA
# so root apps and managers are hidden from them via Zygisk hook.
DEFAULT_SCOPED_BANKING="
com.phonepe.app
com.popclub.android
net.one97.paytm
in.org.npci.upiapp
com.google.android.apps.nbu.paisa.user
com.sbi.lotusintouch
com.mgs.indusmobile
com.icicibank.mobile
com.axis.mobile
com.kotak.mobile
com.hdfcbank.android
com.bankofbaroda.mconnect
com.canarabank.mobility
com.unionbank.ecommerce.mobile.android
com.infrasofttech.indianbank
com.cub.corporatebanking
com.fampay.in
com.jupiter.money
money.jupiter
com.niyo.bharat
com.fi.money
com.paytmmall
in.mobikwik.android
com.freecharge.android
com.dreamplug.androidapp
indwin.c3.shareapp
com.navi.finance
com.payzapp
com.chqbook.android
com.zerodha.kite3
com.nextbillion.groww
com.angelmobile
"

# Dynamic Root Grant Extractor (KernelSU, Magisk, APatch)
get_granted_root_apps() {
    {
        # 1. KernelSU allowlists & temp grants
        for f in /data/adb/ksu/.allowlist /data/adb/ksu/allowlist /data/adb/ksu/temp_grants.json; do
            [ -f "$f" ] || continue
            tr -s ' \t\r\n\0"' '\n' < "$f" 2>/dev/null
        done

        # 2. Magisk database policies (policy=2 is POLICY_ALLOW)
        for db in /data/adb/magisk.db /data/adb/magisk/magisk.db; do
            [ -f "$db" ] || continue
            _sql_bin=""
            if command -v sqlite3 >/dev/null 2>&1; then
                _sql_bin="sqlite3"
            elif [ -x "/system/bin/sqlite3" ]; then
                _sql_bin="/system/bin/sqlite3"
            fi

            if [ -n "$_sql_bin" ]; then
                "$_sql_bin" "$db" "SELECT package_name FROM policies WHERE policy=2;" 2>/dev/null
            elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
                _py_bin="python3"
                command -v python3 >/dev/null 2>&1 || _py_bin="python"
                "$_py_bin" -c "import sqlite3; con=sqlite3.connect('$db'); print('\n'.join(r[0] for r in con.execute('SELECT package_name FROM policies WHERE policy=2')))" 2>/dev/null
            else
                strings "$db" 2>/dev/null
            fi
        done

        # 3. APatch package config & superkeys
        for f in /data/adb/ap/package_config /data/adb/ap/superkeys /data/adb/ap/.allowlist /data/adb/ap/allowlist; do
            [ -f "$f" ] || continue
            tr -s ' \t\r\n\0"' '\n' < "$f" 2>/dev/null
        done
    } | grep -E '^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$' | \
        grep -vE '^(u:r:|android$|system$|com\.android\.|com\.google\.android\.(gms|gsf|vending|packageinstaller))' | \
        sort -u
}

init_defaults() {
    mkdir -p "$AS_DIR" 2>/dev/null || :
    _granted=$(get_granted_root_apps 2>/dev/null)
    if [ -n "$_granted" ]; then
        echo "$_granted" > "$AS_GRANTED.tmp" 2>/dev/null && mv -f "$AS_GRANTED.tmp" "$AS_GRANTED" 2>/dev/null || :
    fi

    # Merge DEFAULT_HIDDEN + _granted + existing AS_HIDDEN
    {
        for p in $DEFAULT_HIDDEN; do
            [ -n "$p" ] && echo "$p"
        done
        [ -n "$_granted" ] && echo "$_granted"
        [ -f "$AS_HIDDEN" ] && cat "$AS_HIDDEN" 2>/dev/null
    } | sed 's/[[:space:]]//g' | grep -vE '^(#|$)' | sort -u > "$AS_HIDDEN.tmp" 2>/dev/null && mv -f "$AS_HIDDEN.tmp" "$AS_HIDDEN" 2>/dev/null || :
    chmod 600 "$AS_HIDDEN" 2>/dev/null || :
}

get_hidden() {
    [ -f "$AS_HIDDEN" ] && cat "$AS_HIDDEN" || { init_defaults && cat "$AS_HIDDEN" 2>/dev/null; }
}

sync_config() {
    target_file="${1:-$TGT}"
    mkdir -p "$AS_DIR" 2>/dev/null || :
    [ -f "$AS_HIDDEN" ] || init_defaults

    # Dynamic Root Database Scan & Merge
    _granted=$(get_granted_root_apps 2>/dev/null)
    if [ -n "$_granted" ]; then
        echo "$_granted" > "$AS_GRANTED.tmp" 2>/dev/null && mv -f "$AS_GRANTED.tmp" "$AS_GRANTED" 2>/dev/null || :
    fi

    # Auto-merge DEFAULT_HIDDEN + _granted into AS_HIDDEN
    {
        for p in $DEFAULT_HIDDEN; do
            [ -n "$p" ] && echo "$p"
        done
        [ -n "$_granted" ] && echo "$_granted"
        [ -f "$AS_HIDDEN" ] && cat "$AS_HIDDEN" 2>/dev/null
    } | sed 's/[[:space:]]//g' | grep -vE '^(#|$)' | sort -u > "$AS_HIDDEN.tmp" 2>/dev/null && mv -f "$AS_HIDDEN.tmp" "$AS_HIDDEN" 2>/dev/null || :
    chmod 600 "$AS_HIDDEN" 2>/dev/null || :

    # Temporary files for awk input
    _tmp_hidden="$AS_DIR/.hma_hidden.$$.tmp"
    _tmp_target="$AS_DIR/.hma_target.$$.tmp"
    _tmp_json="$AS_DIR/.hma_config.$$.tmp"

    # Clean hidden apps list
    if [ -f "$AS_HIDDEN" ]; then
        sed 's/[[:space:]]//g' "$AS_HIDDEN" 2>/dev/null | grep -vE '^(#|$)' | sort -u > "$_tmp_hidden"
    else
        : > "$_tmp_hidden"
    fi

    # Clean target apps list (merge target.txt + DEFAULT_SCOPED_BANKING)
    {
        if [ -f "$target_file" ]; then
            sed 's/[[:space:]]//g' "$target_file" 2>/dev/null | grep -vE '^(#|\[|$)' | sed 's/[!?]*$//'
        fi
        for b in $DEFAULT_SCOPED_BANKING; do
            [ -n "$b" ] && echo "$b"
        done
    } | sed 's/[[:space:]]//g' | grep -vE '^(#|$)' | sort -u > "$_tmp_target"

    # Generate HMA JsonConfig
    awk '
    BEGIN {
        h_cnt = 0;
        t_cnt = 0;
    }
    FNR == NR {
        if ($0 != "") {
            hidden[h_cnt++] = $0;
            is_hidden[$0] = 1;
        }
        next;
    }
    {
        if ($0 != "" && !is_hidden[$0]) targets[t_cnt++] = $0;
    }
    END {
        print "{";
        print "  \"configVersion\": 1,";
        print "  \"detailLog\": false,";
        print "  \"errorOnlyLog\": false,";
        print "  \"maxLogSize\": 512,";
        print "  \"forceMountData\": true,";
        print "  \"disableActivityLaunchProtection\": false,";
        print "  \"altAppDataIsolation\": true,";
        print "  \"altVoldAppDataIsolation\": true,";
        print "  \"skipSystemAppDataIsolation\": false,";
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

    rm -f "$_tmp_hidden" "$_tmp_target" 2>/dev/null || :

    if [ -s "$_tmp_json" ]; then
        mv -f "$_tmp_json" "$AS_HMA_CONF" 2>/dev/null
        chmod 644 "$AS_HMA_CONF" 2>/dev/null || :

        # Generate HMA status.json (oss-177 standard: workMode 1 = Active)
        _status_json='{"version": 177, "workMode": 1}'
        echo "$_status_json" > "$AS_DIR/status.json" 2>/dev/null || :
        chmod 644 "$AS_DIR/status.json" 2>/dev/null || :

        # Sync to any HMA service directories on device
        for d in /data/misc/hide_my_applist_* /data/system/hide_my_applist_*; do
            if [ -d "$d" ]; then
                cp -f "$AS_HMA_CONF" "$d/config.json" 2>/dev/null || :
                chmod 666 "$d/config.json" 2>/dev/null || :
                echo "$_status_json" > "$d/status.json" 2>/dev/null || :
                chmod 666 "$d/status.json" 2>/dev/null || :
            fi
        done
        # Ensure default HMA service directory exists
        if ! ls -d /data/misc/hide_my_applist_* >/dev/null 2>&1; then
            mkdir -p /data/misc/hide_my_applist_alwaysstrong 2>/dev/null || :
            chmod 777 /data/misc/hide_my_applist_alwaysstrong 2>/dev/null || :
            cp -f "$AS_HMA_CONF" /data/misc/hide_my_applist_alwaysstrong/config.json 2>/dev/null || :
            chmod 666 /data/misc/hide_my_applist_alwaysstrong/config.json 2>/dev/null || :
            echo "$_status_json" > /data/misc/hide_my_applist_alwaysstrong/status.json 2>/dev/null || :
            chmod 666 /data/misc/hide_my_applist_alwaysstrong/status.json 2>/dev/null || :
        fi
    else
        rm -f "$_tmp_json" 2>/dev/null || :
    fi

    # Trigger mount namespace isolation for active target apps
    isolate_mounts "$target_file"
}

# KernelSU/APatch Mount Namespace Isolation for target apps
isolate_mounts() {
    target_file="${1:-$TGT}"
    [ -f "$target_file" ] || return 0

    _targets=$(sed 's/[[:space:]]//g' "$target_file" 2>/dev/null | grep -vE '^(#|\[|$)' | sed 's/[!?]*$//' | sort -u)
    [ -n "$_targets" ] || return 0

    _root_mounts="/data/adb /data/adb/modules /data/adb/modules_update /debug_ramdisk /sbin"

    for pkg in $_targets; do
        for pid in $(pidof "$pkg" 2>/dev/null); do
            [ -d "/proc/$pid" ] || continue
            if grep -qE "(/data/adb|/debug_ramdisk|magisk|kernelsu|apatch)" "/proc/$pid/mountinfo" 2>/dev/null; then
                for mnt in $_root_mounts; do
                    if grep -q " $mnt " "/proc/$pid/mountinfo" 2>/dev/null; then
                        nsenter -t "$pid" -m -- umount -l "$mnt" 2>/dev/null || :
                    fi
                done
            fi
        done
    done
}

case "$1" in
    get_hidden|get)
        get_hidden
        ;;
    get_granted|granted)
        get_granted_root_apps
        ;;
    init_defaults|init)
        init_defaults
        ;;
    isolate)
        shift 2>/dev/null || :
        isolate_mounts "$@"
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
        echo "Usage: $0 {sync|isolate|get|set|toggle|init|granted}"
        exit 1
        ;;
esac
