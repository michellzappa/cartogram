# Kickoff: Upload App Store Screenshots to ASC

## Context

Cartogram is a macOS + iOS app that generates map wallpapers from your photo library's GPS data. Bundle ID: `com.centaur-labs.cartogram`.

The screenshot generator already exists at `screenshots/` (Next.js + html-to-image). It has 3 slides:
- **Hero** — App icon + "A wallpaper only you can have." + home screen
- **Heatmap** — "Every photo lights up the map." + detail view
- **Themes** — "One map. Five looks." + settings/theme picker

Screenshot assets are in `screenshots/public/screenshots/` (1-hero.png, 2-detail.png, 3-settings.png).

## What's already set up

- **`asc-screenshot-deploy` skill** in `.agents/skills/` — has the upload + review management Python scripts
- **`scripts/upload-screenshots.sh`** — wrapper that runs the upload with the right bundle ID
- **`scripts/manage-review.sh`** — wrapper for cancel/submit/status review actions
- **`scripts/appstore.sh`** — existing binary build + upload script (don't touch this)
- **"Export All Sizes" button** added to the screenshot generator — exports all 4 iPhone resolutions in one click
- Credentials are in `~/.cartogram-secrets` (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH)

## Task

1. **Start the screenshot generator**: `pnpm --dir screenshots dev` (port 3000, also configured in `.claude/launch.json`)
2. **Preview the slides** and verify they look good
3. **Export all sizes** — click "Export All Sizes" in the browser, which downloads 12 PNGs (3 slides × 4 sizes) to `~/Downloads/`
4. **Collect exports**: `mkdir -p screenshots/exports && cp ~/Downloads/0*-*.png screenshots/exports/`
5. **Upload to ASC**: `./scripts/upload-screenshots.sh`
6. If the version is in review:
   - `./scripts/manage-review.sh cancel` — developer reject
   - `sleep 3`
   - `./scripts/upload-screenshots.sh` — upload new screenshots
   - `./scripts/manage-review.sh submit --wait-for-screenshots 45` — resubmit
7. Verify upload succeeded — all screenshots should be `COMPLETE` state

## Gotchas (learned the hard way)

- **Screenshot set matching**: The upload script fetches ALL screenshot sets and matches by `screenshotDisplayType` attribute locally. Apple's `filter` query param is unreliable.
- **Checksum format**: `sourceFileChecksum` must be a plain MD5 hex string, not `{"type": "md5", "value": "..."}`.
- **Processing delay**: After upload, wait ~45s before submitting for review. Screenshots in `UPLOAD_COMPLETE` → `COMPLETE` takes time.
- **Review items**: A review submission needs a `reviewSubmissionItem` linking the `appStoreVersion` before it can be submitted.
