You are publishing a new iOS release to the App Store. Follow these steps carefully.

## Prerequisites

The build and signing happen in CI (macOS runner with Xcode), so local Xcode signing is NOT required. Only confirm that CI secrets are configured (they are stored as GitHub Actions secrets/variables).

No local file checks are needed — proceed directly to Step 1.

## Step 1: Bump version

Read `ios/IceBloxApp.xcodeproj/project.pbxproj` and find the current `CURRENT_PROJECT_VERSION` (build number) and `MARKETING_VERSION` (user-facing version like "1.1"). Increment `CURRENT_PROJECT_VERSION` by 1 and bump `MARKETING_VERSION` if needed. Show the user the current and new values and ask for confirmation before proceeding.

**Important**: App Store Connect rejects uploads where the build number is not strictly greater than the last uploaded build. Always increment `CURRENT_PROJECT_VERSION`. Use `replace_all` when editing since these values appear in multiple build configurations.

## Step 2: Check App Store Connect status

Before proceeding, check whether there's a pending release that's currently in review:

```
cd ios && python3 publish.py --list
```

- If there's a version **in review for more than 6 hours**, warn the user: "Version X.Y has been in review for N hours. Replacing the build will remove it from review and restart the review process. Continue?"
- If there's a version in review for **less than 6 hours**, proceed without warning (review likely hasn't started).
- If there's **no pending version** (latest is live), the script will create a new version automatically.

Wait for the user's confirmation before proceeding.

## Step 3: Commit, tag, and push to main

After the user confirms:

1. Stage the change
2. Commit with the message `Release iOS v<CURRENT_PROJECT_VERSION>`
3. Tag the commit `ios-v<CURRENT_PROJECT_VERSION>`
4. Push the commit and tag directly to main

```
git add ios/IceBloxApp.xcodeproj/project.pbxproj
git commit -m "Release iOS v<CURRENT_PROJECT_VERSION>"
git tag ios-v<CURRENT_PROJECT_VERSION>
git push origin HEAD:main ios-v<CURRENT_PROJECT_VERSION>
```

The tag push triggers `.github/workflows/release.yml`, which will:
1. Run iOS unit tests
2. Build a signed release IPA (with framework MinimumOSVersion patching)
3. Upload to App Store Connect
4. Wait for build processing
5. Attach to the pending version (or create one)
6. Submit for App Review

## Step 4: Monitor CI

After pushing, watch the workflow run until it completes:

```
gh run list --workflow=release.yml --limit=1
```

Find the run triggered by the tag push, then watch it:

```
gh run watch <run-id>
```

When the run completes:
- If **successful**: tell the user the release succeeded, including the version (MARKETING_VERSION + CURRENT_PROJECT_VERSION), the tag (`ios-v<CURRENT_PROJECT_VERSION>`), and that it was submitted for App Review.
- If **failed**: run `gh run view <run-id> --log-failed` to get the failure logs. Show the user the relevant error output and suggest next steps to fix it.
