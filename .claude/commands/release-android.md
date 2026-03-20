You are publishing a new Android release to Google Play. Follow these steps carefully.

## Prerequisites

The build and signing happen in CI, so signing keys and local properties are NOT required locally. Only confirm that CI secrets are configured (they are stored as GitHub Actions secrets/variables).

No local file checks are needed — proceed directly to Step 1.

## Step 1: Bump version

Read `android/app/build.gradle.kts` and find the current `versionCode` and `versionName`. Increment `versionCode` by 1 and bump `versionName` appropriately. Show the user the current and new values and ask for confirmation before proceeding.

**Important**: Google Play rejects uploads where the `versionCode` is not strictly greater than the currently published version. Always increment.

## Step 2: Commit, tag, and push to main

After the user confirms the version bump:

1. Stage the change
2. Commit with the message `Release Android v<versionCode>`
3. Tag the commit `android-v<versionCode>`
4. Push the commit and tag directly to main

```
git add android/app/build.gradle.kts
git commit -m "Release Android v<versionCode>"
git tag android-v<versionCode>
git push origin HEAD:main android-v<versionCode>
```

The tag push triggers `.github/workflows/release.yml`, which will:
1. Run unit tests
2. Build a signed release AAB
3. Upload to Google Play
4. Create a release on the highest available track

## Step 3: Monitor CI

After pushing, watch the workflow run until it completes:

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
