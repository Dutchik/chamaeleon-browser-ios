# UPDATE_PROTOCOL (iOS)

1. 仕様確認: `docs/MASTER_SPEC.md` の該当セクションを読む
2. データモデル変更はPC版 `src/shared/types.ts` が原典。iOS側だけで構造を変えない。
   変更が必要ならPC版リポジトリにIssue/PRを出し、両方の `docs/DATA_MODEL.md` を更新する
3. パッチ注入・DOMルールのJS生成は `Chamaeleon/BrowserView.swift` の `PatchEngine` に集約する
4. 検証（必須・CIも同じ）:
   `xcodegen generate && xcodebuild -project Chamaeleon.xcodeproj -scheme Chamaeleon -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
5. セキュリティ確認: MASTER_SPEC §14 に反していないか
