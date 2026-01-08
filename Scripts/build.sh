#!/bin/bash
set -e

cd "$(dirname "$0")/.."

swift build --product NiceVoice || true
swift-bundler bundle --skip-build --products-directory .build/arm64-apple-macosx/debug

killall -9 NiceVoice 2>/dev/null || true

codesign -fs "NiceVoice" --deep .build/bundler/NiceVoice.app

rm -rf /Applications/NiceVoice.app
cp -R .build/bundler/NiceVoice.app /Applications/

open /Applications/NiceVoice.app
