# NiceVoice Release Flow

## Required inputs

- `NICEVOICE_SIGN_IDENTITY`
  - Example: `Developer ID Application: Your Name (TEAMID)`
- `NICEVOICE_APPCAST_URL`
  - Sparkle feed URL, for example `https://nicevoice.app/appcast.xml`
- `NICEVOICE_SPARKLE_PUBLIC_KEY`
  - Sparkle EdDSA public key

Optional:

- `NICEVOICE_NOTARIZE=1`
- `NOTARYTOOL_PROFILE`
  - Preferred. Or use `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`
- `NICEVOICE_GENERATE_APPCAST=1`
- `NICEVOICE_UPDATES_DIR=/path/to/updates`
- `SPARKLE_BIN_DIR=/path/to/Sparkle/bin`

## Build a local release bundle

```bash
./Scripts/package-app.sh \
  --configuration release \
  --version 0.1.5 \
  --sign-identity "${NICEVOICE_SIGN_IDENTITY}" \
  --entitlements NiceVoice-release.entitlements
```

## Full release

```bash
NICEVOICE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NICEVOICE_APPCAST_URL="https://nicevoice.app/appcast.xml" \
NICEVOICE_SPARKLE_PUBLIC_KEY="YOUR_PUBLIC_KEY" \
NICEVOICE_NOTARIZE=1 \
NICEVOICE_GENERATE_APPCAST=1 \
./Scripts/release.sh 0.1.5
```

## Notes

- `Scripts/package-app.sh` is now the single path that handles bundling, Server resource copying, localization compilation, plist patching, and Sparkle plist injection.
- `Scripts/notarize.sh` submits the generated zip and staples the app when an app path is provided.
- `Scripts/generate-appcast.sh` expects Sparkle's `generate_appcast` tool either in `SPARKLE_BIN_DIR`, on `PATH`, or under `.build/checkouts/Sparkle/bin`.
- Access mode changes are documented in [access-modes.md](/Users/username/Sync/nicevoice-app/docs/access-modes.md).
- Update the public operator information in [commercial.html](/Users/username/Sync/nicevoice-app/landing/commercial.html) before publishing the legal pages.
