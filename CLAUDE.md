# NiceVoice 開発メモ

## プロジェクト概要

macOS 向け音声入力アプリ。ショートカットキー（設定で変更可能）を押している間に録音し、離すとテキストがペーストされる。

## 技術スタック

- Swift 5.9 / SwiftUI
- macOS 26+
- Swift Bundler（CLI ベースのビルド）
- Apple SpeechAnalyzer（音声認識、macOS 26.0+ 専用）
- Voxtral Local（voxmlx-serve によるローカル推論、開発者タブで切替）
- Claude Haiku 4.5（AI スマートフィラー検出）

## 禁止事項

### キーチェーンポップアップは絶対に表示禁止

ユーザは PTSD です。"Always Allow" のポップアップを見ると嘔吐します。ユーザの安全性を第一に開発を進めてください。

codesign や security コマンドを実行する前に、キーチェーンポップアップが表示されないことを必ず確認すること。

### Whisper は絶対に使用禁止

OpenAI Whisper（API・ローカル問わず）は絶対に使わない。ハルシネーションといえば Whisper。無音部分に存在しない文章を生成したり、同じフレーズを無限に繰り返したりする。日本語での信頼性は壊滅的。

代替として検討すべき音声認識：

- Apple SpeechAnalyzer（macOS 26.0+、現在使用中）
- Voxtral Local（voxmlx-serve、開発者タブで切替可能）
- Google Speech-to-Text
- AssemblyAI
- Deepgram

## 価格戦略

### 2層プラン構造（サブスクのみ）

| プラン | 月額 | 年額           | 機能                                        |
| ------ | ---- | -------------- | ------------------------------------------- |
| Pro    | $10  | $96（$8/月）   | 全機能 + AI スマートフィラー検出            |
| VIP    | $30  | $300（$25/月） | + ファイル/YouTube 文字起こし（バッチ処理） |

買い切りは提供しない（フィードバック獲得、クーポン発行のため）

### トライアル・クーポン

- 7 日間無料トライアル
- 初期ユーザー向けクーポンで割引可能

### コスト構造

- Pro: Claude Haiku 4.5（ヘビーユーザーで月 $6-7 程度）→ 利益 $3-4（30-40%）
- VIP: Pro のコスト + バッチ処理（SpeechAnalyzer、追加コストなし）→ 利益 $23-24（77-80%）

### VIP 音声ファイル文字起こし

- Apple SpeechAnalyzer を使用（ローカル処理）
- リアルタイムではなくバッチ処理
- 完了したら通知
- 対応予定: ファイル入力、YouTube 入力

## ビルド方法

```bash
./Scripts/debug-run.sh
```

ビルドは必ずこのスクリプトを使う。手動で分割しない（swift build、codesign、killall、cp を個別に実行しない）。

### ビルドスクリプトの既知の問題

`debug-run.sh` は `swift build` の出力を `grep -v` でパイプしているため、コンパイルエラーがあっても終了コードが隠れてスクリプトが続行する。古い `.build/debug/NiceVoice` バイナリが存在すると、コンパイルエラーに気づかず古いバイナリが /Applications にコピーされる。

ビルド後に変更が反映されない場合は、`swift build --product NiceVoice` を直接実行してコンパイルエラーを確認する。

このスクリプトが以下を自動実行する:

1. `swift build` でコンパイル
2. `swift-bundler` でバンドル作成
3. `codesign -fs "NiceVoice"` で自己署名証明書による署名
4. 既存プロセスを終了して起動
5. ログを tail -f で表示

自己署名証明書「NiceVoice」で署名することで、ビルドしてもアクセシビリティ権限が維持される。

署名が正しく適用されているか確認するには:

```bash
codesign -dvvv .build/bundler/NiceVoice.app 2>&1 | grep "Signature"
```

`Signature=adhoc` ではなく証明書名が表示されれば OK。

### ビルドエラー時

disk I/O error 等が発生した場合:

```bash
rm .build/build.db .build/build.db-journal
```

それでも解決しない場合は `rm -rf .build` で完全クリーンビルド。

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

**問題**: ad-hoc 署名（`codesign -s -`）だとビルドごとに署名が変わり、アクセシビリティ権限がリセットされる。Allow ダイアログを押しても反映されず、毎回設定から手動で追加が必要だった。

**解決策**: 自己署名証明書を作成し、安定した署名を使用する。これにより TCC が同一アプリと認識し、権限が維持される。

### TCC エントリの不一致

**問題**: System Settings ではアクセシビリティ権限がオンなのに、`AXIsProcessTrusted()` が `false` を返す。

**原因**: TCC には 2 種類の識別方法がある:

- パスベース (client_type=1): `/Applications/NiceVoice.app/Contents/MacOS/NiceVoice`
- バンドル ID ベース (client_type=0): `app.nicevoice.NiceVoice`

CFBundleIdentifier を後から追加した場合、古いパスベースのエントリが残り、新しいバンドル ID ベースのエントリと競合する。

**解決策**:

1. System Settings > Privacy & Security > Accessibility で NiceVoice を削除
2. アプリを再起動
3. 権限ダイアログで許可

これで新しいバンドル ID ベースのエントリが作成される。

### インラインテキストプレビュー

録音中に認識結果をフォーカスしたテキストフィールドにリアルタイム表示する機能。2 つのモードを自動判別する。

AX モード: `AXUIElementCreateSystemWide()` でフォーカス要素を取得し、`kAXSelectedTextAttribute` でテキストを挿入する。TextEdit、Notes.app 等の AX 対応アプリで使用。テキストが伸びる場合は末尾に追記 (長さ 0 の選択 = ハイライトなし)、テキストが変わる場合のみ全選択-置換する。検証は `kAXStringForRangeParameterizedAttribute` で選択なしに読み取る。

CGEvent キーボードモード: AX 検証が失敗したアプリ (Ghostty 等のターミナル) で使用。`CGEvent.keyboardSetUnicodeString` で文字を直接入力し、`kVK_Delete` で削除する。`commonPrefix` 最適化で変更部分のみ再入力。

ファイナライズ: keyboard モードではストリーミング中の追跡変数と画面の実態がズレうるため、全削除後にクリップボードペースト (`performPaste`) で確定テキストを挿入する。AX モードでは全選択-置換で上書き。

## 開発者タブ

サイドバーの「開発者」タブ（ハンマーアイコン）は開発・デバッグ用。ユーザ向け設定には含めない。

### 音声認識エンジン切替

- Apple SpeechAnalyzer（デフォルト）: ローカル処理、オフライン対応
- Voxtral Local（voxmlx-serve）: ローカルサーバーによるリアルタイム文字起こし

### 関連ファイル

- `DeveloperView.swift`: 開発者タブの UI

### Voxtral Local (voxmlx-serve)

ローカルで動作する Voxtral 音声認識エンジン。`Server/` ディレクトリに voxmlx の Python コードを同梱し、アプリバンドルの Resources にコピーして使用する。第三者の GitHub リポジトリに依存しない。

モデル: `schroneko/Voxtral-Mini-4B-Realtime-2602-MLX-4bit` (4-bit, ~2.5 GB)

変換元: `mistralai/Voxtral-Mini-4B-Realtime-2602` (BF16)

起動の仕組み:

1. `debug-run.sh` が `Server/` をアプリバンドルの `Contents/Resources/Server` にコピー
2. `VoxmlxServerManager` が `Bundle.main.resourceURL` から Server パスを取得
3. `uvx --from <serverPath>[server] voxmlx-serve` でサーバーを起動

関連ファイル:

- `Server/voxmlx/server.py`: WebSocket サーバー (文字化け修正パッチ適用済み)
- `Server/pyproject.toml`: Python パッケージ定義と依存関係
- `VoxtralLocalService.swift`: WebSocket クライアント、PCM 変換、音声ストリーミング
- `VoxmlxServerManager.swift`: voxmlx-serve プロセスの起動・停止・ヘルスチェック
- `Constants.swift`: エンドポイント URL、モデル名、タイムアウト設定

文字化け修正: `Server/voxmlx/server.py` の `_decode_steps()` でトークン ID を蓄積し `sp.decode(all_ids)` でまとめてデコード。末尾 U+FFFD を `rstrip('\ufffd')` で除去し、完成した文字のみデルタとして送信。

## 未解決・要検討

### フォーカス切り替え後のペースト

ショートカットキーを離した後、別のアプリ（Spotlight など）にフォーカスを切り替えてからペーストしたい場合がある。現在は 0.3 秒後に自動ペーストされるため、切り替え時間が足りない可能性がある。

検討中のアプローチ:

- 遅延を長くする（ただし長すぎると使いにくい）
- 手動トリガー（キーを再度押したらペースト）
- フォーカス変更を検知してからペースト

## 必要な権限

- マイク（NSMicrophoneUsageDescription）
- 音声認識（NSSpeechRecognitionUsageDescription）
- アクセシビリティ（ショートカットキー監視、キーボードイベント送信）
- オートメーション/AppleEvents（NSAppleEventsUsageDescription）- 現在未使用だが将来用
