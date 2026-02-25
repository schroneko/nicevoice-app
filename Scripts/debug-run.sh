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
mint run stackotter/swift-bundler bundle --skip-build --products-directory .build/arm64-apple-macosx/debug 2>&1 | grep -v "disk I/O error" || true

if [ ! -d .build/bundler/NiceVoice.app ]; then
    echo "❌ Bundle not created"
    exit 1
fi

echo "📦 Copying Server resources..."
cp -R Server .build/bundler/NiceVoice.app/Contents/Resources/Server

echo "📝 Patching Info.plist..."
PLIST=".build/bundler/NiceVoice.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string app.nicevoice.NiceVoice" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.nicevoice.NiceVoice" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 音声入力のためにマイクを使用します" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSSpeechRecognitionUsageDescription string 音声をテキストに変換するために使用します" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string テキストを入力欄に貼り付けるために使用します" "$PLIST" 2>/dev/null || true

echo "🔏 Signing..."
codesign -fs "NiceVoice" --deep .build/bundler/NiceVoice.app

echo "🛑 Killing existing process..."
killall -9 NiceVoice 2>/dev/null || true

echo "📂 Installing to /Applications..."
rm -rf /Applications/NiceVoice.app
cp -R .build/bundler/NiceVoice.app /Applications/

echo "🚀 Launching with log tail..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Logs will appear below. Press Ctrl+C to stop."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Launch from /Applications (TCC recognizes this path)
open /Applications/NiceVoice.app

# Wait a moment for app to start
sleep 1

# Tail the log file
tail -f ~/Library/Logs/NiceVoice/debug.log
