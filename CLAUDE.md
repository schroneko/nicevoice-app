# NiceVoice 開発メモ

## プロジェクト概要

macOS 向け音声入力アプリ。fn キーを押している間に録音し、離すとテキストがペーストされる。

## 技術スタック

- Swift 5.9 / SwiftUI
- macOS 14+
- Swift Bundler（CLI ベースのビルド）
- SFSpeechRecognizer（Mac 標準の音声認識）

## ビルド方法

```bash
cd /Users/username/nicevoice-app
export PATH="$HOME/.mint/bin:$PATH"
swift-bundler bundle
cp -R .build/bundler/NiceVoice.app /Applications/
codesign -fs "NiceVoice" --deep /Applications/NiceVoice.app
killall NiceVoice 2>/dev/null; open /Applications/NiceVoice.app
```

自己署名証明書「NiceVoice」で署名することで、ビルドしてもアクセシビリティ権限が維持される。

### 自己署名証明書の作成（初回のみ）

1. Keychain Access を開く
2. メニュー: Keychain Access → Certificate Assistant → Create a Certificate...
3. Name: `NiceVoice`, Identity Type: `Self Signed Root`, Certificate Type: `Code Signing`
4. Create をクリック
5. 証明書を信頼設定に追加:
   ```bash
   security find-certificate -c "NiceVoice" -p > /tmp/nicevoice-cert.pem
   security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/nicevoice-cert.pem
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

**問題 1**: `/tmp/` にあるアプリはシステム設定のアクセシビリティ一覧に表示されない。

**解決策**: `/Applications/` にコピーしてから起動する。

**問題 2**: ad-hoc 署名（`codesign -s -`）だとビルドごとに署名が変わり、アクセシビリティ権限がリセットされる。Allow ダイアログを押しても反映されず、毎回設定から手動で追加が必要だった。

**解決策**: 自己署名証明書を作成し、安定した署名を使用する。これにより TCC が同一アプリと認識し、権限が維持される。

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
