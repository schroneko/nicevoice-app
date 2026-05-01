#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DEST="${NICEVOICE_INSTALL_DEST:-}"

if [[ -z "${INSTALL_DEST}" ]]; then
    if [[ -w "/Applications" ]]; then
        INSTALL_DEST="/Applications/NiceVoice.app"
    else
        mkdir -p "${HOME}/Applications"
        INSTALL_DEST="${HOME}/Applications/NiceVoice.app"
    fi
fi

killall -9 NiceVoice 2>/dev/null || true
pkill -f "managed-by nicevoice" 2>/dev/null || true
sleep 1

echo "Building and bundling..." >&2
"${ROOT_DIR}/Scripts/package-app.sh" \
    --configuration debug \
    --copy-to "${INSTALL_DEST}" \
    --entitlements "NiceVoice.entitlements"

echo "Restarting app..." >&2
killall -9 NiceVoice 2>/dev/null || true
sleep 1
open -n "${INSTALL_DEST}"

echo "Build verified and app restarted from ${INSTALL_DEST}." >&2
