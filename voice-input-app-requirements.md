# Nice Voice - Mac 音声入力アプリケーション 要件定義書

## サービス概要

| 項目           | 内容                                      |
| -------------- | ----------------------------------------- |
| サービス名     | **Nice Voice**                            |
| ドメイン       | **nicevoice.app**                         |
| ターゲット市場 | グローバル（初期は日本市場中心）          |
| 対応言語       | 日本語・英語（アプリ UI、Web サイト両方） |

---

## エグゼクティブサマリー

Mac 標準の音声入力を超える、開発者・クリエイター向けの高精度音声入力アプリケーションを開発する。クラウド API による高精度認識と、オフラインモード（Lifetime 限定）によるプライバシー保護を両立させる。

### ターゲットユーザー

1. 開発者・エンジニア（技術用語の認識精度を求める）
2. ライター・クリエイター（長文入力の効率化）
3. RSI（反復性ストレス障害）を持つユーザー
4. プライバシーを重視するユーザー

### 競合との差別化

| 競合             | 強み                 | 弱み                      | Nice Voice の差別化            |
| ---------------- | -------------------- | ------------------------- | ------------------------------ |
| Mac 標準音声入力 | 無料、システム統合   | 精度低、カスタマイズ不可  | 高精度、カスタム辞書、LLM 連携 |
| Aqua Voice       | 技術用語 97.3%       | クラウド必須、$8/月       | オフラインモード、日本語特化   |
| Superwhisper     | 完全オフライン       | 設定が複雑、$249          | シンプル UX、段階的プラン      |
| Wispr Flow       | HIPAA 対応、IDE 統合 | **RAM 800MB**（Electron） | **軽量ネイティブ**（Swift）    |
| VoiceInk         | OSS、$25-39          | 機能限定                  | LLM 後処理、プレミアム機能     |

---

## 市場調査サマリー

### 1. 商用音声入力サービス（2025年12月時点）

| サービス     | 価格        | オフライン | 処理方式     | 特徴                       |
| ------------ | ----------- | ---------- | ------------ | -------------------------- |
| Aqua Voice   | $8/月       | 不可       | クラウド     | 技術用語 97.3%、Avalon API |
| Willow Voice | $12-15/月   | 不可       | クラウド     | iOS 連携、200ms 遅延       |
| MacWhisper   | €69 買切    | 可能       | ローカル     | 話者分離、バッチ処理       |
| Superwhisper | $249 買切   | 可能       | ハイブリッド | モデル選択、多言語混合     |
| Wispr Flow   | $12/月      | 不可       | クラウド     | HIPAA、IDE 統合、RAM 800MB |
| VoiceInk     | $25-39 買切 | 可能       | ローカル     | OSS、コスパ最高            |

### 2. Mac 標準音声入力の制限

- カスタム語彙の追加機能なし
- 学習機能なし（使用しても精度向上しない）
- 技術用語・専門用語の精度が低い
- Intel Mac ではクラウド処理必須
- プログラマティックアクセスが制限
- 60 秒のセッション制限

### 3. オープンソース音声認識

| プロジェクト   | 特徴                                 | Nice Voice での採用 |
| -------------- | ------------------------------------ | ------------------- |
| whisper.cpp    | Apple Silicon 最適化、Core ML 対応   | ✅ オフラインモード |
| kotoba-whisper | 日本語特化、6.3 倍高速               | ✅ 日本語認識       |
| WhisperKit     | Swift ネイティブ、ストリーミング対応 | ✅ 検討中           |
| faster-whisper | GPU 最速だが Apple Silicon 非最適    | ❌                  |
| Distil-Whisper | 英語のみ                             | ❌                  |

### 4. 音声認識 API 比較（2025年12月時点）

| API                           | 価格/時間  | 日本語 WER  | リアルタイム | 推奨用途     |
| ----------------------------- | ---------- | ----------- | ------------ | ------------ |
| Groq Whisper Turbo            | **$0.04**  | 約 9-11%    | 擬似対応     | コスパ最強   |
| ElevenLabs Scribe v2          | $0.40      | **5% 未満** | 150ms        | 最高精度     |
| Deepgram Nova-3               | $0.26-0.46 | 7-16%       | 300ms        | リアルタイム |
| OpenAI GPT-4o Mini Transcribe | $0.18      | 改善中      | 対応         | OpenAI 連携  |

### 5. LLM 連携オプション

| 区分           | モデル           | 用途         | 備考                 |
| -------------- | ---------------- | ------------ | -------------------- |
| ローカル推奨   | **Qwen3-4B**     | 日本語後処理 | 119 言語対応、高性能 |
| ローカル軽量   | Gemma 2-2B-JPN   | 日本語特化   | GPT-3.5 相当         |
| クラウド安価   | GPT-4o-mini      | 汎用         | $0.15/M トークン     |
| クラウド高品質 | Claude Haiku 4.5 | 日本語優秀   | 日本語テスト 62%     |

---

## 価格モデル

### 基本方針

Screen Studio / CleanShot X の価格戦略を参考に設計:

- **50% のユーザーは Starter プランで満足**できる設計
- ヘビーユーザー向け機能（オフラインモード）は上位プランで提供
- 段階的値上げ戦略（Early Bird → 通常価格 → プレミアム価格）
- 決済は **Stripe** を使用

### プラン構成

| プラン          | 価格              | 対象            | 機能                                                                   |
| --------------- | ----------------- | --------------- | ---------------------------------------------------------------------- |
| **A. Starter**  | $8/月 or $69/年   | 50% のユーザー  | クラウド音声認識、基本 LLM 後処理、カスタム辞書 50 件                  |
| **B. Pro**      | $15/月 or $129/年 | パワーユーザー  | 高精度モデル（ElevenLabs）、カスタム辞書 300 件、優先サポート          |
| **C. Lifetime** | **$249 買い切り** | ヘビーユーザー  | **オフラインモード**、全機能、カスタム辞書無制限、1 年アップデート込み |
| C. 更新         | $49/年（任意）    | Lifetime 購入者 | 2 年目以降のアップデート                                               |

### オフラインモードの位置づけ

| 機能                               | Starter / Pro | Lifetime |
| ---------------------------------- | ------------- | -------- |
| クラウド音声認識                   | ✅            | ✅       |
| LLM 後処理（クラウド）             | ✅            | ✅       |
| ローカル Whisper（kotoba-whisper） | ❌            | ✅       |
| ローカル LLM（Ollama）             | ❌            | ✅       |
| Apple 標準音声入力（オフライン）   | ❌            | ✅       |
| ネットワーク不要での動作           | ❌            | ✅       |

### 特別施策

| 施策                 | 内容                                                | 実装                                       |
| -------------------- | --------------------------------------------------- | ------------------------------------------ |
| **ぬこスク**         | ぬこスク加入者のうち最初の 100 名に初月無料クーポン | Stripe Coupon（盗難防止にアカウント紐付け  |
| **フィードバック割** | 有益なフィードバック 10 個以上で翌月無料クーポン    | フィードバックフォーム経由で申請、手動発行 |
| **Early Bird**       | ローンチ〜1 ヶ月: Lifetime $199                     | Stripe Price                               |
| **学生割引**         | 30% オフ                                            | SheerID認証                                |
| **30 日返金保証**    | 全プラン対象                                        | Stripe Refund                              |

### 段階的値上げ計画

| フェーズ   | 時期             | Lifetime 価格 | 目的             |
| ---------- | ---------------- | ------------- | ---------------- |
| Early Bird | ローンチ〜1 ヶ月 | $199          | 初期ユーザー獲得 |
| 通常価格   | 2 ヶ月目〜       | $249          | 収益安定化       |
| 値上げ 1   | 6 ヶ月後         | $299          | ブランド価値向上 |
| 値上げ 2   | 1 年後           | $349          | プレミアム化     |

### 将来プラン

| プラン             | 内容                                      | 時期           |
| ------------------ | ----------------------------------------- | -------------- |
| **法人向けプラン** | 管理画面、SSO、一括ライセンス、請求書払い | ユーザー増加後 |

---

## 機能要件

### Phase 1: MVP（最小実行可能製品）

#### 1.1 コア機能

| 機能                 | 説明                                   | 優先度 |
| -------------------- | -------------------------------------- | ------ |
| グローバルホットキー | カスタマイズ可能なショートカットで起動 | 必須   |
| Push-to-Talk         | キー押下中のみ録音                     | 必須   |
| Toggle Mode          | 1 回押しで開始/終了                    | 必須   |
| 音声認識（クラウド） | Groq / ElevenLabs API による高精度認識 | 必須   |
| テキスト挿入         | アクティブなアプリに直接挿入           | 必須   |
| メニューバー常駐     | バックグラウンド動作                   | 必須   |
| 日英 UI 切り替え     | アプリ内言語設定                       | 必須   |

#### 1.2 認識エンジン

| モード             | エンジン                               | 対象プラン    |
| ------------------ | -------------------------------------- | ------------- |
| クラウド（標準）   | Groq Whisper Turbo                     | 全プラン      |
| クラウド（高精度） | ElevenLabs Scribe v2                   | Pro 以上      |
| オフライン         | whisper.cpp + kotoba-whisper-v2.0-ggml | Lifetime のみ |

#### 1.3 UI/UX

| 要件                     | 詳細                                |
| ------------------------ | ----------------------------------- |
| 録音インジケーター       | 音量レベルのリアルタイム表示        |
| 状態表示                 | 録音中 / 処理中 / 完了 の明確な区別 |
| フローティングウィンドウ | 認識結果のプレビュー表示            |
| サウンドフィードバック   | 開始/終了時の効果音（オプション）   |

### Phase 2: 差別化機能

#### 2.1 LLM 連携

| 機能           | 説明                                   | 対象プラン |
| -------------- | -------------------------------------- | ---------- |
| フィラー除去   | 「えー」「あー」などの自動削除         | 全プラン   |
| 句読点自動挿入 | 文脈に基づく句読点の追加               | 全プラン   |
| 文法修正       | 軽微な文法エラーの自動修正             | Pro 以上   |
| スタイル調整   | アプリごとのトーン調整（メール/Slack） | Pro 以上   |

LLM オプション:

- クラウド: GPT-4o-mini / Claude Haiku（BYOK 対応）
- ローカル: Ollama + Qwen3-4B / Gemma 2-2B-JPN（Lifetime のみ）

#### 2.2 コンテキスト認識

| 機能               | 説明                         |
| ------------------ | ---------------------------- |
| アプリ検出         | アクティブなアプリを自動検出 |
| スタイルプリセット | アプリごとの出力スタイル設定 |
| カスタム辞書       | 専門用語・固有名詞の登録     |
| 学習機能           | 使用パターンからの自動学習   |

#### 2.3 開発者向け機能

| 機能             | 説明                                  |
| ---------------- | ------------------------------------- |
| コードモード     | 変数名・関数名の認識向上              |
| 技術用語辞書     | プリセット辞書（React, Python, etc.） |
| カスタムコマンド | 音声コマンドの定義                    |

### Phase 3: 高度な機能

#### 3.1 マルチモーダル

| 機能                   | 説明                                 |
| ---------------------- | ------------------------------------ |
| スクリーンショット連携 | 画面内容を考慮した認識               |
| コマンドモード         | 「修正して」「言い換えて」などの指示 |

#### 3.2 ワークフロー統合

| 機能             | 説明                           |
| ---------------- | ------------------------------ |
| Raycast 拡張     | Raycast からの起動・操作       |
| Shortcuts 対応   | Apple Shortcuts との連携       |
| AppleScript 対応 | 自動化スクリプトからの呼び出し |

---

## 非機能要件

### パフォーマンス

| 指標                         | 目標値                              |
| ---------------------------- | ----------------------------------- |
| 起動時間                     | 500ms 以内                          |
| 認識レイテンシ（クラウド）   | 録音終了から 800ms 以内             |
| 認識レイテンシ（オフライン） | 録音終了から 500ms 以内             |
| メモリ使用量                 | 待機時 50MB 以下、録音時 200MB 以下 |
| CPU 使用率                   | 待機時 0%、録音時 50% 以下          |
| バッテリー影響               | 待機時は影響なし                    |

### 互換性

| 要件             | 詳細                                     |
| ---------------- | ---------------------------------------- |
| macOS バージョン | macOS 26 以降                            |
| チップ           | Apple Silicon（M1 以降）推奨、Intel 対応 |
| アーキテクチャ   | Universal Binary（arm64 + x86_64）       |

### セキュリティ・プライバシー

| 要件         | 詳細                                                          |
| ------------ | ------------------------------------------------------------- |
| データ保存   | 音声データはローカルのみ、一時ファイルは即時削除              |
| ネットワーク | クラウドモードでは API 通信あり、オフラインモードでは通信なし |
| 権限         | マイク、アクセシビリティ（テキスト挿入用）                    |
| API キー保存 | Keychain Services で暗号化保存                                |

---

## 技術アーキテクチャ

### 技術スタック

| レイヤー               | 技術                                        | 理由                                   |
| ---------------------- | ------------------------------------------- | -------------------------------------- |
| フレームワーク         | Swift 6 / SwiftUI                           | ネイティブ、最高のパフォーマンス、軽量 |
| 音声キャプチャ         | AVAudioEngine                               | 低レイテンシ、簡潔な API               |
| 音声認識（クラウド）   | Groq / ElevenLabs API                       | 高精度、低コスト                       |
| 音声認識（オフライン） | WhisperKit or SwiftWhisper + kotoba-whisper | Apple Silicon 最適化、日本語特化       |
| ホットキー             | KeyboardShortcuts                           | SwiftUI 統合、サンドボックス対応       |
| テキスト挿入           | NSPasteboard + CGEvent (Cmd+V)              | 最も安定、IME 互換                     |
| メニューバー           | MenuBarExtra (.window)                      | 最新 SwiftUI API                       |
| 状態管理               | @Observable + @Environment                  | 最新の推奨パターン                     |
| LLM（クラウド）        | GPT-4o-mini / Claude Haiku API              | 高品質、低コスト                       |
| LLM（ローカル）        | Ollama + OllamaKit                          | Swift 統合、Qwen3-4B 推奨              |
| 決済                   | Stripe                                      | ライセンス管理、クーポン対応           |
| 自動更新               | Sparkle                                     | デファクトスタンダード                 |

### アーキテクチャ図

```
┌─────────────────────────────────────────────────────────┐
│                  Nice Voice Application                  │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Menu Bar    │  │  Floating    │  │  Settings    │  │
│  │  (SwiftUI)   │  │  Window      │  │  Panel       │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
├─────────────────────────────────────────────────────────┤
│                    Core Services                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Hotkey      │  │  Audio       │  │  Text        │  │
│  │  Manager     │  │  Capture     │  │  Insertion   │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
├─────────────────────────────────────────────────────────┤
│                    Recognition Engine                   │
│  ┌─────────────────────────┐  ┌─────────────────────┐  │
│  │  Cloud Mode             │  │  Offline Mode       │  │
│  │  ┌─────────┐ ┌────────┐│  │  (Lifetime Only)    │  │
│  │  │  Groq   │ │Eleven- ││  │  ┌────────────────┐ │  │
│  │  │ Whisper │ │Labs    ││  │  │ WhisperKit +   │ │  │
│  │  └─────────┘ └────────┘│  │  │ kotoba-whisper │ │  │
│  └─────────────────────────┘  │  └────────────────┘ │  │
│                               └─────────────────────┘  │
├─────────────────────────────────────────────────────────┤
│                    LLM Post-Processing                  │
│  ┌─────────────────────────┐  ┌─────────────────────┐  │
│  │  Cloud LLM              │  │  Local LLM          │  │
│  │  ┌─────────┐ ┌────────┐│  │  (Lifetime Only)    │  │
│  │  │GPT-4o   │ │Claude  ││  │  ┌────────────────┐ │  │
│  │  │mini     │ │Haiku   ││  │  │ Ollama +       │ │  │
│  │  └─────────┘ └────────┘│  │  │ Qwen3-4B       │ │  │
│  └─────────────────────────┘  │  └────────────────┘ │  │
│                               └─────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### ディレクトリ構造

```
NiceVoice/
├── App/
│   ├── NiceVoiceApp.swift        # エントリーポイント
│   └── AppDelegate.swift         # アプリデリゲート
├── Views/
│   ├── MenuBarView.swift         # メニューバー UI
│   ├── FloatingWindow.swift      # フローティングウィンドウ
│   ├── SettingsView.swift        # 設定画面
│   ├── OnboardingView.swift      # オンボーディング
│   └── Components/
│       ├── WaveformView.swift    # 音声波形表示
│       └── StatusIndicator.swift
├── Services/
│   ├── AudioCaptureService.swift      # 音声キャプチャ
│   ├── CloudRecognitionService.swift  # クラウド音声認識
│   ├── LocalRecognitionService.swift  # ローカル音声認識
│   ├── TextInsertionService.swift     # テキスト挿入
│   ├── HotkeyService.swift            # ホットキー管理
│   ├── LLMService.swift               # LLM 連携
│   └── LicenseService.swift           # ライセンス管理
├── Models/
│   ├── RecognitionResult.swift
│   ├── AppSettings.swift
│   ├── CustomDictionary.swift
│   └── Subscription.swift
├── Resources/
│   ├── Models/                   # Whisper モデル（オフライン用）
│   ├── Sounds/                   # 効果音
│   └── Localizable/              # 日英ローカライズ
│       ├── en.lproj/
│       └── ja.lproj/
└── Tests/
```

---

## 配布方法

### Developer ID（公証付き直接配布）

| 項目     | 詳細                                      |
| -------- | ----------------------------------------- |
| 配布方式 | Developer ID + Notarization               |
| 理由     | CGEventPost を使用するため App Store 不可 |
| 自動更新 | Sparkle フレームワーク                    |
| 決済     | Stripe                                    |

### 初期費用

| 項目                      | 費用           |
| ------------------------- | -------------- |
| Apple Developer Program   | $99/年         |
| ドメイン（nicevoice.app） | $15.62/年      |
| **合計**                  | **約 $115/年** |

---

## 開発ロードマップ

### Phase 1: MVP（8-12 週間）

| 週    | マイルストーン                            |
| ----- | ----------------------------------------- |
| 1-2   | プロジェクトセットアップ、Groq API 統合   |
| 3-4   | 音声キャプチャ、基本認識機能              |
| 5-6   | テキスト挿入、ホットキー実装              |
| 7-8   | メニューバー UI、フローティングウィンドウ |
| 9-10  | 設定画面、Stripe 統合、ライセンス管理     |
| 11-12 | 日英ローカライズ、テスト、公証            |

### Phase 2: 差別化機能（6-8 週間）

| 週  | マイルストーン                          |
| --- | --------------------------------------- |
| 1-2 | LLM 後処理（GPT-4o-mini）、フィラー除去 |
| 3-4 | オフラインモード（kotoba-whisper）      |
| 5-6 | カスタム辞書、コンテキスト認識          |
| 7-8 | ローカル LLM（Ollama）、テスト          |

### Phase 3: 高度な機能（4-6 週間）

| 週  | マイルストーン               |
| --- | ---------------------------- |
| 1-2 | コマンドモード               |
| 3-4 | Raycast / Shortcuts 連携     |
| 5-6 | マルチモーダル機能（実験的） |

### Phase 4: 法人向け（ユーザー増加後）

| マイルストーン       |
| -------------------- |
| 管理画面の設計・実装 |
| SSO / SAML 対応      |
| 一括ライセンス管理   |
| 請求書払い対応       |

---

## リスクと対策

| リスク                  | 影響 | 対策                                                         |
| ----------------------- | ---- | ------------------------------------------------------------ |
| クラウド API のコスト増 | 高   | Groq Turbo（$0.04/時間）でコスト最小化、使用量制限           |
| 日本語認識精度不足      | 高   | kotoba-whisper（日本語特化）の採用、ElevenLabs Scribe の併用 |
| Apple API の変更        | 中   | macOS バージョンごとの条件分岐                               |
| 競合の急成長            | 中   | 日本語特化・軽量ネイティブで差別化                           |
| Stripe 連携の複雑さ     | 中   | 既存ライブラリ（Keygen.sh 等）の活用検討                     |

---

## 参考リンク

### 競合サービス

- [Aqua Voice](https://aquavoice.com/) - 技術用語 97.3%、Avalon API
- [Willow Voice](https://willowvoice.com/) - iOS 連携、エンタープライズ向け
- [Superwhisper](https://superwhisper.com/) - 完全オフライン、$249 永久
- [Wispr Flow](https://wisprflow.ai/) - HIPAA 対応、IDE 統合、RAM 800MB
- [VoiceInk](https://tryvoiceink.com/) - OSS、$25-39 買い切り
- [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) - 話者分離、€69

### 技術資料

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) - Apple Silicon 最適化
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Swift ネイティブ、ストリーミング対応
- [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) - whisper.cpp Swift ラッパー
- [kotoba-whisper](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.0) - 日本語特化、6.3 倍高速
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - グローバルホットキー
- [OllamaKit](https://github.com/kevinhermawan/OllamaKit) - Ollama Swift Package
- [Sparkle](https://sparkle-project.org/) - 自動アップデート

### 音声認識 API

- [Groq Whisper API](https://groq.com/pricing) - 最速、$0.04/時間（Turbo）
- [ElevenLabs Scribe](https://elevenlabs.io/speech-to-text) - 日本語 WER 5% 未満
- [Deepgram Nova-3](https://deepgram.com/pricing) - リアルタイム対応

### LLM API

- [Claude Haiku 4.5](https://www.anthropic.com/claude/haiku) - 日本語優秀
- [GPT-4o-mini](https://platform.openai.com/docs/models/gpt-4o-mini) - $0.15/M トークン

### 価格戦略参考

- [Screen Studio](https://www.screen.studio/) - $89→$229→サブスク移行
- [CleanShot X](https://cleanshot.com/) - $29 買い切り + $19/年更新

### 参考 OSS プロジェクト

- [Vocorize](https://github.com/vocorize/app) - Swift Composable Architecture
- [Maccy](https://github.com/p0deje/Maccy) - テキスト挿入実装参考

---

## TODO

### 実装前に完了すべき調査

- [ ] **競合フィードバック調査**: Aqua Voice、Willow Voice、Superwhisper、Wispr Flow、VoiceInk のユーザーレビュー・不満点を収集（Reddit、Twitter、Product Hunt、App Store レビュー）

---

## 調査実施日

2025 年 12 月 18 日（初版: 2025 年 12 月 16 日）

## 調査対象

1. 商用音声入力サービス（Aqua Voice, Willow Voice, MacWhisper, Superwhisper, Wispr Flow, VoiceInk）
2. Mac 標準音声入力（Dictation, SFSpeechRecognizer）
3. オープンソース音声認識（whisper.cpp, WhisperKit, kotoba-whisper, faster-whisper）
4. クラウド音声認識 API（Groq, ElevenLabs, Deepgram, OpenAI, Google）
5. LLM 連携（Ollama, Qwen3, Gemma 2, Claude, GPT-4o）
6. 価格戦略（Screen Studio, CleanShot X）
7. Swift/macOS 実装技術（AVAudioEngine, KeyboardShortcuts, WhisperKit, OllamaKit）
8. 配布・決済（Developer ID, Notarization, Stripe, Sparkle）
