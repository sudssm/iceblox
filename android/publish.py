#!/usr/bin/env python3
"""
Build, upload, and release an Android AAB to Google Play.

Usage:
  python3 publish.py                # Build, upload AAB, create release on highest available track
  python3 publish.py --list         # List current tracks/releases
  python3 publish.py --skip-build   # Skip build, just upload and release existing AAB
  python3 publish.py --track alpha  # Target a specific track (default: auto-detect highest)

Requires:
  - google-auth, requests (pip3 install google-auth requests)
  - Signing config in android/local.properties
  - Service account key at android/play-store-key.json (or PLAY_STORE_JSON_KEY env var)
  - PEPPER in .env
"""

from __future__ import annotations

import argparse
import glob
import os
import subprocess
import sys
from typing import Any

import requests
from google.auth.transport.requests import Request as AuthRequest
from google.oauth2 import service_account

PACKAGE_NAME = "com.iceblox.app"
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
BASE_URL = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE_NAME}"

# Resolve paths relative to this script (android/)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_KEY_FILE = os.path.join(SCRIPT_DIR, "play-store-key.json")
AAB_GLOB = os.path.join(SCRIPT_DIR, "app/build/outputs/bundle/release/*.aab")


def get_key_file() -> str:
    env_key = os.environ.get("PLAY_STORE_JSON_KEY")
    if env_key:
        # If it looks like JSON content (from a CI secret), write it to a temp file
        if env_key.strip().startswith("{"):
            key_path = os.path.join(SCRIPT_DIR, "play-store-key.json")
            with open(key_path, "w") as f:
                f.write(env_key)
            return key_path
        return env_key
    return DEFAULT_KEY_FILE


def get_credentials() -> service_account.Credentials:
    key_file = get_key_file()
    if not os.path.exists(key_file):
        print(f"ERROR: Service account key not found at {key_file}")
        print("Set PLAY_STORE_JSON_KEY env var or place the key at android/play-store-key.json")
        sys.exit(1)
    creds = service_account.Credentials.from_service_account_file(key_file, scopes=SCOPES)
    creds.refresh(AuthRequest())
    return creds


def api_headers(creds: service_account.Credentials) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {creds.token}",
        "Content-Type": "application/json",
    }


def create_edit(headers: dict[str, str]) -> str:
    resp = requests.post(f"{BASE_URL}/edits", headers=headers, json={})
    resp.raise_for_status()
    edit = resp.json()
    print(f"Created edit: {edit['id']}")
    return edit["id"]


def list_tracks(headers: dict[str, str], edit_id: str) -> list[dict[str, Any]]:
    resp = requests.get(f"{BASE_URL}/edits/{edit_id}/tracks", headers=headers)
    resp.raise_for_status()
    tracks = resp.json().get("tracks", [])
    for track in tracks:
        releases = track.get("releases", [])
        if releases:
            print(f"\n  Track: {track['track']}")
            for release in releases:
                vcs = release.get("versionCodes", [])
                status = release.get("status", "unknown")
                name = release.get("name", "")
                print(f"    {name} versionCodes={vcs} status={status}")
    return tracks


def upload_aab(headers: dict[str, str], edit_id: str, aab_path: str) -> int:
    """Upload an AAB to the edit."""
    print(f"Uploading AAB: {aab_path}")
    upload_url = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE_NAME}/edits/{edit_id}/bundles"
    with open(aab_path, "rb") as f:
        resp = requests.post(
            upload_url,
            headers={
                "Authorization": headers["Authorization"],
                "Content-Type": "application/octet-stream",
            },
            data=f,
        )
    if not resp.ok:
        print(f"Upload failed: {resp.status_code}")
        print(resp.text)
        resp.raise_for_status()
    result = resp.json()
    vc = result.get("versionCode")
    print(f"Uploaded successfully. Version code: {vc}")
    return vc


def set_track(
    headers: dict[str, str],
    edit_id: str,
    track: str,
    version_codes: list[int],
    status: str = "completed",
) -> tuple[dict[str, Any] | None, requests.Response]:
    release = {
        "status": status,
        "versionCodes": [str(vc) for vc in version_codes],
    }
    body = {"track": track, "releases": [release]}
    resp = requests.put(
        f"{BASE_URL}/edits/{edit_id}/tracks/{track}",
        headers=headers,
        json=body,
    )
    if not resp.ok:
        return None, resp
    return resp.json(), resp


def commit_edit(headers: dict[str, str], edit_id: str) -> dict[str, Any]:
    resp = requests.post(f"{BASE_URL}/edits/{edit_id}:commit", headers=headers)
    if not resp.ok:
        print(f"Commit failed: {resp.status_code}")
        print(resp.text)
        resp.raise_for_status()
    print(f"Edit committed: {resp.json()}")
    return resp.json()


def delete_edit(headers: dict[str, str], edit_id: str) -> None:
    requests.delete(f"{BASE_URL}/edits/{edit_id}", headers=headers)


def find_aab() -> str | None:
    matches = sorted(glob.glob(AAB_GLOB))
    if not matches:
        return None
    return matches[-1]


def build_aab() -> str:
    """Build the release AAB using Gradle."""
    print("\n=== Building release AAB ===")
    root_dir = os.path.dirname(SCRIPT_DIR)
    result = subprocess.run(
        ["make", "android-release-bundle"],
        cwd=root_dir,
        env={**os.environ, "PATH": os.environ.get("PATH", "")},
    )
    if result.returncode != 0:
        print("ERROR: Build failed")
        sys.exit(1)

    aab = find_aab()
    if not aab:
        print(f"ERROR: No AAB found at {AAB_GLOB}")
        sys.exit(1)
    print(f"Built AAB: {aab}")
    return aab


def cmd_list() -> None:
    creds = get_credentials()
    headers = api_headers(creds)
    edit_id = create_edit(headers)
    print("\nCurrent releases:")
    list_tracks(headers, edit_id)
    delete_edit(headers, edit_id)


def cmd_publish(skip_build: bool = False, target_track: str | None = None) -> None:
    """Build, upload, and release to the highest available track."""

    # 1. Build
    if skip_build:
        aab = find_aab()
        if not aab:
            print(f"ERROR: No AAB found. Run build first or remove --skip-build.")
            sys.exit(1)
        print(f"Using existing AAB: {aab}")
    else:
        aab = build_aab()

    # 2. Authenticate and create edit
    print("\n=== Uploading to Google Play ===")
    creds = get_credentials()
    headers = api_headers(creds)
    edit_id = create_edit(headers)

    try:
        # 3. Upload AAB
        version_code = upload_aab(headers, edit_id, aab)

        # 4. Set track - try highest available
        if target_track:
            tracks_to_try = [target_track]
        else:
            tracks_to_try = ["production", "beta", "alpha", "internal"]

        released_track = None
        for track_name in tracks_to_try:
            print(f"\nTrying {track_name} track...")
            result, resp = set_track(headers, edit_id, track_name, [version_code], status="completed")
            if result:
                print(f"Set {track_name} track with version code {version_code}")
                released_track = track_name
                break
            else:
                print(f"  {track_name}: unavailable ({resp.status_code})")

        if not released_track:
            print("\nERROR: Could not release to any track.")
            delete_edit(headers, edit_id)
            sys.exit(1)

        # 5. Commit
        print(f"\n=== Committing release to {released_track} ===")
        commit_edit(headers, edit_id)
        print(f"\nDone! Version code {version_code} released to {released_track} track.")

    except Exception:
        print("\nError occurred, cleaning up edit...")
        delete_edit(headers, edit_id)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description="Build and publish Android app to Google Play")
    parser.add_argument("--list", action="store_true", help="List current releases")
    parser.add_argument("--skip-build", action="store_true", help="Skip building, use existing AAB")
    parser.add_argument("--track", type=str, default=None, help="Target track (production/beta/alpha/internal)")
    args = parser.parse_args()

    if args.list:
        cmd_list()
    else:
        cmd_publish(skip_build=args.skip_build, target_track=args.track)


if __name__ == "__main__":
    main()
