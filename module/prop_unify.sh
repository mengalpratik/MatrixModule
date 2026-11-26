#!/system/bin/sh
# prop_unify.sh - unify ro.product.* props with the spoofed fingerprint
#
# PlayIntegrityFork spoofs Build.* inside the GMS process, but the
# ro.product.* family (ro.product.manufacturer/model/name/device/brand) stays
# at the real device values in the global property store. Detection apps that
# read those props via getprop - rather than the Build class - can spot the
# mismatch against the spoofed fingerprint. This closes that cross-validation
# gap by resetprop-ing the product family to match the active pif fingerprint.
#
# Opt out: prop_unify=0 in alwaysstrong/config

MODDIR="${MODPATH:-$(dirname "$0")}"
CFG=/data/adb/tricky_store

# Callers pipe our stdout to `log -t AlwaysStrong-unify`, so just echo - a
# log() wrapper that calls `log` would recurse into itself (functions shadow
# same-named commands), not the Android log binary.
log() { echo "$@"; }

[ -f "$MODDIR/as_store.sh" ] && . "$MODDIR/as_store.sh"

# Source of truth: active pif file in module dir first (same order as sync_patch.sh).
PIF=""
for p in "$MODDIR/custom.pif.prop" "$MODDIR/pif.prop" "$CFG/custom.pif.prop" "$CFG/pif.prop"; do
  [ -s "$p" ] && PIF="$p" && break
done

if [ -z "$PIF" ]; then
  log "no pif.prop found under $CFG - skipping prop unification"
  exit 0
fi

# Resetprop helpers - use '-n' to avoid triggering property triggers
set_prop() {
  local key="$1" val="$2"
  local cur
  cur=$(resetprop "$key" 2>/dev/null)
  [ "$cur" = "$val" ] && return 0
  resetprop -n "$key" "$val" 2>/dev/null
  log "  $key <- $val"
}

del_prop() {
  resetprop --delete "$1" 2>/dev/null
}

log "unifying product props from $PIF"

# Parse pif for FINGERPRINT, explicit override fields, and spoofBuild/spoofProps
FINGERPRINT=""
PRODUCT=""
DEVICE=""
MANUFACTURER=""
BRAND=""
MODEL=""
SECURITY_PATCH=""
SPOOF_BUILD=""
SPOOF_PROPS=""

while IFS='=' read -r key val; do
  val="${val%%$'\r'}"
  case "$key" in
    FINGERPRINT)     FINGERPRINT="$val" ;;
    PRODUCT)         PRODUCT="$val" ;;
    DEVICE)          DEVICE="$val" ;;
    MANUFACTURER)    MANUFACTURER="$val" ;;
    BRAND)           BRAND="$val" ;;
    MODEL)           MODEL="$val" ;;
    SECURITY_PATCH)  SECURITY_PATCH="$val" ;;
    DEVICE_INITIAL_SDK_INT) DEVICE_INITIAL_SDK_INT="$val" ;;
    spoofBuild)      SPOOF_BUILD="$val" ;;
    spoofProps)      SPOOF_PROPS="$val" ;;
  esac
done < "$PIF"

# Check spoof.conf overrides if present
for sc in "$CFG/alwaysstrong/spoof.conf" "$CFG/spoof.conf"; do
  [ -s "$sc" ] || continue
  _sb=$(sed -n 's/^spoofBuild=//p' "$sc" 2>/dev/null | head -1 | tr -d ' \t\r')
  _sp=$(sed -n 's/^spoofProps=//p' "$sc" 2>/dev/null | head -1 | tr -d ' \t\r')
  [ -n "$_sb" ] && SPOOF_BUILD="$_sb"
  [ -n "$_sp" ] && SPOOF_PROPS="$_sp"
  break
done

is_flag_on() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    0|false|off|no) return 1 ;;
    *) return 0 ;;
  esac
}

# Snapshot real device props once per boot (in tmpfs /dev) before unifying so
# toggling spoofBuild / spoofProps OFF live can restore the real identity.
ORIG_FILE=/dev/.matrix_orig_props
if [ ! -f "$ORIG_FILE" ]; then
  : > "$ORIG_FILE"
  chmod 600 "$ORIG_FILE" 2>/dev/null
  for _k in \
    ro.product.manufacturer ro.product.brand ro.product.name ro.product.device ro.product.model \
    ro.product.system.manufacturer ro.product.system.brand ro.product.system.name ro.product.system.device ro.product.system.model \
    ro.build.product ro.build.description ro.build.tags ro.build.type ro.system.build.tags ro.system.build.type \
    ro.build.fingerprint ro.bootimage.build.fingerprint ro.product.first_api_level ro.board.first_api_level; do
    _v=$(resetprop "$_k" 2>/dev/null)
    [ -n "$_v" ] && printf '%s=%s\n' "$_k" "$_v" >> "$ORIG_FILE"
  done
  for part in system vendor product system_ext odm boot vendor_dlkm odm_dlkm; do
    for _k in "ro.$part.build.fingerprint" "ro.build.$part.fingerprint" "ro.$part.build.tags" "ro.$part.build.type"; do
      _v=$(resetprop "$_k" 2>/dev/null)
      [ -n "$_v" ] && printf '%s=%s\n' "$_k" "$_v" >> "$ORIG_FILE"
    done
  done
  for part in odm vendor product system_ext vendor_dlkm odm_dlkm; do
    for field in model brand manufacturer device name; do
      _k="ro.product.$part.$field"
      _v=$(resetprop "$_k" 2>/dev/null)
      [ -n "$_v" ] && printf '%s=%s\n' "$_k" "$_v" >> "$ORIG_FILE"
    done
  done
fi

restore_prop() {
  _rk="$1"
  [ -f "$ORIG_FILE" ] || return 0
  _rv=$(grep -m1 "^${_rk}=" "$ORIG_FILE" 2>/dev/null | cut -d= -f2-)
  [ -n "$_rv" ] && set_prop "$_rk" "$_rv"
}

# Derive brand/product/device from the fingerprint when not overridden.
# Format: brand/product/device:build_type/release/id/incremental:tags/keys
if [ -n "$FINGERPRINT" ]; then
  FP_BRAND="${FINGERPRINT%%/*}"
  AFTER_BRAND="${FINGERPRINT#*/}"
  FP_PRODUCT="${AFTER_BRAND%%/*}"
  AFTER_PRODUCT="${AFTER_BRAND#*/}"
  FP_DEVICE_TMP="${AFTER_PRODUCT%%:*}"
  FP_DEVICE="${FP_DEVICE_TMP%%/*}"

  FP_BUILD_TYPE="user"
  case "$FINGERPRINT" in
    *:userdebug/*) FP_BUILD_TYPE="userdebug" ;;
    *:eng/*)       FP_BUILD_TYPE="eng" ;;
  esac

  [ -n "$DEVICE" ]  && FP_DEVICE="$DEVICE"
  [ -n "$PRODUCT" ] && FP_PRODUCT="$PRODUCT"
  [ -n "$BRAND" ]   && FP_BRAND="$BRAND"

  log "fingerprint -> brand=$FP_BRAND product=$FP_PRODUCT device=$FP_DEVICE (spoofBuild=${SPOOF_BUILD:-1} spoofProps=${SPOOF_PROPS:-1})"

  if is_flag_on "$SPOOF_PROPS"; then
    # Manufacturer first, so it isn't clobbered by the lowercase brand.
    if [ -n "$MANUFACTURER" ]; then
      set_prop ro.product.manufacturer "$MANUFACTURER"
      set_prop ro.product.system.manufacturer "$MANUFACTURER"
    elif [ -n "$FP_BRAND" ]; then
      set_prop ro.product.manufacturer "$FP_BRAND"
      set_prop ro.product.system.manufacturer "$FP_BRAND"
    fi

    [ -n "$FP_BRAND" ] && {
      set_prop ro.product.brand "$FP_BRAND"
      set_prop ro.product.system.brand "$FP_BRAND"
    }

    [ -n "$FP_PRODUCT" ] && {
      set_prop ro.product.name "$FP_PRODUCT"
      set_prop ro.product.system.name "$FP_PRODUCT"
      set_prop ro.product.device "$FP_PRODUCT"
      set_prop ro.product.system.device "$FP_PRODUCT"
      set_prop ro.build.product "$FP_PRODUCT"
    }

    [ -n "$FP_DEVICE" ] && [ "$FP_DEVICE" != "$FP_PRODUCT" ] && {
      set_prop ro.product.device "$FP_DEVICE"
      set_prop ro.product.system.device "$FP_DEVICE"
    }

    if [ -n "$MODEL" ]; then
      set_prop ro.product.model "$MODEL"
      set_prop ro.product.system.model "$MODEL"
    fi

    # Scrub OEM-specific product props that would leak the real device.
    for part in odm vendor product system_ext vendor_dlkm odm_dlkm; do
      for field in model brand manufacturer device name; do
        del_prop "ro.product.$part.$field"
      done
    done
  else
    log "spoofProps is OFF - restoring real product props"
    for _k in \
      ro.product.manufacturer ro.product.brand ro.product.name ro.product.device ro.product.model \
      ro.product.system.manufacturer ro.product.system.brand ro.product.system.name ro.product.system.device ro.product.system.model \
      ro.build.product; do
      restore_prop "$_k"
    done
    for part in odm vendor product system_ext vendor_dlkm odm_dlkm; do
      for field in model brand manufacturer device name; do
        restore_prop "ro.product.$part.$field"
      done
    done
  fi

  if [ -n "$SECURITY_PATCH" ] && command -v as_on >/dev/null 2>&1 && as_on spoof_patch_props; then
    set_prop ro.build.version.security_patch "$SECURITY_PATCH"
    set_prop ro.vendor.build.security_patch "$SECURITY_PATCH"
    set_prop ro.build.version.real_security_patch "$SECURITY_PATCH"
  fi

  if is_flag_on "$SPOOF_BUILD"; then
    # ro.build.description - reconstruct from fingerprint fields.
    REST="${FINGERPRINT#*:}"          # release/id/incremental:type/tags
    FP_RELEASE="${REST%%/*}"          # release (e.g. 15 or CANARY)
    REST2="${REST#*/}"                # id/incremental:type/tags
    FP_ID="${REST2%%/*}"              # build id (e.g. ZP11.260618.005)
    REST3="${REST2#*/}"               # incremental:type/tags
    FP_INCREMENTAL="${REST3%%:*}"     # incremental (e.g. 15760424)
    TYPETAGS="${REST3#*:}"            # type/tags (e.g. user/release-keys)
    FP_TAGS="${TYPETAGS#*/}"          # tags (release-keys)
    [ "$FP_TAGS" = "$TYPETAGS" ] && FP_TAGS="release-keys"

    BUILD_DESC="${FP_PRODUCT}-${FP_BUILD_TYPE} ${FP_RELEASE} ${FP_ID} ${FP_INCREMENTAL} ${FP_TAGS}"
    set_prop ro.build.description "$BUILD_DESC"
    set_prop ro.build.tags "${FP_TAGS:-release-keys}"
    set_prop ro.build.type "${FP_BUILD_TYPE:-user}"
    set_prop ro.system.build.tags "${FP_TAGS:-release-keys}"
    set_prop ro.system.build.type "${FP_BUILD_TYPE:-user}"

    # Unify partition fingerprints and base build fingerprint
    set_prop ro.build.fingerprint "$FINGERPRINT"
    set_prop ro.bootimage.build.fingerprint "$FINGERPRINT"
    for part in system vendor product system_ext odm boot vendor_dlkm odm_dlkm; do
      set_prop "ro.$part.build.fingerprint" "$FINGERPRINT"
      set_prop "ro.build.$part.fingerprint" "$FINGERPRINT"
    done

    [ -n "$DEVICE_INITIAL_SDK_INT" ] && {
      set_prop ro.product.first_api_level "$DEVICE_INITIAL_SDK_INT"
      set_prop ro.board.first_api_level "$DEVICE_INITIAL_SDK_INT"
    }

    for part in vendor product system_ext odm; do
      set_prop "ro.$part.build.tags" "${FP_TAGS:-release-keys}"
      set_prop "ro.$part.build.type" "${FP_BUILD_TYPE:-user}"
    done
  else
    log "spoofBuild is OFF - restoring real build props"
    for _k in ro.build.description ro.build.tags ro.build.type ro.system.build.tags ro.system.build.type \
              ro.build.fingerprint ro.bootimage.build.fingerprint ro.product.first_api_level ro.board.first_api_level; do
      restore_prop "$_k"
    done
    for part in system vendor product system_ext odm boot vendor_dlkm odm_dlkm; do
      restore_prop "ro.$part.build.fingerprint"
      restore_prop "ro.build.$part.fingerprint"
    done
    for part in vendor product system_ext odm; do
      restore_prop "ro.$part.build.tags"
      restore_prop "ro.$part.build.type"
    done
  fi

  # Strict Security Property Locking (Yurikey & Integrity-Box pattern)
  set_prop ro.debuggable 0
  set_prop ro.force.debuggable 0
  set_prop ro.secure 1
  set_prop ro.adb.secure 1
  set_prop sys.oem_unlock_allowed 0
  set_prop ro.boot.vbmeta.device_state locked
  set_prop vendor.boot.vbmeta.device_state locked
  set_prop ro.boot.verifiedbootstate green
  set_prop vendor.boot.verifiedbootstate green
  set_prop ro.boot.flash.locked 1
  set_prop ro.secureboot.lockstate locked
  set_prop ro.boot.veritymode enforcing
  set_prop vendor.boot.veritymode enforcing
fi

log "prop unification complete"
