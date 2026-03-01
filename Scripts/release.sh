#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>}"
PRODUCT="NiceVoice"
ARCHIVE="${PRODUCT}-${VERSION}.zip"
APP=".build/bundler/${PRODUCT}.app"
PLIST="${APP}/Contents/Info.plist"
HOMEBREW_TAP_DIR="${HOME}/Sync/homebrew-tap"
CASK_FILE="${HOMEBREW_TAP_DIR}/Casks/nicevoice.rb"
NICEVOICE_DIR="$(pwd)"

echo "==> Updating Bundler.toml version to ${VERSION}..."
sed -i '' "s/^version = '.*'/version = '${VERSION}'/" Bundler.toml

echo "==> Building ${PRODUCT} v${VERSION} (release)..."
swift build -c release --product "${PRODUCT}" 2>&1 | grep -v "disk I/O error"

if [ ! -f ".build/release/${PRODUCT}" ]; then
    echo "Build output not found"
    exit 1
fi

echo "==> Bundling..."
mint run stackotter/swift-bundler bundle --skip-build --products-directory .build/arm64-apple-macosx/release 2>&1 | grep -v "disk I/O error" || true

if [ ! -d "${APP}" ]; then
    echo "Bundle not created"
    exit 1
fi

echo "==> Copying Server resources..."
cp -R Server "${APP}/Contents/Resources/Server"

echo "==> Compiling localizations..."
xcrun xcstringstool compile Sources/NiceVoice/Resources/Localizable.xcstrings -o "${APP}/Contents/Resources"

echo "==> Patching Info.plist..."
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string app.nicevoice.NiceVoice" "${PLIST}" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.nicevoice.NiceVoice" "${PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${PLIST}" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string Uses microphone for voice input" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSSpeechRecognitionUsageDescription string Converts speech to text" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string Pastes text into input fields" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string app.nicevoice.NiceVoice" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string nicevoice" "${PLIST}" 2>/dev/null || true

echo "==> Signing (ad-hoc)..."
codesign -fs - --deep --options runtime --entitlements NiceVoice-release.entitlements "${APP}"

echo "==> Creating ${ARCHIVE}..."
ditto -c -k --keepParent "${APP}" "${ARCHIVE}"

SHA=$(shasum -a 256 "${ARCHIVE}" | cut -d' ' -f1)

echo ""
echo "Created: ${ARCHIVE}"
echo "Size:    $(du -h "${ARCHIVE}" | cut -f1)"
echo "SHA256:  ${SHA}"

echo ""
echo "==> Updating homebrew-tap Cask..."

if [ ! -f "${CASK_FILE}" ]; then
    echo "Cask file not found: ${CASK_FILE}"
    exit 1
fi

sed -i '' "s/^  version \".*\"/  version \"${VERSION}\"/" "${CASK_FILE}"
sed -i '' "s/^  sha256 .*/  sha256 \"${SHA}\"/" "${CASK_FILE}"
sed -i '' 's|^  url ".*"|  url "https://github.com/schroneko/homebrew-tap/releases/download/v#{version}/NiceVoice-#{version}.zip"|' "${CASK_FILE}"

echo "Updated: ${CASK_FILE}"

echo "==> Committing homebrew-tap changes..."
pushd "${HOMEBREW_TAP_DIR}" > /dev/null

BRANCH="release/nicevoice-v${VERSION}"
git switch -c "${BRANCH}"
git add Casks/nicevoice.rb
git commit -m "Update NiceVoice to v${VERSION}"
git switch main
git merge "${BRANCH}"
git branch -d "${BRANCH}"
git push

echo "==> Managing GitHub Release..."
gh release delete "v${VERSION}" --repo schroneko/homebrew-tap --yes 2>/dev/null || true
git push origin --delete "v${VERSION}" 2>/dev/null || true

gh release create "v${VERSION}" "${NICEVOICE_DIR}/${ARCHIVE}" \
    --title "v${VERSION}" \
    --notes "NiceVoice v${VERSION}" \
    --repo schroneko/homebrew-tap

popd > /dev/null

echo ""
echo "Done! homebrew-tap updated and release created."
echo ""
echo "To tag nicevoice-app (manual):"
echo "  git tag v${VERSION}"
echo "  git push origin v${VERSION}"
echo ""
echo "To verify:"
echo "  brew reinstall --cask schroneko/tap/nicevoice"
