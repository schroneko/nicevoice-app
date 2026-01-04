#!/bin/bash

echo "🔨 Building (step 1/2: compile)..."
if ! swift build --product NiceVoice 2>&1 | grep -v "disk I/O error"; then
    echo "❌ Build failed"
    exit 1
fi

if [ ! -f .build/debug/NiceVoice ]; then
    echo "❌ Build output not found"
    exit 1
fi

echo "📦 Building (step 2/2: bundle)..."
~/.mint/bin/swift-bundler bundle --skip-build --products-directory .build/debug 2>&1 | grep -v "disk I/O error" || true

if [ ! -d .build/bundler/NiceVoice.app ]; then
    echo "❌ Bundle not created"
    exit 1
fi

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
