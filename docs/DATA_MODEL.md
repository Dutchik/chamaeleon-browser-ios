# DATA_MODEL (iOS)

**原典はPC版リポジトリ [chamaeleon-browser](https://github.com/Dutchik/chamaeleon-browser) の `src/shared/types.ts`。**
本リポジトリの `Chamaeleon/Models.swift` は同一構造の Codable 実装。

## iOSで実装済みのエンティティ

| 型 | 状態 |
|---|---|
| `SiteProfile` / `CssPatch` / `JsPatch` / `DomRule` / `SiteNote` | ✅ 実装済み |
| `AutomationMacro` / `AutomationStep` / `AutomationTrigger` | ⬜ 未実装（Issue参照） |
| `ExecutionLog` / `DevReport` | ⬜ 未実装 |

## 保存

`Documents/chamaeleon-profiles.json` に `[SiteProfile]` をJSONEncoderで保存。
フィールド追加はデフォルト値付きで行い、旧JSONを読めるまま保つ。

## URLマッチ仕様（PC版と共通）

- `exact`: 完全一致 / `domain`: host一致 or `.pattern` 後方一致 / `path`・`wildcard`: `*`→`.*` の全体一致 / `regex`: 部分一致
- 実装: `SiteProfile.matches(_:)`（PC版 `matchesProfile()` と同一挙動を保つこと）
