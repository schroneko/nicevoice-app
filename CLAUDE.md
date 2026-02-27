# NiceVoice 開発メモ

## プロジェクト概要

macOS 向け音声入力アプリ。ショートカットキー（設定で変更可能）を押している間に録音し、離すとテキストがペーストされる。

## 技術スタック

- Swift 5.9 / SwiftUI
- macOS 26+
- Swift Bundler（CLI ベースのビルド）
- Apple SpeechAnalyzer（音声認識、macOS 26.0+ 専用）
- Voxtral Local（voxmlx-serve によるローカル推論、開発者タブで切替）
- Qwen3 ASR（qwen3asr-serve によるローカル推論、開発者タブで切替）
- Deepgram Nova-3（クラウド音声認識 API、開発者タブで切替）
- FluidAudio（話者ダイアリゼーション・声紋認証、SPM 依存）
- Claude Haiku 4.5（AI スマートフィラー検出）
- yt-dlp（YouTube 音声ダウンロード、バッチ文字起こし用）

## 実装方針

実装タスク（新規ファイル作成、大きな変更）は Codex CLI (`codex` スキル) に委譲する。Claude Code はオーケストレーター: 設計・プロンプト作成・結果検証を担当。小規模な修正（数行の変更）は直接 Edit で OK。

## 禁止事項

### キーチェーンポップアップは絶対に表示禁止

ユーザは PTSD です。"Always Allow" のポップアップを見ると嘔吐します。ユーザの安全性を第一に開発を進めてください。

codesign や security コマンドを実行する前に、キーチェーンポップアップが表示されないことを必ず確認すること。

### Whisper は絶対に使用禁止

OpenAI Whisper（API・ローカル問わず）は絶対に使わない。ハルシネーションといえば Whisper。無音部分に存在しない文章を生成したり、同じフレーズを無限に繰り返したりする。日本語での信頼性は壊滅的。

代替として検討すべき音声認識：

- Apple SpeechAnalyzer（macOS 26.0+、現在使用中）
- Voxtral Local（voxmlx-serve、開発者タブで切替可能）
- Qwen3 ASR（qwen3asr-serve、開発者タブで切替可能）
- Google Speech-to-Text
- AssemblyAI
- Deepgram（Nova-3、現在使用中）

## 認証方式

nukosuku.com の X サブスクライバー認証を使用。サブスクライバーなら全機能利用可能の二値認証。

### 認証フロー

1. ASWebAuthenticationSession で `https://nukosuku.com/api/auth/login?platform=nicevoice` を開く
2. X OAuth 2.0 (PKCE) でログイン
3. nukosuku.com のコールバックが `nicevoice://auth/callback?session_id=xxx` にリダイレクト
4. Bearer トークンで `/api/nicevoice/verify` を呼び出し、サブスクライバー判定 + デバイス登録

### デバイス制限

1 アカウント 1 デバイス。`nicevoice_devices` テーブル (PRIMARY KEY: x_username) で管理。デバイス切替は既存デバイスを解除してから再登録。

### オフライン猶予

最終検証から 7 日間はオフラインでも利用可能。オンライン時は 1 日に 1 回再検証。

### 関連ファイル

- `NukosukuAuthService.swift`: ASWebAuthenticationSession / Bearer トークン API
- `AuthManager.swift`: @Observable シングルトン、認証状態管理
- nukosuku-com: `worker/routes/nicevoice.ts` (verify/device エンドポイント)

## ビルド方法

```bash
./Scripts/verify-build.sh
```

ビルドは必ずこのスクリプトを使う。手動で分割しない（swift build、codesign、killall を個別に実行しない）。

Swift ファイル編集後、ユーザーにテストを依頼する前に必ず `verify-build.sh` を実行してアプリを再起動する。`swift build` 単体で済ませない。

このスクリプトは Claude Code の PreToolUse フック（pre-commit）として自動実行されるため、コミット前に毎回ビルドが検証される。

### ビルドスクリプトの既知の問題

`verify-build.sh` は `swift build` の出力を `grep -v` でパイプしているため、コンパイルエラーがあっても終了コードが隠れてスクリプトが続行する。古い `.build/debug/NiceVoice` バイナリが存在すると、コンパイルエラーに気づかず古いバイナリが署名される。

ビルド後に変更が反映されない場合は、`swift build --product NiceVoice` を直接実行してコンパイルエラーを確認する。

このスクリプトが以下を自動実行する:

1. `swift build` でコンパイル
2. `swift-bundler` でバンドル作成
3. `codesign -fs "NiceVoice"` で自己署名証明書による署名
4. 既存プロセスを終了して `.build/bundler/NiceVoice.app` から起動

手動起動: `open .build/bundler/NiceVoice.app`（Spotlight には出ない）

ログは別途 `tail -f ~/Library/Logs/NiceVoice/debug.log` で確認できる。

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

## Homebrew Cask テスト

配布用の Homebrew cask (`schroneko/tap/nicevoice`) をローカルでテストする手順。

cask 定義: `/Users/username/Sync/homebrew-tap/Casks/nicevoice.rb`

開発中は `url` を `file://` に、`sha256` を `:no_check` に設定してローカル ZIP を参照する。配布時は GitHub Releases の URL と実際の SHA256 に戻す。

```bash
./Scripts/release.sh 0.1.0
brew reinstall --cask schroneko/tap/nicevoice
```

release.sh は ad-hoc 署名のため、インストール後に権限リセットが必要な場合がある:

```bash
xattr -cr /Applications/NiceVoice.app
tccutil reset Microphone app.nicevoice.NiceVoice
tccutil reset Accessibility app.nicevoice.NiceVoice
tccutil reset SpeechRecognition app.nicevoice.NiceVoice
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
- Qwen3 ASR（qwen3asr-serve）: ローカルサーバーによるリアルタイム文字起こし
- Deepgram Nova-3（クラウド API）: WebSocket リアルタイム + REST バッチ

### 関連ファイル

- `DeveloperView.swift`: 開発者タブの UI

### ローカル ASR エンジン共通アーキテクチャ

Voxtral Local と Qwen3 ASR は同じアーキテクチャを共有する:

1. `verify-build.sh` が `Server/` をアプリバンドルの `Contents/Resources/Server` にコピー
2. `LocalServerManager` が `Bundle.main.resourceURL` から Server パスを取得
3. `uvx --from <serverPath>[server] <command>` でサーバーを起動
4. `LocalASRService` が WebSocket (OpenAI Realtime API 互換) で通信

共通ファイル:

- `LocalASRService.swift`: WebSocket クライアント、PCM 変換、音声ストリーミング
- `LocalServerManager.swift`: Python サーバープロセスの起動・停止・ヘルスチェック
- `Constants.swift`: エンドポイント URL、モデル名、タイムアウト設定

### Voxtral Local (voxmlx-serve)

モデル: `schroneko/Voxtral-Mini-4B-Realtime-2602-MLX-4bit` (4-bit, ~2.5 GB)
変換元: `mistralai/Voxtral-Mini-4B-Realtime-2602` (BF16)
ポート: 8000

- `Server/voxmlx/server.py`: WebSocket サーバー (文字化け修正パッチ適用済み)
- `Server/pyproject.toml`: Python パッケージ定義と依存関係

文字化け修正: `Server/voxmlx/server.py` の `_decode_steps()` でトークン ID を蓄積し `sp.decode(all_ids)` でまとめてデコード。末尾 U+FFFD を `rstrip('\ufffd')` で除去し、完成した文字のみデルタとして送信。

### Qwen3 ASR (qwen3asr-serve)

モデル: `schroneko/Qwen3-ASR-1.7B-4bit` (4-bit, ~1.6 GB)
変換元: `Qwen/Qwen3-ASR-1.7B` (BF16)、`mlx-audio` の convert で変換
ポート: 8001

- `Server/qwen3asr/server.py`: WebSocket サーバー (mlx-qwen3-asr の Session API 使用)
- `Server/qwen3asr/pyproject.toml`: Python パッケージ定義と依存関係

### YouTube 文字起こし

バッチ文字起こしタブで YouTube URL からの音声抽出に対応。yt-dlp (Homebrew) を使用。

- `YouTubeDownloader.swift`: yt-dlp ラッパー (パス探索、m4a ダウンロード)
- yt-dlp 未インストール時は `brew install yt-dlp` を案内

### Deepgram Nova-3

クラウド音声認識 API。API キーは 1Password (`DEEPGRAM_API_KEY`) に保管、ビルド時に `verify-build.sh` が自動埋め込み。

- `DeepgramService.swift`: WebSocket リアルタイムストリーミング + REST バッチ文字起こし
- WebSocket: `wss://api.deepgram.com/v1/listen` (Authorization ヘッダー認証、binary PCM Int16 LE)
- REST: `POST https://api.deepgram.com/v1/listen` (Authorization ヘッダー)
- KeepAlive 5 秒間隔、CloseStream でセッション終了

### 声紋認証 (FluidAudio)

FluidAudio の DiarizerManager を使った話者エンベディング抽出・照合。

- `SpeakerVerificationService.swift`: 登録・照合ロジック
- `performCompleteDiarization()` でセグメントから 256 次元エンベディングを取得
- コサイン距離は `SpeakerUtilities.cosineDistance()` (vDSP 最適化)
- エンベディングは UserDefaults に保存

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
