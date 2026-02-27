# Nice Voice - macOS 音声入力アプリケーション要件定義書 v2

## 1. エグゼクティブサマリー

### プロダクト概要

| 項目             | 内容                                   |
| ---------------- | -------------------------------------- |
| サービス名       | Nice Voice                             |
| ドメイン         | nicevoice.app                          |
| プラットフォーム | macOS 26+（Apple Silicon）             |
| 技術基盤         | Swift / SwiftUI + Apple SpeechAnalyzer |
| ターゲット市場   | 日本市場（初期）、グローバル展開予定   |

### 差別化ポイント

1. **完全ネイティブ Swift** - 軽量（RAM 50MB vs 競合 800MB）、高速起動
2. **オンデバイス処理** - Apple SpeechAnalyzer によるプライバシー重視設計
3. **日本語特化** - 内蔵辞書、自然な句読点挿入、フィラー除去

### 収益目標（初年度）

| 指標           | 目標    |
| -------------- | ------- |
| 有料ユーザー数 | 500 人  |
| MRR            | $4,000  |
| ARR            | $48,000 |

---

## 2. プロダクト概要

### 2.1 ビジョンとミッション

**ビジョン**: 音声入力を日常のテキスト入力の第一選択肢にする

**ミッション**: 高精度・低遅延・プライバシー重視の音声入力体験を提供し、キーボード入力の負担を軽減する

**コアバリュー**:

- プライバシーファースト（オンデバイス処理）
- シンプルさ（ワンキーで録音開始）
- 日本語への最適化

### 2.2 ターゲットユーザー

| 優先度     | ユーザー層         | 規模 | ニーズ               | ペインポイント             |
| ---------- | ------------------ | ---- | -------------------- | -------------------------- |
| プライマリ | ライター・ブロガー | 中   | 長文入力の効率化     | タイピング疲労、思考の中断 |
| セカンダリ | RSI/腱鞘炎ユーザー | 小   | キーボード負荷軽減   | 身体的制約                 |
| ターシャリ | 開発者             | 中   | 技術用語の高精度認識 | Mac 標準の精度不足         |

#### ペルソナ

**ペルソナ 1: ブロガー田中さん（35歳）**

- 週に 3-4 記事を執筆
- 1 記事あたり 3,000-5,000 文字
- 課題: タイピングによる腱鞘炎の兆候、思考のスピードに入力が追いつかない
- 期待: 話すだけで自然な日本語テキストが生成される

**ペルソナ 2: エンジニア佐藤さん（28歳）**

- ドキュメント作成、Slack でのコミュニケーション
- 技術用語（API、GitHub、React など）を頻繁に使用
- 課題: Mac 標準音声入力の技術用語認識精度が低い
- 期待: カスタム辞書で専門用語を正確に認識

**ペルソナ 3: RSI 患者山田さん（42歳）**

- 腱鞘炎でキーボード使用を制限
- メール、チャット、ドキュメント作成
- 課題: 音声入力の後処理が面倒（フィラー削除、句読点追加）
- 期待: 話したままの自然なテキストが即座に入力される

### 2.3 競合分析と差別化

| 競合         | 価格   | 認識方式 | メモリ使用 | 強み           | Nice Voice の差別化        |
| ------------ | ------ | -------- | ---------- | -------------- | -------------------------- |
| Aqua Voice   | $8/月  | クラウド | 不明       | 技術用語 97.3% | オンデバイス、プライバシー |
| Superwhisper | $249   | ローカル | 高         | 完全オフライン | シンプル UX、低価格        |
| Wispr Flow   | $12/月 | クラウド | **800MB**  | IDE 統合       | **RAM 50MB**、軽量         |
| VoiceInk     | $25-39 | ローカル | 中         | OSS、コスパ    | LLM 後処理、日本語特化     |
| Mac 標準     | 無料   | 混合     | 低         | システム統合   | カスタム辞書、精度向上     |

**Nice Voice の競争優位性**:

1. **軽量性**: Electron 製競合（Wispr Flow）の 1/16 のメモリ使用量
2. **プライバシー**: SpeechAnalyzer はオンデバイス処理、音声データ外部送信なし
3. **日本語最適化**: 内蔵辞書、自然な句読点挿入、文脈を考慮したフィラー除去
4. **シンプル UX**: ワンキーで録音、自動ペースト

---

## 3. 機能要件

### 3.1 実装済み機能（現状）

| カテゴリ     | 機能                        | 説明                                                    | 実装ファイル                                                 |
| ------------ | --------------------------- | ------------------------------------------------------- | ------------------------------------------------------------ |
| 音声認識     | Apple SpeechAnalyzer        | macOS 26+ オンデバイス音声認識                          | `SpeechAnalyzerService.swift`                                |
| 音声認識     | Voxtral Local               | `voxmlx-serve` ローカルサーバー経由のリアルタイム認識   | `LocalASRService.swift`, `LocalServerManager.swift`          |
| 音声認識     | Qwen3 ASR                   | `qwen3asr-serve` ローカルサーバー経由のリアルタイム認識 | `LocalASRService.swift`, `LocalServerManager.swift`          |
| 音声認識     | Deepgram Nova-3             | クラウド WebSocket/REST 文字起こし                      | `DeepgramService.swift`                                      |
| 入力方式     | Push-to-Talk                | ショートカットキー押下中のみ録音                        | `KeyMonitor.swift`                                           |
| テキスト処理 | ルールベースフィラー削除    | 「えー」「あー」などの自動削除                          | `TextProcessor.swift`                                        |
| テキスト処理 | 句読点自動挿入              | 文末・接続詞前後の句読点追加                            | `TextProcessor.swift`                                        |
| テキスト処理 | 辞書変換                    | 内蔵辞書 + ユーザー辞書による語彙変換                   | `TextProcessor.swift`                                        |
| 認証         | nukosuku サブスク認証       | OAuth ログインとサブスク状態検証                        | `NukosukuAuthService.swift`, `AuthManager.swift`             |
| 出力         | CGEvent ペースト            | クリップボード経由で Cmd+V 送信                         | `NiceVoice.swift`                                            |
| UI           | メニューバー常駐            | バックグラウンド動作、クイックアクセス                  | `NiceVoice.swift`                                            |
| UI           | フローティングパネル        | 録音中の音声レベル表示                                  | `FloatingPanel.swift`                                        |
| UI           | 設定画面                    | ショートカットキー、フィラー設定など                    | `SettingsViews.swift`                                        |
| UI           | 開発者タブ                  | ASR エンジン切替・接続状態確認                          | `DeveloperView.swift`                                        |
| UI           | オンボーディング            | 初回セットアップ                                        | `OnboardingView.swift`                                       |
| データ       | 履歴管理                    | 最大 20 件の認識履歴                                    | `HistoryViews.swift`                                         |
| データ       | ユーザー辞書                | カスタム語彙の登録                                      | `DictionaryViews.swift`                                      |
| データ       | 使用量トラッキング          | 変換回数・文字数の集計                                  | `UsageTracker.swift`                                         |
| セキュリティ | 声紋認証                    | FluidAudio を使った話者エンベディング照合               | `SpeakerVerificationService.swift`                           |
| バッチ       | ファイル/YouTube 文字起こし | 音声ファイルと YouTube URL のバッチ処理                 | `BatchTranscriptionService.swift`, `YouTubeDownloader.swift` |

#### 内蔵辞書（プリセット）

```
クロードコード -> Claude Code
クロードエムディー -> CLAUDE.md
ラングラー -> Wrangler
クロード -> Claude
スーパーベース -> Supabase
スパベース -> Supabase
グロック -> Grok
ジェイソン -> JSON
チャットGPT -> ChatGPT
ウルトラシンク -> ultrathink
シェモア -> chezmoi
でぃすこーど -> Discord
ディスコード -> Discord
ワンパスワード -> 1Password
ジェミニ -> Gemini
ナノバナナ -> Nano Banana
API機 -> APIキー
クラウドフレア -> Cloudflare
アンソロピック -> Anthropic
```

### 3.2 MVP: 商用リリース必須機能

| 機能                 | 優先度 | 複雑度 | 説明                                | 状態                      |
| -------------------- | ------ | ------ | ----------------------------------- | ------------------------- |
| 認証                 | P0     | 高     | nukosuku.com X サブスクライバー認証 | 実装済み                  |
| コード署名           | P0     | 中     | Developer ID 署名                   | 未実装 (自己署名で運用中) |
| Notarization         | P0     | 中     | Apple 公証                          | 未実装                    |
| Sparkle 自動更新     | P0     | 中     | appcast.xml 配信                    | 未実装                    |
| プライバシーポリシー | P0     | 低     | Web ページ + アプリ内リンク         | 未実装                    |
| 利用規約             | P0     | 低     | Web ページ + アプリ内リンク         | 未実装                    |
| 特定商取引法表記     | P0     | 低     | Web ページ                          | 未実装                    |
| Free プラン制限      | P1     | 中     | 月間文字数制限の実装                | スタブのみ (UsageTracker) |
| トライアル期間       | P1     | 中     | 初回起動から 7 日間フル機能         | 未実装                    |

### 3.3 Phase 2: 差別化機能

| 機能                   | 説明                          | 技術的詳細                                         |
| ---------------------- | ----------------------------- | -------------------------------------------------- |
| Toggle Mode            | 1 回押しで開始/終了           | KeyMonitor に状態管理追加                          |
| クラウド音声認識       | ElevenLabs / Groq API（BYOK） | 設定画面で API キー入力、SpeechAnalyzer と切り替え |
| サウンドフィードバック | 開始/終了の効果音             | AVAudioPlayer + システムサウンド                   |
| YouTube 文字起こし     | URL 入力 -> 文字起こし        | youtube-caption-extractor or 音声ダウンロード      |
| 多言語 UI              | 英語 UI 追加                  | String Catalog / NSLocalizedString                 |

#### クラウド音声認識オプション（BYOK）

| API                  | 価格       | 精度               | 特徴           |
| -------------------- | ---------- | ------------------ | -------------- |
| ElevenLabs Scribe v2 | $0.40/時間 | 最高（WER 5%未満） | 日本語最高精度 |
| Groq Whisper Turbo   | $0.04/時間 | 高（WER 9-11%）    | コスパ最強     |

ユーザーが自分の API キーを入力する方式（BYOK: Bring Your Own Key）で提供。
Nice Voice はマージンを取らず、ユーザーが直接 API プロバイダーに支払う。

### 3.4 Phase 3: 高度な機能

| 機能               | 説明                 | 技術的詳細                                      |
| ------------------ | -------------------- | ----------------------------------------------- |
| コンテキスト認識   | アクティブアプリ検出 | NSWorkspace.shared.frontmostApplication         |
| スタイルプリセット | アプリごとの出力調整 | Slack: カジュアル、メール: フォーマル           |
| 開発者モード       | 技術用語辞書強化     | プリセット辞書パック（React, Python, AWS など） |
| Raycast 拡張       | Raycast からの起動   | Raycast Extension API                           |
| Apple Shortcuts    | ワークフロー統合     | App Intents framework                           |
| オフラインモード   | kotoba-whisper       | whisper.cpp + kotoba-whisper-v2.0-ggml          |

### 3.5 Phase 4: 法人向け機能

| 機能           | 説明                         | 技術的詳細                        |
| -------------- | ---------------------------- | --------------------------------- |
| 管理画面       | ライセンス管理ダッシュボード | Web アプリ（Next.js）             |
| SSO/SAML       | 企業認証連携                 | Auth0 / Okta 統合                 |
| 一括ライセンス | ボリューム購入               | Stripe Billing + カスタムロジック |
| 請求書払い     | 法人向け決済                 | Stripe Invoicing                  |
| SLA            | サービスレベル保証           | 99.9% 可用性                      |

---

## 4. 非機能要件

### 4.1 パフォーマンス

| 指標           | 目標値     | 測定方法                 |
| -------------- | ---------- | ------------------------ |
| 起動時間       | 500ms 以内 | Time Profiler            |
| 認識レイテンシ | 800ms 以内 | 録音終了から結果表示まで |
| 待機時メモリ   | 50MB 以下  | Activity Monitor         |
| 録音時メモリ   | 200MB 以下 | Activity Monitor         |
| CPU（待機時）  | 0%         | Activity Monitor         |
| CPU（録音時）  | 50% 以下   | Activity Monitor         |
| バッテリー影響 | 待機時 0%  | Energy Impact            |

### 4.2 セキュリティ・プライバシー

| 要件             | 実装                                            |
| ---------------- | ----------------------------------------------- |
| 音声データ       | SpeechAnalyzer はオンデバイス処理、外部送信なし |
| API キー         | UserDefaults (将来 Keychain 移行を検討)         |
| 一時ファイル     | 処理後即時削除                                  |
| ログ             | 音声内容は記録しない（メタデータのみ）          |
| ネットワーク通信 | TLS 1.3 必須                                    |
| データ保持       | ユーザー削除可能、アンインストール時に全削除    |

#### 必要な権限

| 権限             | 用途                        | Info.plist キー                     |
| ---------------- | --------------------------- | ----------------------------------- |
| マイク           | 音声録音                    | NSMicrophoneUsageDescription        |
| 音声認識         | SpeechAnalyzer              | NSSpeechRecognitionUsageDescription |
| アクセシビリティ | グローバルキー監視、CGEvent | - (TCC)                             |

### 4.3 互換性

| 要件             | 詳細                                 |
| ---------------- | ------------------------------------ |
| macOS バージョン | **26.0 以上**（SpeechAnalyzer 必須） |
| チップ           | Apple Silicon（M1 以降）             |
| アーキテクチャ   | arm64 のみ                           |
| Intel Mac        | 非対応                               |

### 4.4 信頼性

| 指標           | 目標値                            |
| -------------- | --------------------------------- |
| クラッシュ率   | 0.1% 以下                         |
| エラーリカバリ | 自動再起動                        |
| データ整合性   | 認識結果の欠損なし                |
| オフライン動作 | SpeechAnalyzer はネットワーク不要 |

---

## 5. 技術アーキテクチャ

### 5.1 現行アーキテクチャ

```
NiceVoice Application
├─ Presentation Layer
│  ├─ MainViews / SettingsViews / OnboardingView / HistoryViews / DictionaryViews / DeveloperView
│  └─ FloatingPanel
├─ Business Logic Layer
│  ├─ AppState (NiceVoice.swift 内)
│  └─ KeyMonitor
├─ Service Layer
│  ├─ SpeechAnalyzerService (オンデバイス)
│  ├─ LocalASRService + LocalServerManager (Voxtral/Qwen3 ローカル推論)
│  ├─ DeepgramService (クラウド認識)
│  ├─ BatchTranscriptionService + YouTubeDownloader (バッチ処理)
│  ├─ TextProcessor (フィラー除去/句読点/辞書変換)
│  └─ SpeakerVerificationService (声紋照合)
└─ Data Layer
   ├─ Models (TranscriptionRecord / UsageStats / DictionaryEntry / FillerSettings など)
   └─ LocalStorage / UserDefaults / AuthManager
```

### 5.2 追加コンポーネント（MVP 未実装）

| ファイル              | 責務                         | 状態       |
| --------------------- | ---------------------------- | ---------- |
| `UpdateService.swift` | Sparkle 統合、自動更新       | 未実装     |
| `UsageTracker.swift`  | 文字数カウント、制限チェック | スタブのみ |

### 5.3 外部サービス連携（現状）

| サービス/依存先      | 用途                                           | 必須/オプション | 統合方式                         |
| -------------------- | ---------------------------------------------- | --------------- | -------------------------------- |
| nukosuku.com API     | OAuth ログイン、サブスク状態検証、デバイス管理 | 必須            | HTTPS (Bearer トークン)          |
| Deepgram API         | クラウド音声認識（リアルタイム/バッチ）        | オプション      | WebSocket + REST                 |
| Hugging Face Hub     | Voxtral/Qwen3 モデル取得                       | オプション      | `uvx` 経由でローカルサーバー起動 |
| 1Password CLI (`op`) | 開発時の Deepgram API キー注入                 | 開発環境向け    | `Scripts/verify-build.sh` で参照 |

### 5.4 ディレクトリ構造（目標）

以下は将来のリファクタリング後を想定した目標構成（現行構成とは異なる）。

```
NiceVoice/
├── Sources/NiceVoice/
│   ├── App/
│   │   ├── NiceVoice.swift          # エントリポイント、AppDelegate
│   │   └── AppState.swift           # グローバル状態管理
│   ├── Views/
│   │   ├── MainViews.swift          # メインウィンドウ
│   │   ├── SettingsViews.swift      # 設定画面
│   │   ├── OnboardingView.swift     # オンボーディング
│   │   ├── HistoryViews.swift       # 履歴
│   │   ├── DictionaryViews.swift    # 辞書
│   │   └── FloatingPanel.swift      # 録音中パネル
│   ├── Services/
│   │   ├── SpeechAnalyzerService.swift  # 音声認識
│   │   ├── TextProcessor.swift          # テキスト処理
│   │   ├── FillerDetectionService.swift # AI フィラー検出
│   │   ├── BatchTranscriptionService.swift # バッチ処理
│   │   ├── KeyMonitor.swift             # キー監視
│   │   └── UpdateService.swift          # 自動更新 [未実装]
│   ├── Models/
│   │   └── Models.swift             # データモデル
│   └── Resources/
│       ├── Sounds/                  # 効果音 [Phase 2]
│       └── Localizable/             # ローカライズ [Phase 2]
├── Package.swift
├── Bundler.toml
└── AppIcon.icns
```

---

## 6. 価格モデル

### 6.1 コスト構造分析

#### 現状のコスト

| 項目                         | コスト  | 備考               |
| ---------------------------- | ------- | ------------------ |
| Apple SpeechAnalyzer         | $0      | オンデバイス処理   |
| サーバー（Webhook, appcast） | ~$5/月  | Cloudflare Workers |
| Apple Developer Program      | $99/年  | 必須               |
| ドメイン                     | ~$16/年 | nicevoice.app      |

#### ElevenLabs 採用時のコスト（Phase 2、BYOK）

| 使用量                       | コスト   |
| ---------------------------- | -------- |
| ライトユーザー（月 1 時間）  | $0.40/月 |
| 標準ユーザー（月 5 時間）    | $2.00/月 |
| ヘビーユーザー（月 10 時間） | $4.00/月 |

### 6.2 価格プラン（確定）

**命名: Free / Plus / Pro**（ChatGPT と同じパターン）

| プラン   | 月額 | 年額               | 機能                               |
| -------- | ---- | ------------------ | ---------------------------------- |
| **Free** | $0   | -                  | 毎月 300 クレジット、基本機能      |
| **Plus** | $10  | $96（$8/月相当）   | 無制限リアルタイム音声入力         |
| **Pro**  | $30  | $300（$25/月相当） | Plus + ファイル/YouTube 文字起こし |

### 6.3 クレジット制の詳細

| 項目           | 内容                  |
| -------------- | --------------------- |
| 付与タイミング | 登録日から 1 ヶ月ごと |
| 月間付与量     | 300 クレジット        |
| クレジット換算 | 1 文字 = 1 クレジット |
| ロールオーバー | なし（毎月リセット）  |
| 追加購入       | 将来検討              |

### 6.4 プラン別機能比較

| 機能                     | Free              | Plus   | Pro    |
| ------------------------ | ----------------- | ------ | ------ |
| リアルタイム音声入力     | 300 クレジット/月 | 無制限 | 無制限 |
| ルールベースフィラー削除 | ○                 | ○      | ○      |
| 句読点自動挿入           | ○                 | ○      | ○      |
| 内蔵辞書                 | ○                 | ○      | ○      |
| ユーザー辞書             | 10 件まで         | 無制限 | 無制限 |
| 履歴保持                 | 7 日間            | 無制限 | 無制限 |
| ファイル文字起こし       | -                 | -      | ○      |
| YouTube 文字起こし       | -                 | -      | ○      |
| 優先サポート             | -                 | -      | ○      |

### 6.5 トライアル・特別施策

| 施策                   | 内容                             | 実装                  |
| ---------------------- | -------------------------------- | --------------------- |
| 7 日間 Plus トライアル | 初回ユーザーに Plus 機能フル解放 | 初回起動日から 7 日間 |
| 年額割引               | 約 20% オフ                      | Stripe Price          |
| フィードバック割       | 有益なフィードバックで翌月無料   | 手動クーポン発行      |

---

## 7. 配布・運用

### 7.1 配布方法

| 項目         | 詳細                                             |
| ------------ | ------------------------------------------------ |
| 配布方式     | Developer ID 署名 + Apple Notarization           |
| 形式         | DMG（ドラッグ & ドロップインストール）           |
| ダウンロード | nicevoice.app から直接                           |
| App Store    | 非対応（CGEventPost がサンドボックス制限に抵触） |

### 7.2 自動更新

| 項目           | 詳細                          |
| -------------- | ----------------------------- |
| フレームワーク | Sparkle 2.x                   |
| 更新チェック   | 1 日 1 回（バックグラウンド） |
| appcast.xml    | nicevoice.app/appcast.xml     |
| 署名           | EdDSA（SUPublicEDKey）        |
| 差分更新       | 対応                          |

### 7.3 サポート体制

| チャネル      | 対象         | 応答時間    |
| ------------- | ------------ | ----------- |
| メール        | 全ユーザー   | 72 時間以内 |
| GitHub Issues | バグ報告     | 1 週間以内  |
| FAQ           | 全ユーザー   | -           |
| 優先サポート  | Pro ユーザー | 24 時間以内 |

---

## 8. 法務・コンプライアンス

### 8.1 必要な法務文書

| 文書                 | 言語         | 配置           | 内容                       |
| -------------------- | ------------ | -------------- | -------------------------- |
| 利用規約             | 日本語・英語 | Web + アプリ内 | サービス利用条件、免責事項 |
| プライバシーポリシー | 日本語・英語 | Web + アプリ内 | データ収集・利用方針       |
| 特定商取引法表記     | 日本語       | Web            | 販売者情報（日本向け必須） |
| EULA                 | 日本語・英語 | インストール時 | ソフトウェアライセンス     |

### 8.2 プライバシーポリシーの要点

| 項目       | 内容                                                             |
| ---------- | ---------------------------------------------------------------- |
| 収集データ | 使用統計（匿名、オプトイン）、ライセンス情報                     |
| 音声データ | 外部送信なし（オンデバイス処理）、ローカル保存はユーザー削除可能 |
| 第三者提供 | Anthropic（AI フィラー検出、オプトイン）                         |
| データ保持 | アカウント削除時に全削除                                         |
| 問い合わせ | support@nicevoice.app                                            |

### 8.3 コンプライアンス

| 規制                       | 対応                                   |
| -------------------------- | -------------------------------------- |
| 個人情報保護法（日本）     | プライバシーポリシー、データ削除機能   |
| GDPR（EU）                 | 同意取得、データポータビリティ、削除権 |
| 特定商取引法（日本）       | 販売者表示                             |
| Apple Developer Guidelines | Notarization、Hardened Runtime         |

---

## 9. 開発ロードマップ

### MVP（残タスク）

| タスク                             | 成果物                            |
| ---------------------------------- | --------------------------------- |
| コード署名、Notarization、DMG 作成 | 配布可能バイナリ                  |
| Sparkle 自動更新                   | UpdateService.swift、appcast.xml  |
| Free プラン制限                    | UsageTracker のクレジット制限実装 |
| 法務文書                           | プライバシーポリシー、利用規約    |

### Phase 2（6-8 週間）

| 週  | タスク                              |
| --- | ----------------------------------- |
| 1-2 | Toggle Mode、サウンドフィードバック |
| 3-4 | クラウド音声認識オプション（BYOK）  |
| 5-6 | YouTube 文字起こし                  |
| 7-8 | 英語 UI（String Catalog）           |

### Phase 3（6-8 週間）

| 週  | タスク                                          |
| --- | ----------------------------------------------- |
| 1-2 | コンテキスト認識、スタイルプリセット            |
| 3-4 | 開発者モード、技術用語辞書                      |
| 5-6 | Raycast 拡張                                    |
| 7-8 | Apple Shortcuts、オフラインモード（オプション） |

### Phase 4（需要に応じて）

- 管理画面（Web）
- SSO/SAML
- 一括ライセンス
- 請求書払い

---

## 10. リスクと対策

| リスク                           | 影響度 | 発生確率 | 対策                                                          |
| -------------------------------- | ------ | -------- | ------------------------------------------------------------- |
| macOS 26 普及遅延                | 高     | 中       | 早期アダプター向けマーケティング、Phase 2 でクラウド API 対応 |
| SpeechAnalyzer API 変更          | 高     | 低       | バージョン分岐、クラウド API フォールバック                   |
| 競合の急成長                     | 中     | 中       | 日本語特化・軽量・プライバシーで差別化                        |
| nukosuku.com 認証障害            | 中     | 低       | オフライン猶予 7 日間、手動対応                               |
| Claude API コスト増              | 低     | 低       | AI フィラー検出のオプション化、ローカル LLM 検討              |
| Apple Developer Program 更新忘れ | 高     | 低       | カレンダーリマインダー、自動更新設定                          |

---

## 11. KPI と成功指標

### 初年度目標

| 指標            | 目標    | 測定方法      |
| --------------- | ------- | ------------- |
| ダウンロード数  | 5,000   | Web Analytics |
| 有料転換率      | 10%     | nukosuku.com  |
| 有料ユーザー数  | 500     | nukosuku.com  |
| MRR             | $4,000  | nukosuku.com  |
| 解約率（Churn） | 5% 以下 | nukosuku.com  |
| NPS             | 50 以上 | アンケート    |

### 機能別 KPI

| 機能         | 指標            | 目標       |
| ------------ | --------------- | ---------- |
| 音声認識     | 認識精度（WER） | 10% 以下   |
| フィラー削除 | 適切な削除率    | 90% 以上   |
| ペースト     | 成功率          | 99% 以上   |
| 起動         | 起動時間        | 500ms 以下 |

---

## 12. 付録

### A. 用語集

| 用語           | 説明                                                    |
| -------------- | ------------------------------------------------------- |
| SpeechAnalyzer | macOS 26+ で導入された Apple のオンデバイス音声認識 API |
| Push-to-Talk   | キーを押している間だけ録音するモード                    |
| Toggle Mode    | 1 回押しで開始、もう 1 回押しで終了するモード           |
| フィラー       | 「えー」「あー」などの言い淀み                          |
| BYOK           | Bring Your Own Key - ユーザーが自分の API キーを使用    |
| WER            | Word Error Rate - 音声認識の精度指標                    |

### B. 参考リンク

**競合サービス**:

- [Aqua Voice](https://aquavoice.com/)
- [Superwhisper](https://superwhisper.com/)
- [Wispr Flow](https://wisprflow.ai/)
- [VoiceInk](https://tryvoiceink.com/)

**技術資料**:

- [Apple SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Sparkle](https://sparkle-project.org/)
- [Stripe Billing](https://stripe.com/billing)

**価格戦略参考**:

- [Manus AI Pricing](https://manus.im/pricing)

---

## 更新履歴

| バージョン | 日付       | 変更内容                                           |
| ---------- | ---------- | -------------------------------------------------- |
| v1.0       | 2025-12-18 | 初版作成（市場調査・技術選定中心）                 |
| v2.0       | 2026-01-09 | 現状実装を反映、商用リリース向けに再構成           |
| v2.1       | 2026-02-27 | Stripe 統合削除、nukosuku.com 認証に統一、現状反映 |
