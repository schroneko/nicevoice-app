#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT="NiceVoice"
CONFIGURATION="debug"
VERSION=""
SIGN_IDENTITY="${NICEVOICE_SIGN_IDENTITY:-}"
ENTITLEMENTS=""
COPY_DEST=""
LAUNCH_AFTER_BUILD=0

usage() {
    cat <<'EOF'
Usage: ./Scripts/package-app.sh [options]

Options:
  --configuration <debug|release>  Build configuration (default: debug)
  --version <version>              CFBundleShortVersionString / CFBundleVersion
  --sign-identity <identity>       codesign identity (use "-" for ad-hoc signing)
  --entitlements <path>            entitlements plist for codesign
  --copy-to <path>                 copy bundled app to destination
  --launch                         launch the bundled app after packaging
EOF
}

read_default_version() {
    sed -n "s/^version = '\\(.*\\)'/\\1/p" "${ROOT_DIR}/Bundler.toml" | head -n 1
}

set_plist_value() {
    local plist="$1"
    local type="$2"
    local key="$3"
    local value="$4"

    /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "${plist}" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :${key} ${type} ${value}" "${plist}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --sign-identity)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --entitlements)
            ENTITLEMENTS="$2"
            shift 2
            ;;
        --copy-to)
            COPY_DEST="$2"
            shift 2
            ;;
        --launch)
            LAUNCH_AFTER_BUILD=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "${CONFIGURATION}" != "debug" && "${CONFIGURATION}" != "release" ]]; then
    echo "Invalid configuration: ${CONFIGURATION}" >&2
    exit 1
fi

if [[ -z "${VERSION}" ]]; then
    VERSION="$(read_default_version)"
fi

if [[ -z "${VERSION}" ]]; then
    echo "Version could not be determined from Bundler.toml" >&2
    exit 1
fi

cd "${ROOT_DIR}"

PRODUCTS_DIR=".build/arm64-apple-macosx/${CONFIGURATION}"
APP_PATH=".build/bundler/${PRODUCT}.app"
PLIST_PATH="${APP_PATH}/Contents/Info.plist"

echo "==> Building ${PRODUCT} (${CONFIGURATION})..."
if [[ "${CONFIGURATION}" == "debug" ]]; then
    swift build --product "${PRODUCT}"
else
    swift build -c release --product "${PRODUCT}"
fi

if [[ ! -f "${PRODUCTS_DIR}/${PRODUCT}" ]]; then
    echo "Build output not found: ${PRODUCTS_DIR}/${PRODUCT}" >&2
    exit 1
fi

echo "==> Bundling app..."
mint run stackotter/swift-bundler bundle --skip-build --products-directory "${PRODUCTS_DIR}"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "Bundle not created: ${APP_PATH}" >&2
    exit 1
fi

echo "==> Copying Server resources..."
rm -rf "${APP_PATH}/Contents/Resources/Server"
cp -R Server "${APP_PATH}/Contents/Resources/Server"

echo "==> Compiling localizations..."
xcrun xcstringstool compile Sources/NiceVoice/Resources/Localizable.xcstrings -o "${APP_PATH}/Contents/Resources"

echo "==> Updating Info.plist..."
set_plist_value "${PLIST_PATH}" string "CFBundleIdentifier" "app.nicevoice.NiceVoice"
set_plist_value "${PLIST_PATH}" string "CFBundleShortVersionString" "${VERSION}"
set_plist_value "${PLIST_PATH}" string "CFBundleVersion" "${VERSION}"
set_plist_value "${PLIST_PATH}" string "NSMicrophoneUsageDescription" "音声入力のためにマイクを使用します"
set_plist_value "${PLIST_PATH}" string "NSSpeechRecognitionUsageDescription" "音声をテキストに変換するために使用します"
set_plist_value "${PLIST_PATH}" string "NSAppleEventsUsageDescription" "テキストを入力欄に貼り付けるために使用します"

/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "${PLIST_PATH}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string app.nicevoice.NiceVoice" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string nicevoice" "${PLIST_PATH}"

if [[ -n "${NICEVOICE_APPCAST_URL:-}" ]]; then
    set_plist_value "${PLIST_PATH}" string "SUFeedURL" "${NICEVOICE_APPCAST_URL}"
fi

if [[ -n "${NICEVOICE_SPARKLE_PUBLIC_KEY:-}" ]]; then
    set_plist_value "${PLIST_PATH}" string "SUPublicEDKey" "${NICEVOICE_SPARKLE_PUBLIC_KEY}"
fi

if [[ -n "${NICEVOICE_ENABLE_AUTOMATIC_CHECKS:-}" ]]; then
    set_plist_value "${PLIST_PATH}" bool "SUEnableAutomaticChecks" "${NICEVOICE_ENABLE_AUTOMATIC_CHECKS}"
fi

if [[ -n "${NICEVOICE_AUTOMATICALLY_UPDATE:-}" ]]; then
    set_plist_value "${PLIST_PATH}" bool "SUAutomaticallyUpdate" "${NICEVOICE_AUTOMATICALLY_UPDATE}"
fi

if [[ -n "${SIGN_IDENTITY}" ]]; then
    echo "==> Signing app..."
    CODESIGN_ARGS=(codesign -fs "${SIGN_IDENTITY}" --deep --options runtime)
    if [[ -n "${ENTITLEMENTS}" ]]; then
        CODESIGN_ARGS+=(--entitlements "${ENTITLEMENTS}")
    fi
    CODESIGN_ARGS+=("${APP_PATH}")
    "${CODESIGN_ARGS[@]}"
fi

if [[ -n "${COPY_DEST}" ]]; then
    echo "==> Copying app to ${COPY_DEST}..."
    rm -rf "${COPY_DEST}"
    cp -R "${APP_PATH}" "${COPY_DEST}"
fi

if [[ "${LAUNCH_AFTER_BUILD}" == "1" ]]; then
    TARGET_PATH="${COPY_DEST:-${APP_PATH}}"
    echo "==> Launching ${TARGET_PATH}..."
    open "${TARGET_PATH}"
fi

echo "Packaged app: ${APP_PATH}"
