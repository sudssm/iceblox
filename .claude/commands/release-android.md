You are publishing a new Android release to Google Play. Follow these steps carefully.

## Prerequisites

Before starting, confirm these exist:
- `android/release.keystore` — the release signing keystore
- `android/play-store-key.json` — the Google Cloud service account JSON key for Play Store uploads
- `android/local.properties` — must contain `RELEASE_STORE_FILE`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, `RELEASE_KEY_PASSWORD`
- `.env` — must contain `PEPPER` and `ANDROID_MAPS_API_KEY`

Check for each file. If any are missing, STOP and tell the user which files are missing and what they need to contain. Do NOT proceed without all prerequisites.

## Step 1: Fetch latest main

Run:
```
git fetch origin main
```

This ensures we have the latest `origin/main` ref. You do NOT need to be on the `main` branch — the tag will be placed on `origin/main`'s HEAD.

## Step 2: Bump version

Read `android/app/build.gradle.kts` and find the current `versionCode` and `versionName`. Show the user the current values and ask what the new version should be. Increment `versionCode` by 1. For `versionName`, ask the user or suggest a sensible bump.

After the user confirms, update both values in `build.gradle.kts`.

**Important**: Google Play rejects uploads where the `versionCode` is not strictly greater than the currently published version. Always increment.

## Step 3: Commit and push the version bump

Stage and commit the version change, then push to the current branch:
```
git add android/app/build.gradle.kts
git commit -m "Bump Android version to <versionName> (code <versionCode>)"
git push
```

Tell the user they need to merge this version bump commit to `main` before Step 4 (e.g., via PR or direct push). STOP and wait for confirmation that it's on main.

## Step 4: Tag and push

Create an `android-vXXX` tag on the latest `origin/main` commit and push it. This triggers the CI release workflow.

```
git fetch origin main
git tag android-v<versionCode> origin/main
git push origin android-v<versionCode>
```

The tag push triggers `.github/workflows/release.yml`, which will:
1. Run unit tests
2. Build a signed release AAB
3. Upload to Google Play
4. Create a release on the highest available track

## Step 5: Monitor CI

After pushing the tag, watch the workflow run until it completes:

```
gh run list --workflow=release.yml --limit=1
```

Find the run triggered by the tag push, then watch it:

```
gh run watch <run-id>
```

When the run completes:
- If **successful**: tell the user the release succeeded, including the version (versionName + versionCode), the tag (`android-v<versionCode>`), and which track it was released to.
- If **failed**: run `gh run view <run-id> --log-failed` to get the failure logs. Show the user the relevant error output and suggest next steps to fix it.
