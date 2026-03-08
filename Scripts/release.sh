#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>}"
PRODUCT="NiceVoice"
ARCHIVE="${PRODUCT}-${VERSION}.zip"
APP=".build/bundler/${PRODUCT}.app"
HOMEBREW_TAP_DIR="${HOME}/Sync/homebrew-tap"
CASK_FILE="${HOMEBREW_TAP_DIR}/Casks/nicevoice.rb"
NICEVOICE_DIR="$(pwd)"

echo "==> Updating Bundler.toml version to ${VERSION}..."
sed -i '' "s/^version = '.*'/version = '${VERSION}'/" Bundler.toml

echo "==> Building ${PRODUCT} v${VERSION} (release)..."
"${NICEVOICE_DIR}/Scripts/package-app.sh" \
    --configuration release \
    --version "${VERSION}" \
    --sign-identity "${NICEVOICE_SIGN_IDENTITY:--}" \
    --entitlements "NiceVoice-release.entitlements"

echo "==> Creating ${ARCHIVE}..."
rm -f "${ARCHIVE}"
ditto -c -k --keepParent "${APP}" "${ARCHIVE}"

if [[ "${NICEVOICE_NOTARIZE:-0}" == "1" ]]; then
    echo "==> Notarizing archive..."
    "${NICEVOICE_DIR}/Scripts/notarize.sh" "${ARCHIVE}" "${APP}"
fi

if [[ "${NICEVOICE_GENERATE_APPCAST:-0}" == "1" ]]; then
    echo "==> Generating appcast..."
    "${NICEVOICE_DIR}/Scripts/generate-appcast.sh" "${NICEVOICE_UPDATES_DIR:-${NICEVOICE_DIR}/Updates}" "${ARCHIVE}"
fi

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
