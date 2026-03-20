You are publishing a new Android release to Google Play. Follow these steps carefully.

## Prerequisites

Before starting, confirm these exist:
- `android/release.keystore` — the release signing keystore
- `android/play-store-key.json` — the Google Cloud service account JSON key for Play Store uploads
- `android/local.properties` — must contain `RELEASE_STORE_FILE`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, `RELEASE_KEY_PASSWORD`
- `.env` — must contain `PEPPER` and `ANDROID_MAPS_API_KEY`

Check for each file. If any are missing, STOP and tell the user which files are missing and what they need to contain. Do NOT proceed without all prerequisites.

## Step 1: Ensure clean main branch

Run these checks and STOP if any fail:
```
git fetch origin
```

1. Verify you're on `main`: `git branch --show-current` must output `main`. If not, ask the user to switch.
2. Verify working tree is clean: `git status --porcelain` must be empty. If not, ask the user to commit or stash.
3. Verify in sync with origin: `git rev-parse HEAD` must equal `git rev-parse origin/main`. If behind, ask the user to pull. If ahead, ask the user to push first.

## Step 2: Bump version

Read `android/app/build.gradle.kts` and find the current `versionCode` and `versionName`. Show the user the current values and ask what the new version should be. Increment `versionCode` by 1. For `versionName`, ask the user or suggest a sensible bump.

After the user confirms, update both values in `build.gradle.kts`.

**Important**: Google Play rejects uploads where the `versionCode` is not strictly greater than the currently published version. Always increment.

## Step 3: Commit and push the version bump

Stage and commit the version change, then push to main:
```
git add android/app/build.gradle.kts
git commit -m "Bump Android version to <versionName> (code <versionCode>)"
git push origin main
```

## Step 4: Tag and push

Create an `android-vXXX` tag on the current SHA and push it. This triggers the CI release workflow.

```
git tag android-v<versionCode>
git push origin android-v<versionCode>
```

The tag push triggers `.github/workflows/release.yml`, which will:
1. Run unit tests
2. Build a signed release AAB
3. Upload to Google Play
4. Create a release on the highest available track

## Step 5: Report

Tell the user:
- The version that will be uploaded (versionName + versionCode)
- The tag that was created and pushed (`android-v<versionCode>`)
- That CI will build, upload, and release automatically
- They can monitor the workflow run on GitHub Actions
- The release will go to the highest available track (production > beta > alpha > internal)
