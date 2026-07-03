# Copilot Instructions — Chamaeleon Browser for iOS

「Webページ毎にCSS/JS/DOM操作を登録し再訪問時に自動適用するカスタムブラウザ」の **iOS版（SwiftUI + WKWebView, iOS 16+）** です。
PC版（データモデルの原典）: https://github.com/Dutchik/chamaeleon-browser

## 必読

1. `docs/MASTER_SPEC.md` — 全体仕様の原典
2. `docs/DATA_MODEL.md` — データモデル（PC版 `src/shared/types.ts` と同期）
3. `docs/UPDATE_PROTOCOL.md` — 変更手順

## 構成

- `project.yml` — xcodegen 定義。`.xcodeproj` はこれから生成する（直接編集しない）
- `Chamaeleon/Models.swift` — Codable データモデル
- `Chamaeleon/BrowserView.swift` — WKWebView + PatchEngine（CSS/JS/DOMルール注入）
- `Chamaeleon/ContentView.swift` / `SitePanelView.swift` — UI

## 検証コマンド（PR前に必ず通すこと）

```bash
brew install xcodegen  # 未導入時
xcodegen generate
xcodebuild -project Chamaeleon.xcodeproj -scheme Chamaeleon \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## ルール

- データモデルの構造をiOS側だけで変えない（PC版と同期）
- MASTER_SPEC §14: パスワード値の記録・CAPTCHA回避・外部送信は実装しない
- UIテキストは日本語で統一
