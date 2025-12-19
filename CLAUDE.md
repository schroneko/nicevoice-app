# NiceVoice 開発メモ

## プロジェクト概要

macOS 向け音声入力アプリ。fn キーを押している間に録音し、離すとテキストがペーストされる。

## 技術スタック

- Swift 5.9 / SwiftUI
- macOS 14+
- Swift Bundler（CLI ベースのビルド）
- SFSpeechRecognizer（Mac 標準の音声認識）

## ビルド方法

Google Drive 上で直接ビルドすると SQLite エラーが発生するため、`/tmp/claude/` にコピーしてビルドする：

```bash
cp -R /Users/username/gdrive/nicevoice-app/NiceVoice/* /tmp/claude/nicevoice-build/
cd /tmp/claude/nicevoice-build
export PATH="$HOME/.mint/bin:$PATH"
swift-bundler bundle
cp -R .build/bundler/NiceVoice.app ~/Applications/
open ~/Applications/NiceVoice.app
```

## 解決済みの問題

### Google Drive + Swift Package Manager

**問題**: Google Drive（FileProvider）上で `swift build` や `swift-bundler` を実行すると以下のエラー：
```
sandbox-exec: sandbox_apply: Operation not permitted
error: Invalid manifest
```

**原因**: Swift Package Manager が SQLite データベースを使用するが、Google Drive の仮想ファイルシステムと互換性がない。

**解決策**: `/tmp/claude/` にファイルをコピーしてからビルドする。`--scratch-path` オプションだけでは不十分な場合がある。

### CGEvent でのキーボードイベント送信

**問題**: `CGEvent.post()` で Cmd+V を送信してもペーストされない。

**試したこと**:
- `.cgSessionEventTap` - 動作せず
- `.cghidEventTap` - 動作せず
- AppleScript (`keystroke "v" using command down`) - 動作せず

**解決策**: 以下の組み合わせで動作した：
```swift
let source = CGEventSource(stateID: .privateState)
let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
keyDown?.flags = .maskCommand
keyUp?.flags = .maskCommand
keyDown?.post(tap: .cgAnnotatedSessionEventTap)
usleep(50000)
keyUp?.post(tap: .cgAnnotatedSessionEventTap)
```

ポイント:
- `CGEventSource(stateID: .privateState)` を使用
- `.cgAnnotatedSessionEventTap` にポスト
- keyDown と keyUp の間に 50ms の遅延

### アクセシビリティ権限

**問題**: `/tmp/` にあるアプリはシステム設定のアクセシビリティ一覧に表示されない。

**解決策**: `~/Applications/` にコピーしてから起動する。

## 未解決・要検討

### フォーカス切り替え後のペースト

fn キーを離した後、別のアプリ（Spotlight など）にフォーカスを切り替えてからペーストしたい場合がある。現在は 0.3 秒後に自動ペーストされるため、切り替え時間が足りない可能性がある。

検討中のアプローチ:
- 遅延を長くする（ただし長すぎると使いにくい）
- 手動トリガー（fn を再度押したらペースト）
- フォーカス変更を検知してからペースト

## 必要な権限

- マイク（NSMicrophoneUsageDescription）
- 音声認識（NSSpeechRecognitionUsageDescription）
- アクセシビリティ（fn キー監視、キーボードイベント送信）
- オートメーション/AppleEvents（NSAppleEventsUsageDescription）- 現在未使用だが将来用
