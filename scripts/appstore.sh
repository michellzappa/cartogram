#!/bin/bash
set -euo pipefail

# Cartogram — App Store Connect release script
# Builds, archives, uploads, and submits both macOS + iOS to App Store Connect.
#
# Usage:
#   ./scripts/appstore.sh v1.1.0              # both platforms
#   ./scripts/appstore.sh v1.1.0 --ios-only   # iOS only
#   ./scripts/appstore.sh v1.1.0 --mac-only   # macOS only
#   ./scripts/appstore.sh v1.1.0 --dry-run    # archive + validate, no upload
#
# One-time setup:
#   1. Go to App Store Connect → Users & Access → Integrations → App Store Connect API
#   2. Click "+" → Name: "Cartogram CI" → Role: "App Manager"
#   3. Download the .p8 file
#   4. Create ~/.cartogram-secrets with:
#        ASC_KEY_ID=YOUR_KEY_ID
#        ASC_ISSUER_ID=YOUR_ISSUER_ID
#        ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8

VERSION="${1:?Usage: appstore.sh <version-tag> [--ios-only|--mac-only|--dry-run]}"
MARKETING_VERSION="${VERSION#v}"

# Parse flags
BUILD_MAC=true
BUILD_IOS=true
DRY_RUN=false

shift
for arg in "$@"; do
    case "$arg" in
        --ios-only) BUILD_MAC=false ;;
        --mac-only) BUILD_IOS=false ;;
        --dry-run)  DRY_RUN=true ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

# ── Credentials ──────────────────────────────────────────────────────────────

SECRETS_FILE="$HOME/.cartogram-secrets"
if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "ERROR: Missing $SECRETS_FILE"
    echo ""
    echo "Create it with your App Store Connect API key credentials:"
    echo "  ASC_KEY_ID=YOUR_KEY_ID"
    echo "  ASC_ISSUER_ID=YOUR_ISSUER_ID"
    echo "  ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"
    echo ""
    echo "See script header for full setup instructions."
    exit 1
fi

# shellcheck source=/dev/null
source "$SECRETS_FILE"

# Expand tilde in key path
ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"

for var in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: $var not set in $SECRETS_FILE"
        exit 1
    fi
done

if [[ ! -f "$ASC_KEY_PATH" ]]; then
    echo "ERROR: API key file not found at $ASC_KEY_PATH"
    exit 1
fi

# ── Project paths ────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/Cartogram.xcodeproj"
ARCHIVE_DIR="$PROJECT_DIR/.build/archives"
EXPORT_DIR="$PROJECT_DIR/.build/export"
TEAM_ID="992N457T8D"

rm -rf "$ARCHIVE_DIR" "$EXPORT_DIR"
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"

# ── Version bump ─────────────────────────────────────────────────────────────

echo "==> Bumping version to $MARKETING_VERSION..."

# Read current build number and increment
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PROJECT/project.pbxproj" | head -1 | sed 's/[^0-9]//g')
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "    Build number: $CURRENT_BUILD → $NEW_BUILD"

# Update project.pbxproj
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $MARKETING_VERSION/g" "$PROJECT/project.pbxproj"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $NEW_BUILD/g" "$PROJECT/project.pbxproj"

# Update Info.plists
for plist in "$PROJECT_DIR/macOS/Info.plist" "$PROJECT_DIR/iOS/Info.plist"; do
    if [[ -f "$plist" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$plist"
    fi
done

echo "    Version: $MARKETING_VERSION ($NEW_BUILD)"

# ── Archive & Export ─────────────────────────────────────────────────────────

archive_and_export() {
    local scheme="$1"
    local destination="$2"
    local platform_name="$3"
    local export_options="$4"
    local archive_path="$ARCHIVE_DIR/$platform_name.xcarchive"
    local export_path="$EXPORT_DIR/$platform_name"

    echo ""
    echo "==> Archiving $platform_name ($scheme)..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$scheme" \
        -destination "$destination" \
        -archivePath "$archive_path" \
        -configuration Release \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        MARKETING_VERSION="$MARKETING_VERSION" \
        CURRENT_PROJECT_VERSION="$NEW_BUILD" \
        CODE_SIGN_STYLE=Automatic \
        2>&1 | tail -5

    if [[ ! -d "$archive_path" ]]; then
        echo "ERROR: Archive failed — $archive_path not found"
        exit 1
    fi
    echo "    Archive: $archive_path"

    echo "==> Exporting $platform_name..."
    xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$export_options" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$ASC_KEY_PATH" \
        -authenticationKeyID "$ASC_KEY_ID" \
        -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
        2>&1 | tail -5

    echo "    Export: $export_path"
}

if $BUILD_MAC; then
    archive_and_export \
        "Cartogram" \
        "generic/platform=macOS" \
        "macOS" \
        "$PROJECT_DIR/scripts/ExportOptions-macOS.plist"
fi

if $BUILD_IOS; then
    archive_and_export \
        "CartogramIOS" \
        "generic/platform=iOS" \
        "iOS" \
        "$PROJECT_DIR/scripts/ExportOptions-iOS.plist"
fi

# ── Validate ─────────────────────────────────────────────────────────────────

validate_app() {
    local app_path="$1"
    local platform_name="$2"

    echo ""
    echo "==> Validating $platform_name..."
    xcrun altool --validate-app \
        -f "$app_path" \
        -t "${platform_name,,}" \
        --apiKey "$ASC_KEY_ID" \
        --apiIssuer "$ASC_ISSUER_ID" \
        2>&1
    echo "    ✓ $platform_name validation passed"
}

upload_app() {
    local app_path="$1"
    local platform_name="$2"

    echo ""
    echo "==> Uploading $platform_name to App Store Connect..."
    xcrun altool --upload-app \
        -f "$app_path" \
        -t "${platform_name,,}" \
        --apiKey "$ASC_KEY_ID" \
        --apiIssuer "$ASC_ISSUER_ID" \
        2>&1
    echo "    ✓ $platform_name uploaded"
}

# Find exported artifacts
if $BUILD_MAC; then
    MAC_PKG=$(find "$EXPORT_DIR/macOS" -name "*.pkg" -o -name "*.ipa" | head -1)
    if [[ -z "$MAC_PKG" ]]; then
        echo "ERROR: No .pkg or .ipa found in $EXPORT_DIR/macOS"
        ls -la "$EXPORT_DIR/macOS/"
        exit 1
    fi
    validate_app "$MAC_PKG" "macos"
fi

if $BUILD_IOS; then
    IOS_IPA=$(find "$EXPORT_DIR/iOS" -name "*.ipa" | head -1)
    if [[ -z "$IOS_IPA" ]]; then
        echo "ERROR: No .ipa found in $EXPORT_DIR/iOS"
        ls -la "$EXPORT_DIR/iOS/"
        exit 1
    fi
    validate_app "$IOS_IPA" "ios"
fi

# ── Upload (unless dry run) ──────────────────────────────────────────────────

if $DRY_RUN; then
    echo ""
    echo "==> Dry run complete. Archives validated but NOT uploaded."
    echo "    Run without --dry-run to upload to App Store Connect."
else
    if $BUILD_MAC; then
        upload_app "$MAC_PKG" "macos"
    fi

    if $BUILD_IOS; then
        upload_app "$IOS_IPA" "ios"
    fi

    # ── Git tag ──────────────────────────────────────────────────────────────

    echo ""
    echo "==> Committing version bump and tagging $VERSION..."
    git -C "$PROJECT_DIR" add -A
    git -C "$PROJECT_DIR" commit -m "Bump version to $MARKETING_VERSION ($NEW_BUILD) for App Store release"
    git -C "$PROJECT_DIR" tag "$VERSION"
    git -C "$PROJECT_DIR" push origin main --tags

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  ✓ Cartogram $MARKETING_VERSION ($NEW_BUILD) uploaded!"
    echo ""
    $BUILD_MAC && echo "  • macOS: $MAC_PKG"
    $BUILD_IOS && echo "  • iOS:   $IOS_IPA"
    echo ""
    echo "  Next: Check App Store Connect for build processing status"
    echo "  https://appstoreconnect.apple.com/apps"
    echo "════════════════════════════════════════════════════════════"
fi
