#!/bin/bash
# Upload App Store screenshots from the screenshot generator exports to ASC.
#
# Usage:
#   ./scripts/upload-screenshots.sh [--dry-run]
#
# Prerequisites:
#   1. Run the screenshot generator (pnpm --dir screenshots dev)
#   2. Click "Export All" for each of the 4 sizes (6.9", 6.5", 6.3", 6.1")
#   3. Move/copy the exported PNGs into screenshots/exports/
#   4. Run this script

set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.centaur-labs.cartogram"
EXPORTS_DIR="screenshots/exports"
SKILL_SCRIPTS=".agents/skills/asc-screenshot-deploy/scripts"

if [ ! -d "$EXPORTS_DIR" ]; then
    echo "No exports directory found. Creating it..."
    mkdir -p "$EXPORTS_DIR"
    echo ""
    echo "Now do one of:"
    echo "  1. Export from the screenshot generator into screenshots/exports/"
    echo "  2. Copy PNGs from ~/Downloads:"
    echo "     cp ~/Downloads/0*-*.png screenshots/exports/"
    echo ""
    exit 1
fi

COUNT=$(find "$EXPORTS_DIR" -name "*.png" | wc -l | tr -d ' ')
if [ "$COUNT" -eq 0 ]; then
    echo "No PNGs found in $EXPORTS_DIR"
    echo "Export from the generator first, then copy here."
    exit 1
fi

echo "Found $COUNT PNGs in $EXPORTS_DIR"
ls "$EXPORTS_DIR"/*.png 2>/dev/null | head -20
echo ""

python3 "$SKILL_SCRIPTS/upload-screenshots.py" \
    --bundle-id "$BUNDLE_ID" \
    --exports-dir "$EXPORTS_DIR" \
    "$@"
