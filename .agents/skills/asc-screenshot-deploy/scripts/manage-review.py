#!/usr/bin/env python3
"""Manage App Store Connect review submissions: cancel, resubmit, check status.

Usage:
    python3 manage-review.py --bundle-id <bundle.id> --action <cancel|submit|status>

Actions:
    status  - Show current review submission state
    cancel  - Cancel (developer reject) the current review submission
    submit  - Create a new review submission and submit for review

Requires:
    - PyJWT: pip3 install PyJWT cryptography
    - Credentials file at ~/.cartogram-secrets with ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH
"""

import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path

import jwt

# ── Args ────────────────────────────────────────────────────────────────────

parser = argparse.ArgumentParser(description="Manage App Store review submissions")
parser.add_argument("--bundle-id", required=True, help="App bundle ID")
parser.add_argument("--action", required=True, choices=["cancel", "submit", "status"],
                    help="Action to perform")
parser.add_argument("--secrets-file", default=str(Path.home() / ".cartogram-secrets"),
                    help="Path to secrets file")
parser.add_argument("--wait-for-screenshots", type=int, default=0,
                    help="Seconds to wait for screenshot processing before submitting (default: 0)")
args = parser.parse_args()

# ── Credentials ─────────────────────────────────────────────────────────────

secrets_path = Path(args.secrets_file)
if not secrets_path.exists():
    print(f"ERROR: Missing {secrets_path}")
    sys.exit(1)

secrets = {}
for line in secrets_path.read_text().splitlines():
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        secrets[k.strip()] = v.strip()

ASC_KEY_ID = secrets["ASC_KEY_ID"]
ASC_ISSUER_ID = secrets["ASC_ISSUER_ID"]
ASC_KEY_PATH = Path(secrets["ASC_KEY_PATH"].replace("~", str(Path.home())))

# ── JWT + HTTP ──────────────────────────────────────────────────────────────

def make_token():
    now = int(time.time())
    payload = {"iss": ASC_ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    key = ASC_KEY_PATH.read_text()
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": ASC_KEY_ID})

TOKEN = make_token()
API = "https://api.appstoreconnect.apple.com/v1"

def req(method, path, body=None):
    url = f"{API}{path}" if path.startswith("/") else path
    data = json.dumps(body).encode() if body else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", f"Bearer {TOKEN}")
    if data:
        r.add_header("Content-Type", "application/json")
    try:
        resp = urllib.request.urlopen(r)
        return json.loads(resp.read()) if resp.status != 204 else {}
    except urllib.error.HTTPError as e:
        error_body = json.loads(e.read().decode())
        print(f"  API Error {e.code}:")
        for err in error_body.get("errors", []):
            print(f"    {err.get('title', '')}: {err.get('detail', '')}")
        return None

# ── Find app & version ──────────────────────────────────────────────────────

print(f"==> Finding app: {args.bundle_id}")
app_data = req("GET", f"/apps?filter[bundleId]={args.bundle_id}")
if not app_data or not app_data["data"]:
    print(f"ERROR: No app found with bundle ID: {args.bundle_id}")
    sys.exit(1)

app_id = app_data["data"][0]["id"]
print(f"    App ID: {app_id}")

# Find editable version
versions = req("GET", f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS")
editable_states = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_ACTION_NEEDED", "INVALID_BINARY",
    "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
    "WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW",
}
version_id = None
version_state = None
for v in versions["data"]:
    state = v["attributes"]["appStoreState"]
    if state in editable_states:
        version_id = v["id"]
        version_state = state
        print(f"    Version: {v['attributes']['versionString']} (state: {state})")
        break

if not version_id:
    print("ERROR: No editable version found.")
    sys.exit(1)

# ── Actions ─────────────────────────────────────────────────────────────────

if args.action == "status":
    subs = req("GET", f"/apps/{app_id}/reviewSubmissions")
    if subs and subs["data"]:
        for s in subs["data"][:3]:
            print(f"    Submission {s['id'][:8]}...: {s['attributes']['state']}")
    else:
        print("    No review submissions found.")

elif args.action == "cancel":
    if version_state not in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
        print(f"    Version is {version_state}, not in review. Nothing to cancel.")
        sys.exit(0)

    subs = req("GET", f"/apps/{app_id}/reviewSubmissions?filter[state]=WAITING_FOR_REVIEW,IN_REVIEW")
    if not subs or not subs["data"]:
        print("    No active review submission found.")
        sys.exit(1)

    sub_id = subs["data"][0]["id"]
    print(f"==> Canceling submission {sub_id[:8]}...")
    result = req("PATCH", f"/reviewSubmissions/{sub_id}", {
        "data": {
            "type": "reviewSubmissions",
            "id": sub_id,
            "attributes": {"canceled": True}
        }
    })
    if result:
        print(f"    Done. State: {result['data']['attributes']['state']}")

elif args.action == "submit":
    if version_state in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
        print(f"    Version is already {version_state}.")
        sys.exit(0)

    # Wait for screenshot processing if requested
    if args.wait_for_screenshots > 0:
        print(f"==> Waiting {args.wait_for_screenshots}s for screenshot processing...")
        time.sleep(args.wait_for_screenshots)

    # Create review submission
    print("==> Creating review submission...")
    result = req("POST", "/reviewSubmissions", {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}}
            }
        }
    })
    if not result:
        sys.exit(1)

    sub_id = result["data"]["id"]
    print(f"    Submission: {sub_id[:8]}... ({result['data']['attributes']['state']})")

    # Add version as review item
    print("==> Adding version to submission...")
    item = req("POST", "/reviewSubmissionItems", {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
            }
        }
    })
    if not item:
        print("    Failed to add version. Screenshots may still be processing.")
        print("    Try again with --wait-for-screenshots 60")
        sys.exit(1)

    # Submit
    print("==> Submitting for review...")
    result = req("PATCH", f"/reviewSubmissions/{sub_id}", {
        "data": {
            "type": "reviewSubmissions",
            "id": sub_id,
            "attributes": {"submitted": True}
        }
    })
    if result:
        print(f"    ✓ State: {result['data']['attributes']['state']}")
    else:
        print("    Failed to submit. Try again with --wait-for-screenshots 60")
        sys.exit(1)
