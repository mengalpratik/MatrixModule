#!/bin/sh
##########################################################################################
# MatrixModule - KernelSU ZIP Packaging Script
##########################################################################################

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${DIST_DIR:-$BASE_DIR/dist}"
MODULE_PROP="$BASE_DIR/module.prop"

if [ ! -f "$MODULE_PROP" ]; then
    echo "! Error: module.prop not found in $BASE_DIR"
    exit 1
fi

VERSION=$(grep "^version=" "$MODULE_PROP" | cut -d= -f2)
[ -z "$VERSION" ] && VERSION="v1.0.0"
ZIP_NAME="MatrixModule-${VERSION}.zip"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$ZIP_NAME"

echo "=========================================="
echo " Packaging: $ZIP_NAME"
echo " Source:    $BASE_DIR"
echo " Output:    $DIST_DIR/$ZIP_NAME"
echo "=========================================="

# Security & Permission Normalization:
# Build within an isolated staging directory to enforce exact 0755 directory modes
STAGE_DIR=$(mktemp -d /tmp/matrix_stage_XXXXXX)
trap 'rm -rf "$STAGE_DIR"' EXIT INT TERM

# Stage release files
cp -p "$BASE_DIR/module.prop" "$STAGE_DIR/"
cp -p "$BASE_DIR/customize.sh" "$STAGE_DIR/"
cp -p "$BASE_DIR/post-fs-data.sh" "$STAGE_DIR/"
cp -p "$BASE_DIR/service.sh" "$STAGE_DIR/"
cp -p "$BASE_DIR/action.sh" "$STAGE_DIR/"
cp -p "$BASE_DIR/uninstall.sh" "$STAGE_DIR/"
cp -rp "$BASE_DIR/META-INF" "$STAGE_DIR/"
cp -rp "$BASE_DIR/core" "$STAGE_DIR/"
cp -rp "$BASE_DIR/webroot" "$STAGE_DIR/"

# Also normalize local working tree directory permissions
chmod 755 "$BASE_DIR/core" "$BASE_DIR/webroot" "$BASE_DIR/META-INF" "$BASE_DIR/META-INF/com" "$BASE_DIR/META-INF/com/google" "$BASE_DIR/META-INF/com/google/android" 2>/dev/null || true

# Enforce deterministic exact Unix permissions in stage
find "$STAGE_DIR" -type d -exec chmod 755 {} +
find "$STAGE_DIR" -type f \( -name "*.sh" -o -name "update-binary" \) -exec chmod 755 {} +
find "$STAGE_DIR" -type f ! \( -name "*.sh" -o -name "update-binary" \) -exec chmod 644 {} +

# Package from stage directory
(
    cd "$STAGE_DIR"
    zip -r -q "$DIST_DIR/$ZIP_NAME" \
        module.prop \
        META-INF/ \
        customize.sh \
        post-fs-data.sh \
        service.sh \
        action.sh \
        uninstall.sh \
        core/ \
        webroot/ \
        -x "*.git*" "*.DS_Store*"
)

echo "[+] ZIP Package built successfully."
echo "[+] Validating archive integrity..."
unzip -t "$DIST_DIR/$ZIP_NAME" >/dev/null

echo "[+] Contents table:"
unzip -l "$DIST_DIR/$ZIP_NAME"

echo "=========================================="
echo " Build Complete: $DIST_DIR/$ZIP_NAME"
echo "=========================================="
