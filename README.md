# NiceVoice

macOS 向け音声入力アプリ。ショートカットキーを押している間だけ録音し、離すとテキストをペーストする。

## 技術スタック

- SwiftUI
- Swift 5.9
- macOS 26+
- Swift Bundler
- Apple SpeechAnalyzer
- Voxtral Local
- Qwen3 ASR
- FluidAudio
- Claude Haiku 4.5
- yt-dlp

## 安全上の前提

- キーチェーンの "Always Allow" ポップアップを表示させない
- `codesign` や `security` を実行する前にポップアップが出ない手順を確認する
- Whisper は API 版もローカル版も使わない
- 一般ユーザーに `mise`、`uv`、`uvx`、Python の事前準備を要求しない

代替候補:

- Apple SpeechAnalyzer
- Voxtral Local
- Qwen3 ASR
- Google Speech-to-Text
- AssemblyAI
- Deepgram

## ビルド

```bash
./Scripts/verify-build.sh
```

- Swift ファイルを変更したら必ずこのスクリプトでビルドと再起動まで行う
- `verify-build.sh` はビルド後にアプリを `/Applications/NiceVoice.app` へ自動コピーする。書き込み権限がない場合は `~/Applications/NiceVoice.app` を使う
- `swift build` 単体では終えない
- 手動起動は `open /Applications/NiceVoice.app` または `open ~/Applications/NiceVoice.app`
- ログは `tail -f ~/Library/Logs/NiceVoice/debug.log`
- Voxtral は build 時に `Server/.venv` から app bundle へ runtime を同梱する

署名確認:

```bash
codesign -dvvv .build/bundler/NiceVoice.app 2>&1 | grep "Signature"
```

`Signature=adhoc` ではなく証明書名が表示されればよい。

## ビルドトラブル

- `verify-build.sh` は古いバイナリを署名してしまうことがある
- 反映されない場合は `swift build --product NiceVoice` でコンパイルエラーを直接確認する
- disk I/O error が出たら `rm .build/build.db .build/build.db-journal`
- それでも直らなければ `rm -rf .build`

Voxtral の開発時前提:

- `Server/.venv` が存在していること
- `./Scripts/package-app.sh` が `Server/.venv/pyvenv.cfg` を見て Python runtime を app 内へコピーできること
- 配布アプリの実行時には `uvx` や Python は不要

## 自己署名証明書

初回のみ Keychain Access で `NiceVoice` という Self Signed Root / Code Signing 証明書を作る。信頼設定の追加には次を使う。

```bash
security find-certificate -c "NiceVoice" -p > /tmp/nicevoice-cert.pem
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/nicevoice-cert.pem
```

## 主要機能

- Apple SpeechAnalyzer によるオンデバイス音声認識
- Voxtral Local を app 内同梱 runtime で起動
- Qwen3 ASR の開発者向けローカルサーバー切替
- ルールベースのフィラー除去
- 句読点自動挿入
- ユーザー辞書変換
- 声紋認証
- YouTube 音声のバッチ文字起こし
- メニューバー常駐 UI
- フローティングパネル
- 開発者タブ

## 開発者タブ

- Apple SpeechAnalyzer
- Voxtral Local
- Qwen3 ASR

Voxtral Local は `verify-build.sh` が `Server/` と Python runtime をアプリバンドルへコピーし、`LocalServerManager` が bundle 内の `python3 -m voxmlx.server` で起動する。Qwen3 ASR は開発者向け engine として残してあり、外部ツール起動の fallback を使う。

## 解決済みの問題

- `CGEvent.post()` 単体では Cmd+V が安定しなかったため、`CGEventSource(stateID: .privateState)` と `.cgAnnotatedSessionEventTap` を使う
- ad-hoc 署名だとアクセシビリティ権限が維持されないため、自己署名証明書を使う
- TCC のパスベースエントリとバンドル ID ベースエントリが競合する場合は、Accessibility から一度削除して再許可する

## 未解決・要検討

- ローカル ASR サーバーの共通フレームワーク化
- フォーカス切り替え後にペーストする UX
- String Catalog を使った多言語ローカライズ

## 必要な権限

- マイク
- 音声認識
- アクセシビリティ
- オートメーション / AppleEvents

## 配布

macOS ネイティブアプリであり、Web サービスのデプロイという概念はない。配布は `release-build.yml` の手動実行 (workflow_dispatch) でバージョンを指定してビルドする。main への push で自動デプロイは発生しない。

## 関連資料

- 要件定義: `requirements.md`
- 更新履歴: `Updates/README.md`
