---
name: asc-screenshot-deploy
description: Full workflow for deploying App Store screenshots — from simulator setup through App Store Connect upload and review submission. Use this skill whenever the user wants to upload screenshots to App Store Connect, manage App Store review submissions (cancel, resubmit), set up an iOS simulator with Apple-standard status bar for clean screenshots, or run the end-to-end flow of generating marketing screenshots and pushing them to the App Store. Triggers on App Store Connect, ASC, upload screenshots, submit for review, cancel review, simulator status bar, screenshot deploy.
---

# App Store Screenshot Deploy

End-to-end workflow for getting App Store screenshots from your screen into App Store Connect, including simulator setup, screenshot generation, API upload, and review management.

## Overview

This skill covers the full pipeline:

1. **Simulator setup** — Boot a simulator with Apple-standard status bar (9:41, full bars, 100% battery)
2. **App build & install** — Build the Xcode project and install on the simulator
3. **Screenshot generation** — Use the `app-store-screenshots` skill to create marketing screenshots
4. **Upload to ASC** — Push exported PNGs to App Store Connect via the API
5. **Review management** — Cancel an existing review, upload new screenshots, resubmit

Each step can be run independently — the user might only need the upload, or only the simulator setup.

## Step 1: Simulator Status Bar

Apple uses a clean status bar in all marketing materials: 9:41, full signal, full WiFi, 100% battery, no carrier name. Set this up before capturing any screenshots.

```bash
# Find and boot a simulator (pick the right device for your screenshot size)
xcrun simctl list devices available | grep "iPhone"
xcrun simctl boot <DEVICE_UUID>

# Override the status bar
xcrun simctl status_bar booted override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4 \
  --cellularMode active \
  --operatorName ""

# Reset when done
xcrun simctl status_bar booted clear
```

### Device → Screenshot Size Mapping

| Device | Resolution | Apple Display Type |
|--------|-----------|-------------------|
| iPhone 16 Pro Max | 1320×2868 | APP_IPHONE_67 (6.9") |
| iPhone 15 Pro Max | 1284×2778 | APP_IPHONE_65 (6.5") |
| iPhone 16 Pro | 1206×2622 | APP_IPHONE_61 (6.3") |
| iPhone 14 Pro | 1125×2436 | APP_IPHONE_58 (6.1") |

## Step 2: Build & Install

Build the Xcode project for the booted simulator and install it so widgets and app are available for screenshots.

```bash
# Find the scheme
xcodebuild -list

# Build
xcodebuild -scheme <SCHEME> \
  -destination 'id=<DEVICE_UUID>' \
  -configuration Debug build

# Install (find the .app in DerivedData)
xcrun simctl install booted <path/to/Build/Products/Debug-iphonesimulator/App.app>

# Launch
xcrun simctl launch booted <BUNDLE_ID>
```

To find the bundle ID:
```bash
plutil -p <path/to/App.app/Info.plist> | grep CFBundleIdentifier
```

## Step 3: Generate Screenshots

Use the `app-store-screenshots` skill (installed separately via `npx skills add ParthJadhav/app-store-screenshots`) to create the marketing screenshot images. That skill handles the Next.js generator, phone mockups, copy, and export.

The generator exports PNGs named like `01-hero-1320x2868.png` into an `exports/` directory. The upload script expects this naming convention.

## Step 4: Upload to App Store Connect

The bundled `scripts/upload-screenshots.py` handles the full upload flow:

```bash
python3 <skill-path>/scripts/upload-screenshots.py \
  --bundle-id <BUNDLE_ID> \
  --exports-dir <path/to/exports>
```

### What it does

1. Finds the app and its editable version via the ASC API
2. For each of the 4 iPhone resolutions, finds exported PNGs matching `*-<WxH>.png`
3. Matches screenshot sets by `screenshotDisplayType` attribute (fetches ALL sets and filters locally — Apple's `filter` query param is unreliable and can return wrong sets)
4. Deletes existing screenshots in each set
5. Uploads new ones: reserve → upload chunks → commit with MD5 checksum
6. The `sourceFileChecksum` in the commit step must be a plain MD5 hex string, not an object — Apple's API rejects `{"type": "md5", "value": "..."}` even though some docs suggest it

### Options

- `--dry-run` — Show what would happen without uploading
- `--secrets-file <path>` — Custom path to credentials (default: `~/.cartogram-secrets`)

### Credentials

The script reads from `~/.cartogram-secrets` (or the path given via `--secrets-file`):

```
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_PATH=~/path/to/AuthKey_XXXXXXXXXX.p8
```

These come from App Store Connect → Users and Access → Integrations → App Store Connect API.

### Dependencies

```bash
pip3 install PyJWT cryptography
```

## Step 5: Review Management

The bundled `scripts/manage-review.py` handles canceling and resubmitting reviews:

```bash
# Check current status
python3 <skill-path>/scripts/manage-review.py \
  --bundle-id <BUNDLE_ID> --action status

# Cancel current review (developer reject)
python3 <skill-path>/scripts/manage-review.py \
  --bundle-id <BUNDLE_ID> --action cancel

# Resubmit for review (wait 45s for screenshot processing)
python3 <skill-path>/scripts/manage-review.py \
  --bundle-id <BUNDLE_ID> --action submit --wait-for-screenshots 45
```

### Common workflow: Update screenshots on a version in review

If the version is `WAITING_FOR_REVIEW` or `IN_REVIEW`, you can't modify screenshots. The workflow is:

1. **Cancel** the review → version becomes `DEVELOPER_REJECTED`
2. **Upload** new screenshots → they replace the old ones
3. **Wait** ~45 seconds for Apple to process the uploads
4. **Resubmit** → version goes back to `WAITING_FOR_REVIEW`

```bash
BUNDLE=com.example.MyApp
SKILL=<path-to-this-skill>
EXPORTS=<path-to-exports>

# Cancel → Upload → Wait → Resubmit
python3 $SKILL/scripts/manage-review.py --bundle-id $BUNDLE --action cancel
sleep 3
python3 $SKILL/scripts/upload-screenshots.py --bundle-id $BUNDLE --exports-dir $EXPORTS
python3 $SKILL/scripts/manage-review.py --bundle-id $BUNDLE --action submit --wait-for-screenshots 45
```

## Gotchas & Lessons Learned

- **Screenshot set matching**: Apple's `filter[screenshotDisplayType]` API param sometimes returns the wrong set. Always fetch ALL sets and match by the `screenshotDisplayType` attribute in the response data.
- **Checksum format**: The `sourceFileChecksum` field in the commit step must be a plain string (`"abc123..."`), not an object (`{"type": "md5", "value": "..."}`). The API returns a 409 with `ENTITY_ERROR.ATTRIBUTE.TYPE` if you use an object.
- **Screenshot processing time**: After uploading, Apple takes 30-60 seconds to process screenshots. Attempting to submit for review before processing completes returns a `STATE_ERROR.SCREENSHOT_UPLOADS_IN_PROGRESS` error.
- **Failed screenshots block submission**: If any screenshot is in `FAILED` state, you cannot submit. Delete and re-upload them.
- **Review submission items**: A review submission needs at least one item (the app store version) linked via `reviewSubmissionItems` before it can be submitted.
