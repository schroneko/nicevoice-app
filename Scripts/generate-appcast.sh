#!/bin/bash
set -euo pipefail

UPDATES_DIR="${1:?Usage: ./Scripts/generate-appcast.sh <updates-dir> [archive.zip]}"
ARCHIVE_PATH="${2:-}"

resolve_generate_appcast() {
    if [[ -n "${SPARKLE_BIN_DIR:-}" && -x "${SPARKLE_BIN_DIR}/generate_appcast" ]]; then
        echo "${SPARKLE_BIN_DIR}/generate_appcast"
        return
    fi

    if command -v generate_appcast >/dev/null 2>&1; then
        command -v generate_appcast
        return
    fi

    if [[ -x ".build/checkouts/Sparkle/bin/generate_appcast" ]]; then
        echo ".build/checkouts/Sparkle/bin/generate_appcast"
        return
    fi

    echo "generate_appcast not found. Set SPARKLE_BIN_DIR or fetch Sparkle package tools." >&2
    exit 1
}

mkdir -p "${UPDATES_DIR}"

if [[ -n "${ARCHIVE_PATH}" ]]; then
    cp "${ARCHIVE_PATH}" "${UPDATES_DIR}/"
fi

GENERATE_APPCAST_BIN="$(resolve_generate_appcast)"

echo "==> Generating appcast in ${UPDATES_DIR}..."
"${GENERATE_APPCAST_BIN}" "${UPDATES_DIR}"

echo "Appcast generated: ${UPDATES_DIR}/appcast.xml"
