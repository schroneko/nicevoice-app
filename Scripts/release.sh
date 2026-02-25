#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>}"
PRODUCT="NiceVoice"
ARCHIVE="${PRODUCT}-${VERSION}.zip"
APP=".build/bundler/${PRODUCT}.app"
PLIST="${APP}/Contents/Info.plist"

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

echo "==> Patching Info.plist..."
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string app.nicevoice.NiceVoice" "${PLIST}" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.nicevoice.NiceVoice" "${PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${PLIST}" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string Uses microphone for voice input" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSSpeechRecognitionUsageDescription string Converts speech to text" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string Pastes text into input fields" "${PLIST}" 2>/dev/null || true

echo "==> Signing (ad-hoc)..."
codesign -fs - --deep "${APP}"

echo "==> Creating ${ARCHIVE}..."
ditto -c -k --keepParent "${APP}" "${ARCHIVE}"

SHA=$(shasum -a 256 "${ARCHIVE}" | cut -d' ' -f1)

echo ""
echo "Created: ${ARCHIVE}"
echo "Size:    $(du -h "${ARCHIVE}" | cut -f1)"
echo "SHA256:  ${SHA}"
echo ""
echo "To publish:"
echo "  git tag v${VERSION}"
echo "  git push origin v${VERSION}"
echo "  gh release create v${VERSION} ${ARCHIVE} --title \"v${VERSION}\""
