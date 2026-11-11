#!/system/bin/sh
# MatrixModule uninstall — clean every artifact we created.

MODDIR=${0%/*}
CONFIG_DIR=/data/adb/tricky_store

# Kill all running module processes (both attestation engines)
for proc in TEESimulator supervisor daemon TrickyStoreOSS; do
    for pid in $(pidof "$proc" 2>/dev/null); do
        kill -9 "$pid" 2>/dev/null
    done
done
pkill -9 -f TEESimulator 2>/dev/null || true
pkill -9 -f org.matrix.TEESimulator 2>/dev/null || true
pkill -9 -f io.github.beakthoven.TrickyStoreOSS 2>/dev/null || true

# Kill GMS + Vending so they reload without our hooks
if [ -f "$MODDIR/as_store.sh" ]; then
    . "$MODDIR/as_store.sh" 2>/dev/null && as_killpi
else
    am force-stop com.android.vending >/dev/null 2>&1
    am kill com.google.android.gms >/dev/null 2>&1
    killall -9 com.google.android.gms.unstable com.android.vending com.android.vending:background com.android.vending:quick_launch >/dev/null 2>&1
fi

# Remove the DenyList entries we added (entries only, never the enforcement
# toggle). Only on Magisk; rm by package drops all of that package's processes.
if command -v magisk >/dev/null 2>&1; then
    for p in com.android.vending com.google.android.gms com.google.android.gsf \
             com.google.android.gm com.anu.developers3k.rootchecker \
             gr.nikolasspyr.integritycheck io.github.vvb2060.keyattestation; do
        magisk --denylist rm "$p" >/dev/null 2>&1
    done
fi

# Our settings, state and logs
rm -rf /data/adb/tricky_store/alwaysstrong
rm -rf /data/adb/modules/tricky_store/temp 2>/dev/null
rm -rf /data/adb/modules/hma_oss_zygisk 2>/dev/null || :
rm -rf /data/misc/hide_my_applist_* 2>/dev/null || :


# Wipe TEESimulator runtime state
rm -rf /data/adb/tricky_store/persistent_keys
rm -f /data/adb/tricky_store/tee_status.txt
rm -f /data/adb/tricky_store/boot_hash.bin /data/adb/tricky_store/boot_key.bin

# JingMatrix TEESimulator data dir: drop the config, the root-of-trust override
# and the harvested record we generated so a reinstall (or a switch to another
# engine) starts clean and re-harvests instead of reusing a stale zeroed key.
# keybox.xml there is a symlink into tricky_store and is left alone.
rm -f /data/adb/teesim/config.json /data/adb/teesim/overrides.json \
      /data/adb/teesim/harvested.json 2>/dev/null

# Global PIF prop we dropped for the TEE PatchLevelManager (sync_patch.sh)
rm -f /data/adb/pif.prop

# Restore ROM-level spoof engines that rom_spoof_block.sh disabled, so removing
# AlwaysStrong frees the ROM's own PixelProps / pihooks / entryhooks again.
# Only clear a prop if it STILL holds the exact "disabled" value we wrote — that
# way we never clobber a value the ROM set for itself. Takes effect next boot.
revert_spoof() {
    [ "$(resetprop "$1" 2>/dev/null)" = "$2" ] && resetprop -p --delete "$1" 2>/dev/null
}
revert_spoof persist.sys.pihooks.disable.gms_props                 true
revert_spoof persist.sys.pihooks.disable.gms_key_attestation_block true
revert_spoof persist.sys.entryhooks_enabled                        false
revert_spoof persist.sys.spoof.gms                                 false
revert_spoof persist.sys.pixelprops.gms                            false
revert_spoof persist.sys.pixelprops.gapps                          false
revert_spoof persist.sys.pixelprops.google                         false
revert_spoof persist.sys.pixelprops.pi                             false
revert_spoof persist.sys.pp.gms                                    false
revert_spoof persist.sys.pp.finsky                                 false
revert_spoof persist.sys.pihooks.first_api_level                   ""
revert_spoof persist.sys.pihooks.security_patch                    ""

# Keep keybox.xml and security_patch.txt — user may want them for reinstall.
