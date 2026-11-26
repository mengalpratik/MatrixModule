#!/system/bin/sh

rm -f /data/adb/post-fs-data.d/hmaoss.sh
rm -f /data/adb/post-mount.d/hmaoss.sh
rm -f /data/adb/boot-completed.d/hmaoss.sh

# INFO: Only removes if dir is empty
rmdir /data/adb/post-fs-data.d 2>/dev/null || :
rmdir /data/adb/post-mount.d 2>/dev/null || :
rmdir /data/adb/boot-completed.d 2>/dev/null || :

true
