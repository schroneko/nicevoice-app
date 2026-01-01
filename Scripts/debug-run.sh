#!/bin/bash
set -e

echo "🔨 Building..."
~/.mint/bin/swift-bundler bundle 2>&1 | grep -v "disk I/O error" || true

echo "🔏 Signing..."
codesign -fs "NiceVoice" --deep .build/bundler/NiceVoice.app

echo "🛑 Killing existing process..."
killall -9 NiceVoice 2>/dev/null || true

echo "🚀 Launching with log tail..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Logs will appear below. Press Ctrl+C to stop."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Launch app in background
open .build/bundler/NiceVoice.app

# Wait a moment for app to start
sleep 1

# Tail the log file
tail -f ~/Library/Logs/NiceVoice/debug.log
