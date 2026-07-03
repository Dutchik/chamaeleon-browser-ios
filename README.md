# 🦎 Chamaeleon Browser for iOS

Webページを「見る」だけでなく、**自分の使いやすい形へ変形し、再訪問時に再現する**カスタムブラウザの **iPhone / iPad 版**。

**PC版（Windows / macOS / Linux）は → [Dutchik/chamaeleon-browser](https://github.com/Dutchik/chamaeleon-browser)**

技術: SwiftUI + WKWebView（iOS 16+）

## 実装済み機能

- WKWebView ブラウザ（URLバー・戻る/進む/更新・検索）
- 🦎 バッジ: 現在ページに適用中の Site Profile 数を表示 → タップで Site Panel
- **Site Profile**: exact / domain / path / wildcard / regex の5種URLマッチ
- **CSS Patch**: ページ読み込み時に自動注入
- **JS Patch**: 自動実行＋「今すぐ実行」
- **DOM Rule**: hide / remove / highlight / replaceText / addClass / setStyle / move / click / input（要素出現待ち付き）
- **メモ**: ページごとの記録
- JSON 保存（`Documents/chamaeleon-profiles.json`）

## 未実装（Issues参照）

- Automation マクロ（記録・再生）
- PC版とのプロファイル共有（import/export）

## 開発

前提: macOS + Xcode 15+、`brew install xcodegen`

```bash
xcodegen generate
open Chamaeleon.xcodeproj   # ▶ で実行
```

CLIビルド検証:

```bash
xcodebuild -project Chamaeleon.xcodeproj -scheme Chamaeleon \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## データモデル

**原典はPC版リポジトリの `src/shared/types.ts`**。本リポジトリの `Chamaeleon/Models.swift` は同一構造の Codable。
どちらかを変更する場合は両リポジトリで同期し、`docs/DATA_MODEL.md` を更新すること（詳細は docs/UPDATE_PROTOCOL.md）。

## セキュリティ方針（仕様§14）

- ユーザーが明示的に登録したページにのみパッチを適用する
- パスワード値の記録・CAPTCHA回避・機密情報の外部送信は実装しない

## License

MIT
