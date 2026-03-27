#!/bin/bash
# Manage App Store review submissions for Cartogram.
#
# Usage:
#   ./scripts/manage-review.sh status
#   ./scripts/manage-review.sh cancel
#   ./scripts/manage-review.sh submit
#   ./scripts/manage-review.sh submit --wait-for-screenshots 45

set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.centaur-labs.cartogram"
SKILL_SCRIPTS=".agents/skills/asc-screenshot-deploy/scripts"

ACTION="${1:?Usage: $0 <status|cancel|submit> [extra args]}"
shift

python3 "$SKILL_SCRIPTS/manage-review.py" \
    --bundle-id "$BUNDLE_ID" \
    --action "$ACTION" \
    "$@"
