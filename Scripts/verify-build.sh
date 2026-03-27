#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Building and bundling..." >&2
"${ROOT_DIR}/Scripts/package-app.sh" \
    --configuration debug \
    --entitlements "NiceVoice.entitlements"

echo "Restarting app..." >&2
killall -9 NiceVoice 2>/dev/null || true
sleep 1
open -n "${ROOT_DIR}/.build/bundler/NiceVoice.app"

echo "Build verified and app restarted." >&2
