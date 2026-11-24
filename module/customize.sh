# shellcheck shell=sh
# shellcheck disable=SC2034
SKIPUNZIP=1
MIN_SDK=29
CONFIG_DIR=/data/adb/tricky_store

if [ "$BOOTMODE" != true ]; then
  abort "install from a root manager, not recovery"
fi
if [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
  abort "please update KernelSU + manager first"
fi

case "$ARCH" in
  arm64) ABI_DIR="arm64-v8a" ;;
  arm)   ABI_DIR="armeabi-v7a" ;;
  x64)   ABI_DIR="x86_64" ;;
  x86)   ABI_DIR="x86" ;;
  *)     abort "unsupported arch: $ARCH" ;;
esac

[ "$API" -lt "$MIN_SDK" ] && abort "needs Android 10+ (SDK $MIN_SDK)"

VERSION=$(grep_prop version "${TMPDIR}/module.prop")
# read the name from module.prop so the -inject build shows "[inject]" here too
NAME=$(grep_prop name "${TMPDIR}/module.prop")
install_file() { unzip -qqjo "$ZIPFILE" "$1" -d "$2" || abort "extract failed: $1"; }

ui_print "${NAME:-MatrixModule} $VERSION"
ui_print "by Pratik Mengal"
ui_print "Copyright (c) 2026 Pratik Mengal. All rights reserved."
ui_print ""

# stop anything that might be holding our lib files (upgrade-in-place). The
# list is a superset across both engines — killing an absent process is a no-op.
for proc in TEESimulator supervisor daemon ta-enhanced TrickyStoreOSS cleverestricky aswatcher; do
  for pid in $(pidof "$proc" 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done
done
pkill -9 -f TEESimulator 2>/dev/null || true

# --- deep legacy directories & IPC wipe ---
for legacy_dir in /data/adb/cleverestricky /data/adb/matrix_module; do
  [ -d "$legacy_dir" ] && rm -rf "$legacy_dir" 2>/dev/null || :
done
# Wipe stale FIFO pipes (.native_runtime.pipe.*)
for p in /data/adb /data/adb/* /data/adb/modules/* /dev /dev/socket /data/local/tmp; do
  for pipe in "$p"/.native_runtime.pipe.*; do
    [ -e "$pipe" ] && rm -f "$pipe" 2>/dev/null || :
  done
done
# Wipe stale sockets (admin.sock)
for s in /data/adb/admin.sock /data/adb/*/admin.sock /dev/socket/admin.sock /data/local/tmp/admin.sock; do
  [ -e "$s" ] && rm -f "$s" 2>/dev/null || :
done
# Wipe stale PID files
for pidfile in /data/adb/*.pid /data/adb/*/*.pid /data/adb/tricky_store/*.pid /data/adb/tricky_store/alwaysstrong/tmp/*.pid; do
  [ -f "$pidfile" ] && rm -f "$pidfile" 2>/dev/null || :
done

# --- conflict cleanup ----------------------------------------------------
# Keystore / TEE / target-list / prop modules always conflict with the
# attestation engine. The PIF-family (Build spoof) only conflicts with a line
# that bundles its own PlayIntegrityFork — the PIF-less "Lite" line ships none and
# is meant to run alongside the user's own PIF, so Lite does NOT remove them.
CONFLICT_LIST="tricky_store_v2 TrickyStore \
  tee_simulator TEESimulator TEESimulator-RS \
  safetynet-fix Universal_SafetyNet_Fix \
  MagiskHidePropsConf \
  TA_utl tricky_addon TA_enhanced tsupport-advance \
  Yurikey specter"
case "$NAME" in
  *"[Lite]"*) ui_print "- Lite build — keeping any standalone PlayIntegrityFork" ;;
  *) CONFLICT_LIST="$CONFLICT_LIST playintegrityfix playintegrityfork play_integrity_fix playcurl playcurlNEXT pif_strong pif_force" ;;
esac
CONFLICTS=0
for c in $CONFLICT_LIST ; do
  cp_dir="/data/adb/modules/$c"
  if [ -d "$cp_dir" ] && [ "$(basename "$cp_dir")" != "$(basename "$MODPATH")" ]; then
    CONFLICTS=$((CONFLICTS+1))
    [ -f "$cp_dir/uninstall.sh" ] && sh "$cp_dir/uninstall.sh" 2>/dev/null || true
    touch "$cp_dir/disable" "$cp_dir/remove" 2>/dev/null || :
  fi
  [ -d "/data/adb/modules_update/$c" ] && touch "/data/adb/modules_update/$c/remove" 2>/dev/null || :
done
# A full keystore/attestation toolkit (author MeowDump) ships under the SAME id as
# osm0sis PlayIntegrityFork (playintegrityfix). The Lite line keeps the plain Fork
# but must still drop that toolkit (it fights the engine), told apart by module.prop.
_ib=/data/adb/modules/playintegrityfix
if [ -d "$_ib" ] && [ "$(basename "$_ib")" != "$(basename "$MODPATH")" ] \
   && grep -qiE 'MeowDump|webuiIcon|ntegrity.?[Bb]ox' "$_ib/module.prop" 2>/dev/null; then
  CONFLICTS=$((CONFLICTS+1))
  [ -f "$_ib/uninstall.sh" ] && sh "$_ib/uninstall.sh" 2>/dev/null || true
  touch "$_ib/disable" "$_ib/remove" 2>/dev/null || :
  ui_print "- removed a conflicting keystore module (playintegrityfix id)"
fi
if [ $CONFLICTS -eq 0 ]; then
  ui_print "no conflicting modules"
else
  ui_print "removed $CONFLICTS conflicting module(s)"
fi

# --- extract our scripts + configs ---------------------------------------
# engine.sh first: it names the upstream files this build's Play Integrity
# engine needs ($ENGINE_FILES). Everything else here is engine-neutral.
install_file "engine.sh" "$MODPATH"
# shellcheck source=/dev/null
. "$MODPATH/engine.sh"

for f in module.prop service.sh post-fs-data.sh action.sh \
         uninstall.sh common_func.sh as_store.sh sepolicy.rule \
         keybox_fetch.sh build_target_txt.sh status_fetch.sh description.txt \
         rom_spoof_block.sh conflict_scan.sh sync_patch.sh patch_resolve.sh beta_pif.sh \
         denylist.sh hma_sync.sh \
         pif_native_fetch.sh prop_unify.sh logcat_cleanup.sh collect_logs.sh \
         import_pif.sh reapply_spoof.sh reset_defaults.sh \
         pif_fallback_1.prop pif_fallback_2.prop \
         target.txt daemon \
         $ENGINE_FILES ; do
  install_file "$f" "$MODPATH"
done

# lite_pif_sync.sh is only used on the Lite line (ENGINE=none), where the user's
# own standalone PIF provides the fingerprint/spoof flags. The Fork/inject lines
# bundle their own engine and never call it, so it ships in the Lite zip only.
[ "$ENGINE" = none ] && install_file "lite_pif_sync.sh" "$MODPATH"

# module banner shown by the root manager (module.prop -> banner=.../banner.png)
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "^.*banner\.png"; then
  install_file "banner.png" "$MODPATH"
  chmod 644 "$MODPATH/banner.png" 2>/dev/null
fi

# --- attestation engine (TEESimulator-RS | TrickyStoreOSS) ----------------
# The per-engine install steps live in attest.sh, which build.sh generates from
# attest/<engine>.sh. It runs with $ABI_DIR / $ARCH / $ZIPFILE / $MODPATH and
# install_file() + ui_print() in scope, and installs that engine's binaries.
install_file "attest.sh" "$MODPATH"
# shellcheck source=/dev/null
. "$MODPATH/attest.sh"
attest_install

# --- PIF zygisk + dex ----------------------------------------------------
# Ship whatever ABIs upstream built. PlayIntegrityFork covers all four;
# PlayIntegrityFix inject-s is ARM-only, so on x86 that build has no zygisk to
# install — the TEE half still runs, the Play Integrity spoof can't, and the
# install says so rather than half-working in silence.
#
# A PIF-less "Lite" line (engine.sh sets ENGINE=none) ships no zygisk and no
# classes.dex at all — only the TEE/TSOSS attestation + keybox fetcher. Skip the
# whole Play Integrity install for it.
if [ "$ENGINE" = "none" ]; then
  ui_print "PIF-less build — hardware attestation + keybox only"
  ui_print "no Play Integrity fingerprint spoof in this build"
else
mkdir -p "$MODPATH/zygisk"
ZN=0
for z in arm64-v8a armeabi-v7a x86 x86_64; do
  if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "zygisk/$z.so"; then
    unzip -qqjo "$ZIPFILE" "zygisk/$z.so" -d "$MODPATH/zygisk" 2>/dev/null
    ZN=$((ZN+1))
  fi
done
install_file "classes.dex" "$MODPATH"

HAS_ZYGISK_SO=0
[ -f "$MODPATH/zygisk/$ABI_DIR.so" ] && HAS_ZYGISK_SO=1

if [ $HAS_ZYGISK_SO -eq 0 ]; then
  ui_print "⚠️ no PIF zygisk for $ABI_DIR ($ENGINE_NAME is ARM-only)"
  ui_print "⚠️ TEE works, Play Integrity spoof won't"
  ui_print "⚠️ use the default build for $ABI_DIR"
# --- Zygisk provider check — PIF's zygisk needs a Zygisk host --------------
# The common silent-failure setup is Zygisk-less KernelSU: KSU has NO built-in
# Zygisk, so without ZygiskNext / ReZygisk the PIF spoof never loads and STRONG
# quietly fails. Magisk / APatch ship (or host) Zygisk themselves. Warn only on
# the real footgun to avoid false alarms.
elif [ "$KSU" = "true" ]; then
  _zygisk_active=0
  for _zmod in zygisksu rezygisk neozygisk; do
    if [ -d "/data/adb/modules/$_zmod" ] && [ ! -f "/data/adb/modules/$_zmod/disable" ]; then
      _zygisk_active=1
      break
    fi
  done
  if [ $_zygisk_active -eq 0 ]; then
    ui_print "****************************************************"
    ui_print "⚠️  WARNING: Zygisk Next is MISSING or DISABLED!   ⚠️"
    ui_print "⚠️  KernelSU requires active Zygisk Next (zygisksu)⚠️"
    ui_print "⚠️  Without it, PIF spoofing and STRONG will fail! ⚠️"
    ui_print "****************************************************"
  else
    ui_print "zygisk found"
  fi
fi
fi

# --- aswatcher native binary (inotify target.txt + Xposed exclude + conflict)
mkdir -p "$MODPATH/bin/$ABI_DIR"
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "bin/$ABI_DIR/aswatcher"; then
  install_file "bin/$ABI_DIR/aswatcher" "$MODPATH/bin/$ABI_DIR"
  chmod 755 "$MODPATH/bin/$ABI_DIR/aswatcher"
else
  ui_print "warning: no aswatcher binary for $ABI_DIR"
fi

# --- asfetch native HTTPS fetcher (arm devices only; TLS fallback for CDNs)
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "bin/$ABI_DIR/asfetch"; then
  install_file "bin/$ABI_DIR/asfetch" "$MODPATH/bin/$ABI_DIR"
  chmod 755 "$MODPATH/bin/$ABI_DIR/asfetch"
fi

chmod 755 "$MODPATH/daemon" "$MODPATH/supervisor" "$MODPATH/inject" \
          "$MODPATH"/*.sh 2>/dev/null

# --- WebUI (KSU / APatch / MMRL) — single self-contained index.html
mkdir -p "$MODPATH/webroot"
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "webroot/index.html"; then
  install_file "webroot/index.html" "$MODPATH/webroot"
  chmod 644 "$MODPATH/webroot/index.html"
  if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "webroot/main.js"; then
    install_file "webroot/main.js" "$MODPATH/webroot"
    chmod 644 "$MODPATH/webroot/main.js"
  fi
  if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "webroot/app.css"; then
    install_file "webroot/app.css" "$MODPATH/webroot"
    chmod 644 "$MODPATH/webroot/app.css"
  fi
  # Magisk has no built-in WebUI host. The standalone WebUI app is fetched
  # from GitHub and installed on the first [Action] press (see action.sh).
  if [ "$KSU" != true ] && [ "$APATCH" != true ]; then
    ui_print "WebUI: app downloads + installs on first Action tap"
  fi
else
  ui_print "warning: WebUI index.html missing from package"
fi

# --- /data/adb/tricky_store config ----------------------------------------
mkdir -p "$CONFIG_DIR"

# Everything of OURS (settings, state, logs) goes under one directory there;
# import it now so an upgrade from the old one-file-per-toggle layout keeps
# every setting, instead of silently reverting to defaults on first boot.
if [ -f "$MODPATH/as_store.sh" ]; then
  sh "$MODPATH/as_store.sh" migrate 2>/dev/null
  ui_print "settings: $CONFIG_DIR/alwaysstrong/"
fi
if [ -f "$CONFIG_DIR/keybox.xml" ]; then
  ui_print "keybox kept ($(wc -c < "$CONFIG_DIR/keybox.xml") bytes)"
else
  install_file "keybox.xml" "$CONFIG_DIR"
  chmod 600 "$CONFIG_DIR/keybox.xml" 2>/dev/null || :
  ui_print "✅ default working keybox seeded (offline STRONG ready)"
fi

# Restore an imported / beta fingerprint that this reinstall just wiped. On Fork
# and inject-s the active pif lives in the module dir, which was re-extracted
# empty; import_pif.sh keeps a persistent source copy at
# $CONFIG_DIR/custom.pif.prop. If the user had a custom pif (custom_pif=1) and
# that copy is present, re-install it into the fresh module dir now — otherwise
# the update strands the device with custom_pif=1 and no spoof identity, and
# STRONG silently drops to whatever Fork's own boot autopif fetches. No-op on
# Lite (ENGINE=none already keeps its pif under CONFIG_DIR) and when the user
# was on the automatic fingerprint. engine.sh is sourced above.
if [ "${ENGINE:-none}" != "none" ] && [ -s "$CONFIG_DIR/custom.pif.prop" ] && \
   grep -q '^custom_pif=1' "$CONFIG_DIR/alwaysstrong/config" 2>/dev/null; then
  if engine_install_pif "$CONFIG_DIR/custom.pif.prop" 2>/dev/null; then
    ui_print "imported fingerprint restored"
  fi
fi

# --- Deploy Bundled HMA Zygisk Hook Engine (MatrixModule - Hiding Engine) ---
HMA_MODDIR="/data/adb/modules/matrixmodule_hiding_engine"
rm -rf /data/adb/modules/hma_oss_zygisk 2>/dev/null || :
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "hma_backend/"; then
  ui_print "Deploying MatrixModule Hiding Engine..."
  mkdir -p "$HMA_MODDIR/zygisk" "$HMA_MODDIR/packages" 2>/dev/null
  unzip -qqjo "$ZIPFILE" "hma_backend/classes.dex" -d "$HMA_MODDIR" 2>/dev/null || :
  if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "hma_backend/module.prop.engine"; then
    unzip -qqjo "$ZIPFILE" "hma_backend/module.prop.engine" -d "$HMA_MODDIR" 2>/dev/null || :
    [ -f "$HMA_MODDIR/module.prop.engine" ] && mv -f "$HMA_MODDIR/module.prop.engine" "$HMA_MODDIR/module.prop"
  else
    unzip -qqjo "$ZIPFILE" "hma_backend/module.prop" -d "$HMA_MODDIR" 2>/dev/null || :
  fi
  unzip -qqjo "$ZIPFILE" "hma_backend/update_desc.sh" -d "$HMA_MODDIR" 2>/dev/null || :
  unzip -qqjo "$ZIPFILE" "hma_backend/hmaoss.sh" -d "$HMA_MODDIR" 2>/dev/null || :
  unzip -qqjo "$ZIPFILE" "hma_backend/uninstall.sh" -d "$HMA_MODDIR" 2>/dev/null || :
  touch "$HMA_MODDIR/packages/android"
  
  # Deploy Signature Banner Image for card background (reuse single root banner)
  if [ -f "$MODPATH/banner.png" ]; then
    cp -f "$MODPATH/banner.png" "$HMA_MODDIR/banner.png" 2>/dev/null || :
  elif unzip -l "$ZIPFILE" 2>/dev/null | grep -q "^banner.png"; then
    unzip -qqjo "$ZIPFILE" "banner.png" -d "$HMA_MODDIR" 2>/dev/null || :
  fi
  chmod 644 "$HMA_MODDIR/banner.png" 2>/dev/null || :
  
  # Remove leftover apk/action files or orphan update flags
  rm -f "$HMA_MODDIR/manager.apk" "$HMA_MODDIR/action.sh" "$HMA_MODDIR/action.sh.bak" "$HMA_MODDIR/module.prop.bak" "$HMA_MODDIR/update" 2>/dev/null || :

  # Zygisk libs
  unzip -qqjo "$ZIPFILE" "hma_backend/zygisk/$ABI_DIR.so" -d "$HMA_MODDIR/zygisk" 2>/dev/null || :
  unzip -qqjo "$ZIPFILE" "hma_backend/zygisk/arm64-v8a.so" -d "$HMA_MODDIR/zygisk" 2>/dev/null || :
  unzip -qqjo "$ZIPFILE" "hma_backend/zygisk/armeabi-v7a.so" -d "$HMA_MODDIR/zygisk" 2>/dev/null || :
  
  chmod 755 "$HMA_MODDIR" "$HMA_MODDIR/zygisk" "$HMA_MODDIR/packages"
  chmod 755 "$HMA_MODDIR"/*.sh 2>/dev/null || :
  chmod 644 "$HMA_MODDIR/classes.dex" "$HMA_MODDIR/module.prop" "$HMA_MODDIR/zygisk"/*.so 2>/dev/null || :
  chmod 644 "$HMA_MODDIR/packages/android" 2>/dev/null || :

  # Enforce SELinux contexts for the sub-module directory so Zygote doesn't crash
  chcon -R u:object_r:system_file:s0 "$HMA_MODDIR" 2>/dev/null || :
  chcon -R u:object_r:system_lib_file:s0 "$HMA_MODDIR/zygisk" 2>/dev/null || :
  rm -f "$HMA_MODDIR/disable" "$HMA_MODDIR/remove" 2>/dev/null || :

  # Setup boot-completed hook
  mkdir -p /data/adb/boot-completed.d 2>/dev/null || :
  cp -f "$HMA_MODDIR/hmaoss.sh" /data/adb/boot-completed.d/hmaoss.sh 2>/dev/null || :
  chmod 755 /data/adb/boot-completed.d/hmaoss.sh 2>/dev/null || :

  # Ensure default HMA service directory exists
  mkdir -p /data/misc/hide_my_applist_alwaysstrong 2>/dev/null || :
  chmod 777 /data/misc/hide_my_applist_alwaysstrong 2>/dev/null || :

  # Ensure redundant standalone HMA manager APK is uninstalled
  if pm path org.frknkrc44.hma_oss >/dev/null 2>&1; then
    pm uninstall org.frknkrc44.hma_oss >/dev/null 2>&1 || :
  fi

  # Initialize description
  [ -f "$HMA_MODDIR/update_desc.sh" ] && sh "$HMA_MODDIR/update_desc.sh" 2>/dev/null || :

  ui_print "✅ MatrixModule - Hiding Engine deployed"

  # Check for latest online HMA engine release if internet is available (with quick timeout)
  if [ -f "$MODPATH/hma_update.sh" ]; then
    chmod 755 "$MODPATH/hma_update.sh" 2>/dev/null || :
    ui_print "Checking for latest online HMA engine..."
    _up_res=$(HMA_MODDIR="$HMA_MODDIR" sh "$MODPATH/hma_update.sh" update 2>/dev/null || true)
    if echo "$_up_res" | grep -q '"updated"'; then
      _new_v=$(echo "$_up_res" | sed -n 's/.*"new_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      ui_print "✅ Online update applied: $_new_v"
    elif echo "$_up_res" | grep -q '"up_to_date"'; then
      ui_print "✅ HMA engine is up to date"
    else
      ui_print "Using bundled offline HMA engine"
    fi
  fi
fi

# target.txt is (re)built on boot (service.sh) and on every [Action] tap — just
# drop a default seed here so TrickyStore has something to read on first boot.
[ -f "$CONFIG_DIR/target.txt" ] || install_file "target.txt" "$CONFIG_DIR"
if [ -f "$MODPATH/hma_sync.sh" ]; then
  sh "$MODPATH/hma_sync.sh" init 2>/dev/null || :
  sh "$MODPATH/hma_sync.sh" sync "$CONFIG_DIR/target.txt" 2>/dev/null || :
  ui_print "✅ HMA hiding architecture initialized"
fi

if [ ! -f "$CONFIG_DIR/hbk" ]; then
  head -c 32 /dev/random > "$CONFIG_DIR/hbk"
  chmod 600 "$CONFIG_DIR/hbk"
fi
rm -f "$CONFIG_DIR/tee_status.txt" "$CONFIG_DIR/tee_status" 2>/dev/null || :

# Unconditionally remove orphan update flag to prevent bogus KernelSU update badge
rm -f "$MODPATH/update" 2>/dev/null || :
_mod_basename=$(basename "$MODPATH")
rm -f "/data/adb/modules/$_mod_basename/update" "/data/adb/modules_update/$_mod_basename/update" 2>/dev/null || :

ui_print ""
ui_print "installed. reboot, then tap [Action] to refresh."
ui_print ""

