#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

killall -9 NiceVoice 2>/dev/null || true

"${ROOT_DIR}/Scripts/package-app.sh" \
    --configuration debug \
    --sign-identity "NiceVoice" \
    --copy-to "/Applications/NiceVoice.app" \
    --launch
