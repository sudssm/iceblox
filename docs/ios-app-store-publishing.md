# iOS App Store Publishing

## Prerequisites

- Apple Developer Program membership ($99/year)
- App created in [App Store Connect](https://appstoreconnect.apple.com)
- App Store Connect API key (for CLI uploads)

### API Key Setup

1. Go to **Users and Access > Integrations > App Store Connect API**
2. Generate a key with **Admin** or **App Manager** role
3. Add to `.env`:
   ```
   APP_STORE_KEY_ID=<key-id>
   APP_STORE_ISSUER_ID=<issuer-id>
   APP_STORE_KEY_P8="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
   ```

## Build & Upload

```bash
# Archive, patch frameworks, and export IPA
make package-ios

# Upload to App Store Connect
make publish-ios
```

### What `package-ios` does

1. Creates an `ExportOptions.plist` for app-store-connect distribution
2. Runs `xcodebuild archive` with automatic signing
3. **Patches embedded framework Info.plists** — sets `MinimumOSVersion` to match the app's deployment target. This fixes Apple error 90208 where SPM xcframeworks (e.g., onnxruntime) have stale `MinimumOSVersion` values in their plists that don't match the recompiled binary's `minos`.
4. Runs `xcodebuild -exportArchive` to produce the IPA

### What `publish-ios` does

1. Writes the API key `.p8` to `~/private_keys/` (where `altool` expects it)
2. Runs `xcrun altool --upload-app` to upload the IPA

### Build Numbers

Apple rejects duplicate version+build combinations. The build number lives in the Xcode project:

```
CURRENT_PROJECT_VERSION = N  (in project.pbxproj)
```

Bump this before each upload. The marketing version (`MARKETING_VERSION`) stays at `1.0` until you're ready for a version bump.

## App Store Connect Setup

### Required Fields (Distribution > iOS App Version)

| Field | Notes |
|-------|-------|
| Screenshots | 4+ screenshots at 1284×2778 (iPhone 6.5" display). Use `scripts/simulator/appstore_screenshots.sh` |
| Promotional Text | Short marketing pitch (can change without new review) |
| Description | Full feature description |
| Keywords | Comma-separated, 100 char max |
| Support URL | Link to support page or GitHub repo |
| Copyright | e.g., `2026 Your Name` |
| Build | Select from uploaded builds (appears after processing) |

### App Review Information

- **Sign-in required**: Uncheck if the app doesn't need login
- **Contact**: First name, last name, phone, email
- **Notes**: Explain anything non-obvious to reviewers (e.g., "Grant location permission to see the map")

### App Privacy (Trust & Safety > App Privacy)

1. Set **Privacy Policy URL** (required)
2. Click **Get Started** under Data Types
3. Select **"Yes, we collect data"**
4. Check applicable data types:
   - **Precise Location** — if the app uses lat/lng
   - **Device ID** — if the app registers push notification tokens (APNs)
5. For each data type, complete the follow-up:
   - **How is it used?** (e.g., "App Functionality")
   - **Is it linked to the user's identity?** (typically No for anonymous usage)
6. Click **Publish**

## Common Errors

### 90208: Invalid Bundle — framework MinimumOSVersion mismatch

**Cause**: SPM xcframeworks (like onnxruntime) ship with a `MinimumOSVersion` in their `Info.plist` that's lower than the app's deployment target. Xcode recompiles the binary with the app's `minos` but doesn't update the framework's plist, causing a mismatch Apple rejects.

**Fix**: The `package-ios` target includes a post-archive step that patches all embedded framework plists to match the app's `MinimumOSVersion`.

### Build not appearing in App Store Connect

After `publish-ios` succeeds, builds take **5-15 minutes** to process. Check the **TestFlight > iOS Builds** page — failed builds show under "Build Uploads" with error details. Successful builds appear under "Builds" in the sidebar.

### Screenshots dimension error

App Store requires specific dimensions. For iPhone 6.5" display: **1284×2778** or **2778×1284**. Use the iPhone 14 Plus simulator (or equivalent) which outputs this resolution.

## App Store Screenshots

The `scripts/simulator/appstore_screenshots.sh` script captures 4 screenshots:

1. **Splash** — the app's home screen
2. **Camera** — dashcam view with injected test image
3. **Map** — map view with hardcoded pins and notification overlay
4. **Report** — ICE report form

It builds with `-DAPPSTORE_SCREENSHOTS` flag which activates hardcoded data in `MapView.swift` (pins, camera region, notification banner overlay) instead of fetching from the server.

The camera screenshot uses a demo dashcam image. The script looks for it at `.context/attachments/image-v2.png` first, then falls back to the checked-in copy at `scripts/simulator/assets/dashcam-demo.png`.

Output goes to `.context/screenshots/`.

## Submission Checklist

- [ ] Screenshots uploaded (correct dimensions)
- [ ] Promotional text, description, keywords filled
- [ ] Support URL set
- [ ] Copyright set
- [ ] Build uploaded and processed successfully
- [ ] Build selected on version page
- [ ] App Review contact info filled
- [ ] App Privacy completed and published
- [ ] Export compliance answered (select "No" for standard HTTPS)
- [ ] Click "Add for Review"
