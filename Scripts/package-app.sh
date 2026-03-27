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

sign_nested_code() {
    local sign_identity="$1"
    local frameworks_dir="$2"
    local -a sign_args=(codesign -fs "${sign_identity}")

    if [[ "${CONFIGURATION}" == "release" && "${sign_identity}" != "-" ]]; then
        sign_args+=(--options runtime)
    fi

    if [[ ! -d "${frameworks_dir}" ]]; then
        return
    fi

    while IFS= read -r executable; do
        "${sign_args[@]}" "${executable}"
    done < <(
        find "${frameworks_dir}" -type f -perm -111 \
            | awk '{ print length($0) " " $0 }' \
            | sort -rn \
            | cut -d' ' -f2-
    )

    while IFS= read -r bundle; do
        "${sign_args[@]}" "${bundle}"
    done < <(
        find "${frameworks_dir}" \( -name "*.app" -o -name "*.xpc" -o -name "*.framework" \) -type d \
            | awk '{ print length($0) " " $0 }' \
            | sort -rn \
            | cut -d' ' -f2-
    )
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
FRAMEWORKS_DIR="${APP_PATH}/Contents/Frameworks"
BINARY_PATH="${APP_PATH}/Contents/MacOS/${PRODUCT}"

validate_bundle() {
    local app_path="$1"
    local binary_path="$2"
    local frameworks_dir="$3"
    local sign_identity="$4"

    echo "==> Validating app bundle..."

    if otool -L "${binary_path}" | grep -q "Sparkle.framework"; then
        if [[ ! -d "${frameworks_dir}/Sparkle.framework" ]]; then
            echo "Validation failed: Sparkle.framework is linked but not bundled." >&2
            exit 1
        fi

        if ! otool -l "${binary_path}" | grep -q "@loader_path/../Frameworks"; then
            echo "Validation failed: ${PRODUCT} is missing @loader_path/../Frameworks rpath." >&2
            exit 1
        fi

        codesign --verify --strict "${frameworks_dir}/Sparkle.framework"
    fi

    if [[ -n "${sign_identity}" ]]; then
        codesign --verify --deep --strict "${app_path}"

        if [[ "${CONFIGURATION}" == "debug" ]]; then
            if codesign -dvv "${app_path}" 2>&1 | grep -q "flags=.*runtime"; then
                echo "Validation failed: debug app must not enable hardened runtime." >&2
                exit 1
            fi
        fi
    fi
}

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
if command -v mint >/dev/null 2>&1; then
    mint run stackotter/swift-bundler bundle --skip-build --products-directory "${PRODUCTS_DIR}"
elif command -v swift-bundler >/dev/null 2>&1; then
    swift-bundler bundle --skip-build --products-directory "${PRODUCTS_DIR}"
else
    echo "swift-bundler not found. Install it with 'mint install stackotter/swift-bundler' or ensure 'swift-bundler' is on PATH." >&2
    exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
    echo "Bundle not created: ${APP_PATH}" >&2
    exit 1
fi

echo "==> Copying Server resources..."
rm -rf "${APP_PATH}/Contents/Resources/Server"
cp -R Server "${APP_PATH}/Contents/Resources/Server"
find "${APP_PATH}/Contents/Resources/Server" -name ".venv" -type d -prune -exec rm -rf {} +

if [[ -d "${PRODUCTS_DIR}/Sparkle.framework" ]]; then
    echo "==> Copying Sparkle.framework..."
    mkdir -p "${FRAMEWORKS_DIR}"
    rm -rf "${FRAMEWORKS_DIR}/Sparkle.framework"
    ditto "${PRODUCTS_DIR}/Sparkle.framework" "${FRAMEWORKS_DIR}/Sparkle.framework"

    if ! otool -l "${APP_PATH}/Contents/MacOS/${PRODUCT}" | grep -q "@loader_path/../Frameworks"; then
        install_name_tool -add_rpath "@loader_path/../Frameworks" "${APP_PATH}/Contents/MacOS/${PRODUCT}"
    fi
fi

echo "==> Compiling localizations..."
xcrun xcstringstool compile Sources/NiceVoice/Resources/Localizable.xcstrings -o "${APP_PATH}/Contents/Resources"

echo "==> Updating Info.plist..."
set_plist_value "${PLIST_PATH}" string "CFBundleIdentifier" "app.nicevoice.NiceVoice"
set_plist_value "${PLIST_PATH}" string "CFBundleShortVersionString" "${VERSION}"
set_plist_value "${PLIST_PATH}" string "CFBundleVersion" "${VERSION}"
set_plist_value "${PLIST_PATH}" string "NSMicrophoneUsageDescription" "音声入力のためにマイクを使用します"
set_plist_value "${PLIST_PATH}" string "NSSpeechRecognitionUsageDescription" "音声をテキストに変換するために使用します"
set_plist_value "${PLIST_PATH}" string "NSAppleEventsUsageDescription" "テキストを入力欄に貼り付けるために使用します"


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
    sign_nested_code "${SIGN_IDENTITY}" "${FRAMEWORKS_DIR}"

    RESOURCE_SIGN_ARGS=(codesign -fs "${SIGN_IDENTITY}")
    if [[ "${CONFIGURATION}" == "release" && "${SIGN_IDENTITY}" != "-" ]]; then
        RESOURCE_SIGN_ARGS+=(--options runtime)
    fi
    while IFS= read -r bundle; do
        "${RESOURCE_SIGN_ARGS[@]}" "${bundle}"
    done < <(find "${APP_PATH}/Contents/Resources" -name "*.bundle" -type d 2>/dev/null)

    CODESIGN_ARGS=(codesign -fs "${SIGN_IDENTITY}")
    if [[ "${CONFIGURATION}" == "release" && "${SIGN_IDENTITY}" != "-" ]]; then
        CODESIGN_ARGS+=(--options runtime)
    fi
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

validate_bundle "${APP_PATH}" "${BINARY_PATH}" "${FRAMEWORKS_DIR}" "${SIGN_IDENTITY}"

if [[ "${LAUNCH_AFTER_BUILD}" == "1" ]]; then
    TARGET_PATH="${COPY_DEST:-${APP_PATH}}"
    echo "==> Launching ${TARGET_PATH}..."
    open "${TARGET_PATH}"
fi

echo "Packaged app: ${APP_PATH}"
