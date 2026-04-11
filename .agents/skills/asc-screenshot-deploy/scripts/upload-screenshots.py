#!/usr/bin/env python3
"""Upload App Store screenshots to App Store Connect via the API.

Usage:
    python3 upload-screenshots.py --bundle-id <bundle.id> --exports-dir <path/to/exports>
    python3 upload-screenshots.py --bundle-id <bundle.id> --exports-dir <path/to/exports> --dry-run

Requires:
    - PyJWT: pip3 install PyJWT cryptography
    - Credentials file at ~/.cartogram-secrets with ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH

Export files must be named: <NN>-<slug>-<WxH>.png
    e.g. 01-hero-1320x2868.png, 02-widget-1284x2778.png
"""

import argparse
import hashlib
import json
import sys
import time
import urllib.request
from pathlib import Path

import jwt

# ── Apple display type mapping ──────────────────────────────────────────────

DISPLAY_TYPES = {
    "2048x2732": "APP_IPAD_PRO_3GEN_129",
    "1320x2868": "APP_IPHONE_67",
    "1284x2778": "APP_IPHONE_65",
    "1206x2622": "APP_IPHONE_61",
    "1125x2436": "APP_IPHONE_58",
}

# ── Args ────────────────────────────────────────────────────────────────────

parser = argparse.ArgumentParser(description="Upload screenshots to App Store Connect")
parser.add_argument("--bundle-id", required=True, help="App bundle ID (e.g. com.example.MyApp)")
parser.add_argument("--exports-dir", required=True, help="Directory containing exported PNGs")
parser.add_argument("--secrets-file", default=str(Path.home() / ".cartogram-secrets"),
                    help="Path to secrets file (default: ~/.cartogram-secrets)")
parser.add_argument("--dry-run", action="store_true", help="Show what would happen without uploading")
args = parser.parse_args()

BUNDLE_ID = args.bundle_id
EXPORTS_DIR = Path(args.exports_dir)
DRY_RUN = args.dry_run

if not EXPORTS_DIR.exists():
    print(f"ERROR: Exports directory not found: {EXPORTS_DIR}")
    sys.exit(1)

# ── Credentials ─────────────────────────────────────────────────────────────

secrets_path = Path(args.secrets_file)
if not secrets_path.exists():
    print(f"ERROR: Missing credentials file: {secrets_path}")
    print("Expected format (one per line):")
    print("  ASC_KEY_ID=XXXXXXXXXX")
    print("  ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")
    print("  ASC_KEY_PATH=~/path/to/AuthKey_XXXXXXXXXX.p8")
    sys.exit(1)

secrets = {}
for line in secrets_path.read_text().splitlines():
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        secrets[k.strip()] = v.strip()

for key in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
    if key not in secrets:
        print(f"ERROR: Missing {key} in {secrets_path}")
        sys.exit(1)

ASC_KEY_ID = secrets["ASC_KEY_ID"]
ASC_ISSUER_ID = secrets["ASC_ISSUER_ID"]
ASC_KEY_PATH = Path(secrets["ASC_KEY_PATH"].replace("~", str(Path.home())))

# ── JWT ─────────────────────────────────────────────────────────────────────

def make_token():
    now = int(time.time())
    payload = {"iss": ASC_ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    key = ASC_KEY_PATH.read_text()
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": ASC_KEY_ID})

TOKEN = make_token()
API = "https://api.appstoreconnect.apple.com/v1"

# ── HTTP helpers ────────────────────────────────────────────────────────────

def asc_request(method, path, body=None):
    url = f"{API}{path}" if path.startswith("/") else path
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read()) if resp.status != 204 else {}
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"  API Error {e.code}: {error_body[:500]}")
        raise

def asc_get(path): return asc_request("GET", path)
def asc_post(path, body): return asc_request("POST", path, body)
def asc_patch(path, body): return asc_request("PATCH", path, body)
def asc_delete(path): return asc_request("DELETE", path)

# ── Find app & version ──────────────────────────────────────────────────────

print(f"==> Finding app: {BUNDLE_ID}")
app_data = asc_get(f"/apps?filter[bundleId]={BUNDLE_ID}")
if not app_data["data"]:
    print(f"ERROR: No app found with bundle ID: {BUNDLE_ID}")
    sys.exit(1)
app_id = app_data["data"][0]["id"]
locale = app_data["data"][0]["attributes"]["primaryLocale"]
print(f"    App ID: {app_id}, locale: {locale}")

print("==> Finding editable app store version...")
versions = asc_get(f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS")
editable_states = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_ACTION_NEEDED", "INVALID_BINARY",
    "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
    "WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW",
}
version_id = None
version_string = None
version_state = None
for v in versions["data"]:
    state = v["attributes"]["appStoreState"]
    if state in editable_states:
        version_id = v["id"]
        version_string = v["attributes"]["versionString"]
        version_state = state
        print(f"    Version: {version_string} (state: {state}, id: {version_id})")
        break

if not version_id:
    print("ERROR: No editable app store version found.")
    print("Create one in App Store Connect first, or cancel the current review.")
    sys.exit(1)

# ── Find localization ───────────────────────────────────────────────────────

print("==> Finding localization...")
locs = asc_get(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")
loc_id = None
for loc in locs["data"]:
    if loc["attributes"]["locale"] == locale:
        loc_id = loc["id"]
        break
if not loc_id:
    loc_id = locs["data"][0]["id"]
    locale = locs["data"][0]["attributes"]["locale"]
print(f"    Localization: {locale} ({loc_id})")

# ── Upload screenshots ──────────────────────────────────────────────────────

for resolution, display_type in DISPLAY_TYPES.items():
    print(f"\n── {display_type} ({resolution}) ──")

    # Find matching files
    files = sorted(EXPORTS_DIR.glob(f"*-{resolution}.png"))
    if not files:
        print(f"  No files matching *-{resolution}.png, skipping")
        continue

    # IMPORTANT: Fetch ALL screenshot sets and match by screenshotDisplayType attribute.
    # Apple's filter[screenshotDisplayType] param is unreliable and can return wrong sets.
    all_sets = asc_get(f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    set_id = None
    for s in all_sets["data"]:
        if s["attributes"]["screenshotDisplayType"] == display_type:
            set_id = s["id"]
            break

    if set_id:
        print(f"  Set exists: {set_id}")

        # Delete existing screenshots
        existing = asc_get(f"/appScreenshotSets/{set_id}/appScreenshots")
        for s in existing["data"]:
            if not DRY_RUN:
                try:
                    asc_delete(f"/appScreenshots/{s['id']}")
                    print(f"  Deleted existing: {s['id']}")
                except Exception as e:
                    print(f"  Skipped delete {s['id']}: {e}")
    else:
        print("  Creating screenshot set...")
        if DRY_RUN:
            set_id = "DRY_RUN"
        else:
            resp = asc_post("/appScreenshotSets", {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": display_type},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                        }
                    }
                }
            })
            set_id = resp["data"]["id"]
        print(f"  Set ID: {set_id}")

    # Upload each file
    for png_path in files:
        file_size = png_path.stat().st_size
        file_name = png_path.name
        print(f"  Uploading {file_name} ({file_size:,} bytes)...")

        if DRY_RUN:
            print(f"    [dry-run] Would upload {file_name}")
            continue

        # 1. Reserve
        reserve = asc_post("/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": file_name, "fileSize": file_size},
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                }
            }
        })

        screenshot_id = reserve["data"]["id"]
        operations = reserve["data"]["attributes"]["uploadOperations"]

        # 2. Upload chunks
        file_data = png_path.read_bytes()
        for op in operations:
            offset = op["offset"]
            length = op["length"]
            chunk = file_data[offset:offset + length]

            req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
            for h in op["requestHeaders"]:
                req.add_header(h["name"], h["value"])
            urllib.request.urlopen(req)

        # 3. Commit — sourceFileChecksum must be a plain MD5 hex string, NOT an object
        md5 = hashlib.md5(file_data).hexdigest()
        asc_patch(f"/appScreenshots/{screenshot_id}", {
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": md5
                }
            }
        })

        print(f"    ✓ {screenshot_id}")

# ── Done ────────────────────────────────────────────────────────────────────

print()
if DRY_RUN:
    print("==> Dry run complete. No screenshots were uploaded.")
else:
    print("════════════════════════════════════════════════════════════")
    print(f"  Screenshots uploaded to App Store Connect!")
    print(f"")
    print(f"  Check: https://appstoreconnect.apple.com/apps/{app_id}")
    print("════════════════════════════════════════════════════════════")
