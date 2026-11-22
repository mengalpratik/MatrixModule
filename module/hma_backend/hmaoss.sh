#!/system/bin/sh

# ref: https://github.com/PerformanC/ReZygisk/blob/main/module/src/rezygisk.sh

set -e

# INFO: This script gets moved to /data/adb/boot-completed.d/hmaoss.sh

# INFO: This script is utilized so that when HMA-OSS is disabled, it still can clean up its
#         module.prop, making it not have traces of its old status.

MODDIR=/data/adb/modules/matrixmodule_hiding_engine
DISABLE="$MODDIR/disable"

if [ ! -f "$DISABLE" ]; then
    (
        sleep 5

        try=1
        while [ "$try" -le 10 ]; do
            STATUS_FILE=$(printf '%s' /data/misc/hide_my_applist_*/status.json)
            [ -n "$STATUS_FILE" ] && [ -s "$STATUS_FILE" ] && break
            sleep 1
            try=$((try + 1))
        done

        [ -f "$MODDIR/update_desc.sh" ] && sh "$MODDIR/update_desc.sh"
    ) &
fi

true
