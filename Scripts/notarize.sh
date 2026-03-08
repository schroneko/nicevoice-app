#!/bin/bash
set -euo pipefail

ARCHIVE_PATH="${1:?Usage: ./Scripts/notarize.sh <archive.zip> [app-path]}"
APP_PATH="${2:-}"

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
    echo "Archive not found: ${ARCHIVE_PATH}" >&2
    exit 1
fi

submit_notarytool() {
    if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
        xcrun notarytool submit "${ARCHIVE_PATH}" --keychain-profile "${NOTARYTOOL_PROFILE}" --wait
        return
    fi

    if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
        echo "Set NOTARYTOOL_PROFILE or APPLE_ID / APPLE_TEAM_ID / APPLE_APP_SPECIFIC_PASSWORD" >&2
        exit 1
    fi

    xcrun notarytool submit "${ARCHIVE_PATH}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
        --wait
}

echo "==> Submitting ${ARCHIVE_PATH} for notarization..."
submit_notarytool

if [[ -n "${APP_PATH}" ]]; then
    if [[ ! -d "${APP_PATH}" ]]; then
        echo "App not found for stapling: ${APP_PATH}" >&2
        exit 1
    fi

    echo "==> Stapling ticket to ${APP_PATH}..."
    xcrun stapler staple "${APP_PATH}"
    echo "==> Verifying notarized app..."
    spctl -a -vv "${APP_PATH}"
fi
