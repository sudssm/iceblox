#!/usr/bin/env python3
"""
Upload IPA and manage App Store Connect releases.

Usage:
  python3 publish.py                # Upload IPA, attach to pending version, submit for review
  python3 publish.py --list         # List current app store versions
  python3 publish.py --skip-build   # Skip build, upload existing IPA
  python3 publish.py --build-only   # Build IPA only, don't upload

Requires:
  - PyJWT, cryptography (pip3 install PyJWT cryptography)
  - App Store Connect API key (env vars or .env file):
    APP_STORE_KEY_ID, APP_STORE_ISSUER_ID, APP_STORE_KEY_P8 or APP_STORE_KEY_FILE
  - APPLE_TEAM_ID (for building)

Environment:
  CI sets secrets via GitHub Actions. Locally, values come from .env in the project root.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any

import jwt
import requests

BUNDLE_ID = "com.iceblox.app"
BASE_URL = "https://api.appstoreconnect.apple.com/v1"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
IPA_PATH = os.path.join(ROOT_DIR, "ios", "build", "export", "IceBloxApp.ipa")

# How long a version must have been in review before we warn
REVIEW_WARNING_HOURS = 6


def load_env() -> None:
    """Load .env file from project root into os.environ (simple key=value parsing)."""
    env_path = os.path.join(ROOT_DIR, ".env")
    if not os.path.exists(env_path):
        return
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"')
            if key not in os.environ:
                os.environ[key] = value


def get_api_key() -> tuple[str, str, str]:
    """Return (key_id, issuer_id, private_key_pem)."""
    key_id = os.environ.get("APP_STORE_KEY_ID", "")
    issuer_id = os.environ.get("APP_STORE_ISSUER_ID", "")

    # Private key: from file path or inline PEM
    key_file = os.environ.get("APP_STORE_KEY_FILE", "")
    if key_file and os.path.exists(key_file):
        with open(key_file) as f:
            pem = f.read()
    else:
        raw = os.environ.get("APP_STORE_KEY_P8", "")
        pem = raw.encode().decode("unicode_escape")

    if not all([key_id, issuer_id, pem]):
        print("ERROR: Missing App Store Connect API credentials.")
        print("Set APP_STORE_KEY_ID, APP_STORE_ISSUER_ID, and APP_STORE_KEY_P8 (or APP_STORE_KEY_FILE).")
        sys.exit(1)

    return key_id, issuer_id, pem


def make_token(key_id: str, issuer_id: str, pem: str) -> str:
    """Generate a JWT for the App Store Connect API."""
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, pem, algorithm="ES256", headers={"kid": key_id})


def api_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def api_get(token: str, path: str, params: dict | None = None) -> dict:
    resp = requests.get(f"{BASE_URL}{path}", headers=api_headers(token), params=params)
    resp.raise_for_status()
    return resp.json()


def api_patch(token: str, path: str, body: dict) -> dict:
    resp = requests.patch(f"{BASE_URL}{path}", headers=api_headers(token), json=body)
    if not resp.ok:
        print(f"PATCH {path} failed: {resp.status_code}")
        print(resp.text)
        resp.raise_for_status()
    if resp.status_code == 204:
        return {}
    return resp.json()


def api_post(token: str, path: str, body: dict) -> dict:
    resp = requests.post(f"{BASE_URL}{path}", headers=api_headers(token), json=body)
    if not resp.ok:
        print(f"POST {path} failed: {resp.status_code}")
        print(resp.text)
        resp.raise_for_status()
    return resp.json()


# ── App & Version helpers ──────────────────────────────────────────────


def get_app_id(token: str) -> str:
    data = api_get(token, "/apps", {"filter[bundleId]": BUNDLE_ID})
    apps = data.get("data", [])
    if not apps:
        print(f"ERROR: No app found with bundle ID {BUNDLE_ID}")
        sys.exit(1)
    return apps[0]["id"]


def get_versions(token: str, app_id: str) -> list[dict]:
    data = api_get(token, f"/apps/{app_id}/appStoreVersions")
    return data.get("data", [])


def get_version_build(token: str, version_id: str) -> dict | None:
    data = api_get(token, f"/appStoreVersions/{version_id}/build")
    return data.get("data")


def get_builds(token: str, app_id: str) -> list[dict]:
    data = api_get(token, f"/apps/{app_id}/builds", {"limit": 20})
    return data.get("data", [])


def get_review_submissions(token: str, app_id: str) -> list[dict]:
    data = api_get(token, f"/apps/{app_id}/reviewSubmissions",
                   {"filter[state]": "WAITING_FOR_REVIEW,IN_REVIEW,READY_FOR_REVIEW"})
    return data.get("data", [])


# ── Build & Upload ─────────────────────────────────────────────────────


def build_ipa() -> str:
    """Build the IPA using make package-ios, with API key auth for export."""
    print("\n=== Building iOS release IPA ===")

    key_id, issuer_id, pem = get_api_key()

    # Write API key for xcodebuild auth
    key_dir = os.path.expanduser("~/.appstoreconnect/private_keys")
    os.makedirs(key_dir, exist_ok=True)
    key_path = os.path.join(key_dir, f"AuthKey_{key_id}.p8")
    with open(key_path, "w") as f:
        f.write(pem)

    # Step 1: Archive (via make, which also patches frameworks)
    result = subprocess.run(["make", "package-ios"], cwd=ROOT_DIR)

    if result.returncode != 0:
        # Archive may have succeeded but export failed (no local signing cert).
        # Try export manually with API key auth.
        archive = os.path.join(ROOT_DIR, "ios", "build", "IceBloxApp.xcarchive")
        export_plist = os.path.join(ROOT_DIR, "ios", "build", "ExportOptions.plist")
        export_dir = os.path.join(ROOT_DIR, "ios", "build", "export")

        if not os.path.exists(archive):
            print("ERROR: Archive not found. Build failed before archiving.")
            sys.exit(1)

        print("Export failed — retrying with API key authentication...")
        export_result = subprocess.run([
            "xcodebuild", "-exportArchive",
            "-archivePath", archive,
            "-exportPath", export_dir,
            "-exportOptionsPlist", export_plist,
            "-allowProvisioningUpdates",
            "-authenticationKeyPath", key_path,
            "-authenticationKeyID", key_id,
            "-authenticationKeyIssuerID", issuer_id,
        ])
        if export_result.returncode != 0:
            print("ERROR: Export failed even with API key auth.")
            sys.exit(1)

    if not os.path.exists(IPA_PATH):
        print(f"ERROR: IPA not found at {IPA_PATH}")
        sys.exit(1)

    print(f"IPA ready: {IPA_PATH}")
    return IPA_PATH


def upload_ipa(ipa_path: str) -> None:
    """Upload IPA to App Store Connect via xcrun altool."""
    key_id = os.environ.get("APP_STORE_KEY_ID", "")
    issuer_id = os.environ.get("APP_STORE_ISSUER_ID", "")

    print(f"\n=== Uploading IPA: {ipa_path} ===")
    result = subprocess.run([
        "xcrun", "altool", "--upload-app",
        "-f", ipa_path,
        "-t", "ios",
        "--apiKey", key_id,
        "--apiIssuer", issuer_id,
    ])
    if result.returncode != 0:
        print("ERROR: Upload failed")
        sys.exit(1)
    print("Upload succeeded.")


def wait_for_build(token: str, app_id: str, build_number: str,
                   timeout: int = 900, poll: int = 30) -> dict:
    """Wait for a build to appear and finish processing."""
    print(f"\nWaiting for build {build_number} to finish processing...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        builds = get_builds(token, app_id)
        for b in builds:
            if b["attributes"].get("version") == build_number:
                state = b["attributes"].get("processingState", "")
                if state == "VALID":
                    print(f"Build {build_number} is VALID.")
                    return b
                elif state in ("FAILED", "INVALID"):
                    print(f"ERROR: Build {build_number} processing {state}.")
                    sys.exit(1)
                else:
                    print(f"  Build {build_number}: {state}...")
                    break
        time.sleep(poll)

    print(f"ERROR: Timed out waiting for build {build_number} (after {timeout}s).")
    sys.exit(1)


# ── Version management ──────────────────────────────────────────────────


def find_pending_version(versions: list[dict]) -> dict | None:
    """Find a version that's editable (not yet live)."""
    editable_states = {
        "PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW",
        "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
        "INVALID_BINARY", "READY_FOR_DISTRIBUTION",
    }
    for v in versions:
        state = v["attributes"].get("appStoreState", "")
        if state in editable_states:
            return v
    return None


def find_live_version(versions: list[dict]) -> dict | None:
    for v in versions:
        if v["attributes"].get("appStoreState") == "READY_FOR_DISTRIBUTION":
            return v
    return None


def version_in_review_duration(version: dict) -> float | None:
    """Return hours since the version entered review, or None if not in review."""
    state = version["attributes"].get("appStoreState", "")
    if state not in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
        return None
    # Use createdDate as an approximation (submission time isn't directly available)
    created = version["attributes"].get("createdDate")
    if not created:
        return None
    created_dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
    return (datetime.now(timezone.utc) - created_dt).total_seconds() / 3600


def remove_from_review(token: str, app_id: str, version: dict) -> None:
    """Cancel a review submission for a version that's in review."""
    submissions = get_review_submissions(token, app_id)
    for sub in submissions:
        sub_id = sub["id"]
        print(f"Cancelling review submission {sub_id}...")
        api_patch(token, f"/reviewSubmissions/{sub_id}", {
            "data": {
                "type": "reviewSubmissions",
                "id": sub_id,
                "attributes": {"canceled": True},
            }
        })
        print("Review cancelled.")
        return

    print("No active review submission found to cancel.")


def set_version_build(token: str, version_id: str, build_id: str) -> None:
    """Attach a build to an app store version."""
    api_patch(token, f"/appStoreVersions/{version_id}/relationships/build", {
        "data": {"type": "builds", "id": build_id},
    })
    print(f"Attached build {build_id} to version {version_id}.")


def create_version(token: str, app_id: str, version_string: str) -> dict:
    """Create a new app store version."""
    return api_post(token, "/appStoreVersions", {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "versionString": version_string,
                "platform": "IOS",
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
            },
        }
    })


def submit_for_review(token: str, app_id: str, version_id: str) -> None:
    """Create a review submission and submit it."""
    # Create submission
    sub = api_post(token, "/reviewSubmissions", {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
            },
        }
    })
    sub_id = sub["data"]["id"]

    # Add the version as an item
    api_post(token, "/reviewSubmissionItems", {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
            },
        }
    })

    # Submit
    api_patch(token, f"/reviewSubmissions/{sub_id}", {
        "data": {
            "type": "reviewSubmissions",
            "id": sub_id,
            "attributes": {"submitted": True},
        }
    })
    print("Submitted for App Review.")


# ── Commands ────────────────────────────────────────────────────────────


def cmd_list() -> None:
    """List current app store versions."""
    load_env()
    key_id, issuer_id, pem = get_api_key()
    token = make_token(key_id, issuer_id, pem)
    app_id = get_app_id(token)
    versions = get_versions(token, app_id)

    print(f"\nApp Store versions for {BUNDLE_ID} (app {app_id}):\n")
    for v in versions:
        attrs = v["attributes"]
        state = attrs.get("appStoreState", "?")
        ver = attrs.get("versionString", "?")
        created = attrs.get("createdDate", "?")
        print(f"  {ver}  {state}  (created {created})")

    builds = get_builds(token, app_id)
    print(f"\nRecent builds:")
    for b in builds[:5]:
        attrs = b["attributes"]
        print(f"  Build {attrs.get('version')}  {attrs.get('processingState')}  "
              f"uploaded {attrs.get('uploadedDate', '?')}")


def cmd_publish(skip_build: bool = False, skip_upload: bool = False,
                build_number: str | None = None,
                auto_submit: bool = True) -> None:
    """Build, upload, attach to version, and submit for review."""
    load_env()
    key_id, issuer_id, pem = get_api_key()
    token = make_token(key_id, issuer_id, pem)
    app_id = get_app_id(token)

    # 1. Build and upload
    if not skip_build:
        ipa_path = build_ipa()
    else:
        if not os.path.exists(IPA_PATH):
            print(f"ERROR: IPA not found at {IPA_PATH}. Run build first or remove --skip-build.")
            sys.exit(1)
        ipa_path = IPA_PATH
        print(f"Using existing IPA: {ipa_path}")

    if not skip_upload:
        upload_ipa(ipa_path)

    # Read build number from the archive if not provided
    if not build_number:
        import subprocess as sp
        result = sp.run(
            ["plutil", "-extract", "CFBundleVersion", "raw",
             os.path.join(ROOT_DIR, "ios", "build", "IceBloxApp.xcarchive",
                          "Products", "Applications", "IceBloxApp.app", "Info.plist")],
            capture_output=True, text=True,
        )
        build_number = result.stdout.strip()

    if not build_number:
        print("ERROR: Could not determine build number.")
        sys.exit(1)

    # Read marketing version from archive
    result = subprocess.run(
        ["plutil", "-extract", "CFBundleShortVersionString", "raw",
         os.path.join(ROOT_DIR, "ios", "build", "IceBloxApp.xcarchive",
                      "Products", "Applications", "IceBloxApp.app", "Info.plist")],
        capture_output=True, text=True,
    )
    marketing_version = result.stdout.strip()

    print(f"\nVersion: {marketing_version}, Build: {build_number}")

    # 2. Wait for build to process
    # Refresh token in case it expired during build/upload
    token = make_token(key_id, issuer_id, pem)
    build = wait_for_build(token, app_id, build_number)
    build_id = build["id"]

    # 3. Find or create version
    token = make_token(key_id, issuer_id, pem)
    versions = get_versions(token, app_id)
    pending = find_pending_version(versions)

    if pending:
        version_state = pending["attributes"]["appStoreState"]
        version_string = pending["attributes"]["versionString"]

        # Check if in review and warn if > 6 hours
        review_hours = version_in_review_duration(pending)
        if review_hours is not None and review_hours > REVIEW_WARNING_HOURS:
            print(f"\n⚠ WARNING: Version {version_string} has been in review for "
                  f"{review_hours:.1f} hours (>{REVIEW_WARNING_HOURS}h).")
            print("It may have already started being reviewed by Apple.")
            # In CI, we proceed but log the warning. The Claude skill handles confirmation.

        # Remove from review if needed
        if version_state in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
            print(f"Removing version {version_string} from review...")
            remove_from_review(token, app_id, pending)
            # Refresh
            token = make_token(key_id, issuer_id, pem)

        version_id = pending["id"]
        print(f"Using existing version {version_string} ({version_state}) → attaching build {build_number}")
    else:
        # No pending version — create one
        print(f"No pending version found. Creating version {marketing_version}...")
        result = create_version(token, app_id, marketing_version)
        version_id = result["data"]["id"]
        print(f"Created version {marketing_version}.")

    # 4. Attach build and set export compliance
    set_version_build(token, version_id, build_id)

    # Set export compliance (app uses only standard HTTPS encryption, which is exempt)
    api_patch(token, f"/builds/{build_id}", {
        "data": {
            "type": "builds",
            "id": build_id,
            "attributes": {"usesNonExemptEncryption": False},
        }
    })
    print("Export compliance set (no non-exempt encryption).")

    # 5. Submit for review
    if auto_submit:
        token = make_token(key_id, issuer_id, pem)
        submit_for_review(token, app_id, version_id)
        print(f"\n✓ Version {marketing_version} (build {build_number}) submitted for review.")
    else:
        print(f"\n✓ Build {build_number} attached to version. Submit manually when ready.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build and publish iOS app to App Store Connect")
    parser.add_argument("--list", action="store_true", help="List current versions and builds")
    parser.add_argument("--skip-build", action="store_true", help="Skip building, use existing IPA")
    parser.add_argument("--skip-upload", action="store_true", help="Skip uploading (build already uploaded)")
    parser.add_argument("--build-only", action="store_true", help="Build IPA only, don't upload")
    parser.add_argument("--build-number", type=str, default=None, help="Build number to wait for")
    parser.add_argument("--no-submit", action="store_true", help="Don't auto-submit for review")
    args = parser.parse_args()

    if args.list:
        cmd_list()
    elif args.build_only:
        load_env()
        build_ipa()
    else:
        cmd_publish(
            skip_build=args.skip_build,
            skip_upload=args.skip_upload,
            build_number=args.build_number,
            auto_submit=not args.no_submit,
        )


if __name__ == "__main__":
    main()
