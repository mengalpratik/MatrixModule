#!/system/bin/sh

# If you run this by hand, please use ./update_desc.sh or use full path
#  instead of 'sh update_desc.sh' after cd
MODDIR="${0%/*}"

BASE_DESC="Dedicated App Isolation & Banking Protection Engine for MatrixModule."

STATUS_FILE=""
for _sf in /data/misc/hide_my_applist_*/status.json; do
    [ -s "$_sf" ] && { STATUS_FILE="$_sf"; break; }
done

echo "Status file: $STATUS_FILE"

if [ -z "$STATUS_FILE" ] || [ ! -s "$STATUS_FILE" ]; then
    MODE="0"
else
    MODE=$(grep -o '"workMode"[[:space:]]*:[[:space:]]*[0-9]*' "$STATUS_FILE" 2>/dev/null | grep -o '[0-9]*$')
fi

case "$MODE" in
    1) STATUS="[Matrix Engine is Online]" ;;
    2) STATUS="[[!] Sick mode - Disabled hooks]" ;;
    3) STATUS="[[*] Loading]" ;;
    4) STATUS="[[-] System service crashed]"  ;;
    *) STATUS="[[?] Unknown]" ;;
esac

echo "Detected status: $STATUS"

NEW_DESC="$STATUS $BASE_DESC"
SAFE_DESC=$(echo "$NEW_DESC" | sed 's/[&/]/\\&/g')
sed -i "s|^description=.*|description=$SAFE_DESC|" "$MODDIR/module.prop"
