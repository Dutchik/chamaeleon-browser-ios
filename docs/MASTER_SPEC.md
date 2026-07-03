# Chamaeleon Browser 仕様書

作成日: 2026-07-03  
プロジェクト名: Chamaeleon Browser / Awokela Motion Browser  
対象環境: Windows / macOS / Linux（Electron）、iPhone / iPad（SwiftUI + WKWebView）  
想定技術: Electron / React / TypeScript / Vite、SwiftUI / WebKit

---

## 1. 概要

Chamaeleon Browser は、Webページごとに CSS / JavaScript / DOM 操作 / 自動化操作を登録し、ユーザーがそのページを訪れるたびに自動適用できるカスタムブラウザである。

通常のブラウザ拡張やユーザースクリプトよりも、日常利用・開発補助・業務自動化・UI改造に寄せた設計とする。

本ブラウザの中心思想は以下である。

> Webページを「見る」だけでなく、自分の使いやすい形へ変形し、操作を記録し、再訪問時に再現する。

---

## 2. 目的

### 2.1 主目的

- 登録したWebページに対して CSS を自動適用する
- 登録したWebページに対して JavaScript を自動実行する
- ユーザー操作を記録し、マクロとして再生する
- URL / ドメイン / パス / 正規表現ごとに設定を保存する
- Webページ訪問時に登録済みの改造・自動化を自動実行する
- 開発作業や日常Web操作を軽量に自動化する

### 2.2 副目的

- Webページごとのメモ、改修ログ、開発レポートを残す
- CSS / JS / 自動化レシピを将来的に Awokela Store で共有できるようにする
- Selenium のような重い自動化ではなく、日常利用できるブラウザ内マクロとして提供する
- ブラウザ上で簡易的なDOM検査・要素選択・パッチ作成を可能にする

---

## 3. 想定ユーザー

- 開発者
- Web制作・検証担当者
- 業務Webシステムを毎日操作するユーザー
- 既存WebサービスのUIを自分好みに変えたいユーザー
- 繰り返し作業を記録・再生したいユーザー
- 自作ツールをブラウザに組み込みたいパワーユーザー

---

## 4. 基本機能

## 4.1 ブラウザ基本機能

### 必須機能

- タブ表示
- URL入力欄
- 戻る / 進む / 更新 / 停止
- ホームページ設定
- ブックマーク
- 履歴
- ダウンロード管理
- DevTools 起動
- ユーザーエージェント設定

### 将来機能

- ワークスペース
- セッション復元
- タブグループ
- 垂直タブ
- プライベートモード
- プロキシ設定
- Cookie / LocalStorage 管理UI

---

## 5. Site Profile 機能

## 5.1 概要

Site Profile は、URLまたはドメインごとに CSS / JS / DOM操作 / 自動化マクロ / メモ / 実行条件を保存する単位である。

例:

- `https://example.com/*`
- `https://example.com/dashboard/*`
- `*.example.com`
- 正規表現: `^https://example\.com/user/[0-9]+`

---

## 5.2 Site Profile の項目

```ts
interface SiteProfile {
  id: string;
  name: string;
  enabled: boolean;
  matchType: 'exact' | 'domain' | 'path' | 'wildcard' | 'regex';
  matchPattern: string;
  description?: string;
  cssPatches: CssPatch[];
  jsPatches: JsPatch[];
  domRules: DomRule[];
  automations: AutomationMacro[];
  notes: SiteNote[];
  createdAt: string;
  updatedAt: string;
}
```

---

## 5.3 URLマッチ方式

### exact

完全一致。

```text
https://example.com/dashboard
```

### domain

ドメイン単位。

```text
example.com
```

### path

パス単位。

```text
https://example.com/dashboard/*
```

### wildcard

ワイルドカード。

```text
https://*.example.com/*
```

### regex

正規表現。

```text
^https://example\.com/items/[0-9]+$
```

---

## 6. CSS Patch 機能

## 6.1 概要

登録したCSSを、該当ページ訪問時に自動で注入する。

用途:

- 広告領域の非表示
- 文字サイズ変更
- 配色変更
- レイアウト調整
- 不要UIの削除
- 重要項目の強調
- ダークテーマ化

---

## 6.2 CSS Patch データ構造

```ts
interface CssPatch {
  id: string;
  name: string;
  enabled: boolean;
  code: string;
  runAt: 'document_start' | 'document_end' | 'idle';
  priority: number;
  createdAt: string;
  updatedAt: string;
}
```

---

## 6.3 CSS Patch 例

```css
/* 不要なサイドバーを消す */
.sidebar,
.ad-area {
  display: none !important;
}

/* メイン領域を広げる */
.main-content {
  max-width: 1200px !important;
  margin: 0 auto !important;
}
```

---

## 7. JavaScript Patch 機能

## 7.1 概要

登録したJavaScriptを、該当ページ訪問時に自動実行する。

用途:

- DOM操作
- ボタン自動クリック
- 入力補助
- UI追加
- ページ内データ抽出
- 自動スクロール
- フォーム補完
- SPAページの監視

---

## 7.2 JS Patch データ構造

```ts
interface JsPatch {
  id: string;
  name: string;
  enabled: boolean;
  code: string;
  runAt: 'document_start' | 'document_end' | 'idle' | 'manual';
  priority: number;
  sandbox: boolean;
  allowDomAccess: boolean;
  createdAt: string;
  updatedAt: string;
}
```

---

## 7.3 JS Patch 例

```js
// ページ内の特定ボタンを強調する
const buttons = document.querySelectorAll('button');
buttons.forEach((button) => {
  if (button.textContent?.includes('保存')) {
    button.style.border = '2px solid red';
    button.style.fontWeight = 'bold';
  }
});
```

---

## 8. DOM Rule 機能

## 8.1 概要

コードを書かずに、特定のDOM要素に対して簡単な操作を登録できる機能。

---

## 8.2 DOM Rule 種類

- hide: 非表示
- remove: 削除
- highlight: 強調
- replaceText: テキスト置換
- addClass: クラス追加
- setStyle: style 直接指定
- move: 要素移動
- click: 自動クリック
- input: 自動入力

---

## 8.3 DOM Rule データ構造

```ts
interface DomRule {
  id: string;
  name: string;
  enabled: boolean;
  selector: string;
  action: 'hide' | 'remove' | 'highlight' | 'replaceText' | 'addClass' | 'setStyle' | 'move' | 'click' | 'input';
  value?: string;
  runAt: 'document_start' | 'document_end' | 'idle';
  waitForSelector: boolean;
  timeoutMs: number;
}
```

---

## 9. 自動化記録機能

## 9.1 概要

ユーザーのブラウザ操作を記録し、後から再生できるマクロとして保存する。

記録対象:

- クリック
- 入力
- キー操作
- ページ遷移
- スクロール
- 待機
- 要素出現待ち
- フォーム送信
- ファイル選択
- タブ操作

---

## 9.2 Automation Macro データ構造

```ts
interface AutomationMacro {
  id: string;
  name: string;
  enabled: boolean;
  trigger: AutomationTrigger;
  steps: AutomationStep[];
  createdAt: string;
  updatedAt: string;
}
```

---

## 9.3 Trigger 種類

```ts
interface AutomationTrigger {
  type: 'manual' | 'onPageLoad' | 'onUrlMatch' | 'onElementAppear' | 'schedule';
  value?: string;
}
```

### manual

ユーザーが手動実行する。

### onPageLoad

ページ読み込み後に自動実行する。

### onUrlMatch

指定URLに一致した時に実行する。

### onElementAppear

指定セレクタの要素が出現した時に実行する。

### schedule

指定時間や間隔で実行する。初期版では後回し。

---

## 9.4 Automation Step 種類

```ts
interface AutomationStep {
  id: string;
  type:
    | 'click'
    | 'input'
    | 'keydown'
    | 'scroll'
    | 'wait'
    | 'waitForSelector'
    | 'navigate'
    | 'submit'
    | 'select'
    | 'check'
    | 'uncheck'
    | 'extractText'
    | 'runJavaScript';
  selector?: string;
  value?: string;
  delayMs?: number;
  timeoutMs?: number;
  url?: string;
}
```

---

## 9.5 記録方式

### 記録開始

ユーザーが「記録開始」ボタンを押す。

### 記録中

以下を取得する。

- 操作種別
- 対象要素のCSS selector
- 対象要素のXPath
- 対象要素のテキスト
- 入力値
- 発生時刻
- 前操作からの経過時間

### 記録終了

ユーザーが「記録停止」ボタンを押す。

### 保存

記録内容を Automation Macro として保存する。

---

## 9.6 Selector 生成方針

優先順位:

1. `id`
2. `data-testid`
3. `name`
4. `aria-label`
5. 安定した class
6. テキスト一致
7. DOM階層によるCSS selector
8. XPath

脆いセレクタを避けるため、保存時に候補を複数保持する。

```ts
interface ElementTarget {
  primarySelector: string;
  fallbackSelectors: string[];
  xpath?: string;
  textHint?: string;
}
```

---

## 10. パッチ適用エンジン

## 10.1 処理順序

ページ遷移時、以下の順で処理する。

1. 現在URLを取得
2. Site Profile を検索
3. 有効な Profile を抽出
4. CSS Patch を priority 順に注入
5. DOM Rule を実行
6. JS Patch を runAt 条件に従って実行
7. Automation Trigger を判定
8. 条件に合う Automation Macro を実行

---

## 10.2 SPA対応

React / Vue / Angular などのSPAでは通常のページ読み込みだけではURL変更を検知できない。

対応方法:

- `history.pushState` 監視
- `history.replaceState` 監視
- `popstate` 監視
- `MutationObserver` によるDOM変化監視
- URL変更時に Site Profile を再評価

---

## 11. UI仕様

## 11.1 メイン画面

構成:

- 上部: タブバー
- 上部: ナビゲーションバー
- 中央: WebView
- 右側: Site Panel
- 下部または右下: 記録ボタン / パッチ適用状態

---

## 11.2 Site Panel

現在ページに対する設定を表示・編集する。

表示項目:

- 現在URL
- 適用中の Site Profile
- CSS Patch 一覧
- JS Patch 一覧
- DOM Rule 一覧
- Automation Macro 一覧
- メモ
- 実行ログ

---

## 11.3 Patch Editor

CSS / JS を編集する画面。

機能:

- コードエディタ
- シンタックスハイライト
- 保存
- 一時適用
- 有効 / 無効切替
- 実行タイミング選択
- priority 設定
- エラー表示

推奨ライブラリ:

- Monaco Editor
- CodeMirror

---

## 11.4 Automation Recorder UI

機能:

- 記録開始
- 記録停止
- 一時停止
- ステップ一覧表示
- ステップ編集
- ステップ削除
- セレクタ再指定
- テスト再生
- 保存

---

## 12. データ保存仕様

## 12.1 初期版

初期版ではローカル保存を基本とする。

候補:

- JSON ファイル
- SQLite
- IndexedDB
- Electron Store

推奨:

- 設定: JSON / Electron Store
- 履歴・ログ・大量データ: SQLite

---

## 12.2 ディレクトリ構成

```text
chamaeleon-browser/
  app/
    main/
    renderer/
    preload/
  data/
    profiles/
    patches/
    automations/
    logs/
  docs/
    MASTER_SPEC.md
    FILE_STRUCTURE.md
    DATA_MODEL.md
    LOCAL_STORAGE_SCHEMA.md
    DATABASE_SCHEMA.md
    REBUILD_FROM_SCRATCH.md
    UPDATE_PROTOCOL.md
    DEV_REPORT_SYSTEM.md
```

---

## 12.3 保存ファイル例

```text
data/profiles/site-profiles.json
data/patches/css-patches.json
data/patches/js-patches.json
data/automations/macros.json
data/logs/execution-log.sqlite
```

---

## 13. データモデル

## 13.1 SiteNote

```ts
interface SiteNote {
  id: string;
  title: string;
  body: string;
  tags: string[];
  createdAt: string;
  updatedAt: string;
}
```

---

## 13.2 ExecutionLog

```ts
interface ExecutionLog {
  id: string;
  profileId: string;
  patchId?: string;
  automationId?: string;
  type: 'css' | 'js' | 'dom' | 'automation';
  status: 'success' | 'error' | 'skipped';
  message?: string;
  url: string;
  createdAt: string;
}
```

---

## 14. セキュリティ方針

## 14.1 基本方針

CSS / JS 注入と自動化は強力な機能であるため、ユーザーが明示的に登録したページにのみ適用する。

---

## 14.2 禁止・制限事項

- デフォルトで全サイト適用は禁止
- パスワード欄への自動入力は警告を出す
- 外部から取得したJS Patchは初回実行前に警告を出す
- Awokela Store で共有するパッチは審査・署名・ハッシュ検証を行う
- 銀行・証券・決済サイトでは自動操作に強い警告を表示する
- ユーザーの明示操作なしに機密情報を外部送信するJSは禁止

---

## 14.3 権限モデル

JS Patch ごとに権限を設定する。

```ts
interface PatchPermission {
  allowDomRead: boolean;
  allowDomWrite: boolean;
  allowNetwork: boolean;
  allowClipboard: boolean;
  allowStorage: boolean;
}
```

---

## 15. エラー処理

## 15.1 CSS Patch エラー

CSS構文エラーは保存時に警告する。  
ただしブラウザ側が無視可能なCSSは保存可能とする。

---

## 15.2 JS Patch エラー

JS実行時エラーは ExecutionLog に保存する。

表示内容:

- エラー種別
- メッセージ
- 行番号
- 対象URL
- 実行Patch名
- 発生時刻

---

## 15.3 Automation エラー

ステップ失敗時の挙動を選べるようにする。

- 停止
- スキップして続行
- リトライ
- ユーザー確認待ち

---

## 16. 開発レポート / 改修メモ機能

## 16.1 概要

ブラウザ自体の開発を進めるため、画面上に「改修メモ」ボタンを配置し、バグ・改善案・仕様変更を記録できるようにする。

---

## 16.2 機能

- 改修メモ作成
- 状態管理
  - 未着手
  - 作業中
  - 完了
  - 保留
- 優先度
  - Low
  - Medium
  - High
  - Critical
- タグ付け
- スクリーンショット添付
- CSV export/import
- Codex用プロンプト生成

---

## 16.3 DevReport データ構造

```ts
interface DevReport {
  id: string;
  title: string;
  body: string;
  status: 'todo' | 'doing' | 'done' | 'hold';
  priority: 'low' | 'medium' | 'high' | 'critical';
  tags: string[];
  relatedFile?: string;
  screenshotPath?: string;
  createdAt: string;
  updatedAt: string;
}
```

---

## 17. Codex連携用ドキュメント

プロジェクト内に以下のMDファイルを配置する。

```text
docs/MASTER_SPEC.md
docs/FILE_STRUCTURE.md
docs/DATA_MODEL.md
docs/LOCAL_STORAGE_SCHEMA.md
docs/DATABASE_SCHEMA.md
docs/REBUILD_FROM_SCRATCH.md
docs/UPDATE_PROTOCOL.md
docs/DEV_REPORT_SYSTEM.md
```

---

## 18. 実装フェーズ

## Phase 1: 最小ブラウザ

- Electron 起動
- WebView 表示
- URL入力
- 戻る / 進む / 更新
- タブ1枚
- DevTools起動

## Phase 2: Site Profile

- URLごとのProfile作成
- Profile保存
- Profile一覧
- URLマッチ処理
- Profile有効 / 無効切替

## Phase 3: CSS Patch

- CSS登録
- CSS自動注入
- CSS編集画面
- 一時適用
- priority対応

## Phase 4: JS Patch

- JS登録
- JS自動実行
- JS編集画面
- 実行タイミング設定
- エラーログ保存

## Phase 5: DOM Rule

- 要素選択
- 非表示
- 削除
- 強調
- テキスト置換
- style指定

## Phase 6: 自動化記録

- 記録開始 / 停止
- クリック記録
- 入力記録
- スクロール記録
- 遷移記録
- マクロ保存
- 手動再生

## Phase 7: 自動実行

- onPageLoad Trigger
- onUrlMatch Trigger
- onElementAppear Trigger
- waitForSelector
- リトライ処理

## Phase 8: 開発レポート

- 改修メモ作成
- CRUD
- フィルタ
- CSV export/import
- Codex用プロンプト生成

## Phase 9: Store連携準備

- パッチ署名
- パッチハッシュ検証
- パッチ import/export
- レシピ共有形式
- Awokela Store API 接続準備

---

## 19. 初期MVP範囲

最初に作るべき最小版は以下。

- Electron + React + TypeScript 起動
- URL入力でWebページ表示
- 現在URLに対するProfile作成
- CSS Patch登録・適用
- JS Patch登録・手動実行
- 自動化記録はクリック・入力のみ
- 記録したマクロを手動再生
- JSON保存
- 改修メモボタン

この範囲なら、巨大な理想論ではなく実際に動くブラウザになる。

---

## 20. 注意すべき技術課題

## 20.1 CSP

Webサイト側の Content Security Policy により、JS注入が制限される場合がある。
Electron の preload script や isolated world を使った設計が必要。

## 20.2 iframe

iframe 内部のDOM操作は同一オリジン制約を受ける。
クロスオリジン iframe への操作は制限される。

## 20.3 SPA

SPAではページ遷移が通常の reload ではないため、URL変化とDOM変化を監視する必要がある。

## 20.4 セレクタの脆さ

Webページ側のHTML構造変更により、記録済みマクロが壊れる。
複数selector候補、テキストヒント、XPath fallback を保存する。

## 20.5 ログイン・認証

ログイン状態、2FA、CAPTCHA が絡むページでは自動化が失敗しやすい。
CAPTCHA回避を目的とした機能は実装しない。

---

## 21. 実装方針

## 21.1 Electron 構成

- main process: ウィンドウ管理、ファイル保存、OS連携
- renderer process: UI、エディタ、設定画面
- preload script: Webページとの安全な橋渡し

## 21.2 推奨構成

```text
src/
  main/
    main.ts
    windowManager.ts
    storage.ts
  preload/
    preload.ts
    patchBridge.ts
    recorderBridge.ts
  renderer/
    App.tsx
    components/
    pages/
    stores/
    editors/
    automation/
    siteProfiles/
  shared/
    types/
    constants/
    validators/
```

---

## 22. 非目標

初期版では以下を対象外とする。

- 完全なChrome互換
- Chrome拡張機能の完全対応
- CAPTCHA突破
- 他人のWebサービスへの不正アクセス支援
- パスワード窃取や外部送信
- 大規模クラウド同期

---

## 23. 将来構想

- Awokela Store で CSS / JS / Automation レシピ配布
- ユーザー作成テーマ販売
- 企業内業務ブラウザ化
- AIによるCSS Patch自動生成
- AIによる操作マクロ修復
- Webページ差分検知
- 定期巡回
- ローカルLLM連携
- QRコードでPatch共有
- チーム共有Profile

---

## 24. まとめ

Chamaeleon Browser は、単なるブラウザではなく、Webページをユーザー側で再構成するための操作環境である。

中核は以下の4つである。

1. Site Profile
2. CSS / JS Patch
3. DOM Rule
4. Automation Recorder

この4つを安定させれば、Webページ改造・業務自動化・開発支援の土台になる。

逆にここを雑に作ると、ただの壊れやすい自動クリック玩具になる。
最初は小さく、しかしデータ構造だけは拡張前提で設計すること。
