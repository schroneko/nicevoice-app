# Access Modes

NiceVoice は、配布の考え方を 2 つのモードで扱います。

- `preview`: 現在の運用。ぬこスク加入者向けの先行配布
- `public`: 将来の運用。一般公開モード

現在のコードは、`preview` を前提にしています。課金ライセンスというより、`先行アクセス権` を判定する設計です。

## 今の運用

- 配布方法: 直配布 / Homebrew
- 利用条件: ぬこスク加入者がログインして先行アクセス権を確認
- 文言: 「単体販売」ではなく「先行配布」「先行アクセス」

## 一般公開に切り替えるとき

一般公開するときは、まずアクセスモードだけを切り替えます。

```bash
swift Scripts/set-access-mode.swift public
swift test
```

これでアプリは `publicRelease` 扱いになります。ログインしていないユーザーでも利用できます。

切り替え後にやること:

1. [page.ts](/Users/username/Sync/nicevoice-web/src/lp/page.ts) の「先行配布中」文言を「一般公開中」に更新する
2. 更新履歴と告知文を追加する
3. リリースビルドを作成して配布する

```bash
./Scripts/package-app.sh --configuration release
```

## 先行配布モードへ戻すとき

```bash
swift Scripts/set-access-mode.swift preview
swift test
```

## 実装メモ

- 実際のモード判定は [AppSupport.swift](/Users/username/Sync/nicevoice-app/Sources/NiceVoice/AppSupport.swift) の `AppAccessPolicy` が行います
- モード文字列は [ObfuscatedStrings.swift](/Users/username/Sync/nicevoice-app/Sources/NiceVoice/ObfuscatedStrings.swift) に難読化して保存しています
- この難読化は抑止目的です。完全な防御ではありません
- 先行配布中の利用可否は、引き続きサーバー側の認証結果が本体です
