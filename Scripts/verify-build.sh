#!/bin/bash
set -o pipefail

CONSTANTS_FILE="Sources/NiceVoice/Constants.swift"
DEEPGRAM_KEY=$(op item get "DEEPGRAM_API_KEY" --fields credential --reveal --vault Automation 2>/dev/null || echo "")
if [ -n "$DEEPGRAM_KEY" ]; then
    sed -i '' "s/DEEPGRAM_API_KEY_PLACEHOLDER/$DEEPGRAM_KEY/" "$CONSTANTS_FILE"
fi

echo "Building (step 1/2: compile)..." >&2
if ! swift build --product NiceVoice 2>&1 | grep -v "disk I/O error"; then
    if [ -n "$DEEPGRAM_KEY" ]; then
        sed -i '' "s/$DEEPGRAM_KEY/DEEPGRAM_API_KEY_PLACEHOLDER/" "$CONSTANTS_FILE"
    fi
    echo "Build failed" >&2
    exit 1
fi

if [ -n "$DEEPGRAM_KEY" ]; then
    sed -i '' "s/$DEEPGRAM_KEY/DEEPGRAM_API_KEY_PLACEHOLDER/" "$CONSTANTS_FILE"
fi

if [ ! -f .build/debug/NiceVoice ]; then
    echo "Build output not found" >&2
    exit 1
fi

echo "Building (step 2/2: bundle)..." >&2
mint run stackotter/swift-bundler bundle --skip-build --products-directory .build/arm64-apple-macosx/debug 2>&1 | grep -v "disk I/O error" || true

if [ ! -d .build/bundler/NiceVoice.app ]; then
    echo "Bundle not created" >&2
    exit 1
fi

echo "Copying Server resources..." >&2
cp -R Server .build/bundler/NiceVoice.app/Contents/Resources/Server

echo "Patching Info.plist..." >&2
PLIST=".build/bundler/NiceVoice.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string app.nicevoice.NiceVoice" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.nicevoice.NiceVoice" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 音声入力のためにマイクを使用します" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSSpeechRecognitionUsageDescription string 音声をテキストに変換するために使用します" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string テキストを入力欄に貼り付けるために使用します" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string app.nicevoice.NiceVoice" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string nicevoice" "$PLIST" 2>/dev/null || true

echo "Signing..." >&2
codesign -fs "NiceVoice" --deep --options runtime --entitlements NiceVoice.entitlements .build/bundler/NiceVoice.app

echo "Restarting app..." >&2
killall -9 NiceVoice 2>/dev/null || true
open .build/bundler/NiceVoice.app

echo "Build verified and app restarted." >&2
