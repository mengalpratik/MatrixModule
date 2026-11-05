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

# Security Boundary Enforcement:
# Explicitly exclude references/, tests/, docs/, dist/, and git metadata
cd "$BASE_DIR"
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

echo "[+] ZIP Package built successfully."
echo "[+] Validating archive integrity..."
unzip -t "$DIST_DIR/$ZIP_NAME" >/dev/null

echo "[+] Contents table:"
unzip -l "$DIST_DIR/$ZIP_NAME"

echo "=========================================="
echo " Build Complete: $DIST_DIR/$ZIP_NAME"
echo "=========================================="
