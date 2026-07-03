import Foundation
import Security

// PC版 src/shared/types.ts に対応する自動化フロー・検索エンジンのモデル。

struct SearchEngine: Identifiable, Hashable {
    let id: String
    let name: String
    let searchUrl: String  // %s が検索語に置換
    let homeUrl: String
}

let DEFAULT_ENGINES: [SearchEngine] = [
    .init(id: "google", name: "Google", searchUrl: "https://www.google.com/search?q=%s", homeUrl: "https://www.google.com"),
    .init(id: "bing", name: "Bing", searchUrl: "https://www.bing.com/search?q=%s", homeUrl: "https://www.bing.com"),
    .init(id: "duckduckgo", name: "DuckDuckGo", searchUrl: "https://duckduckgo.com/?q=%s", homeUrl: "https://duckduckgo.com"),
    .init(id: "brave", name: "Brave Search", searchUrl: "https://search.brave.com/search?q=%s", homeUrl: "https://search.brave.com"),
    .init(id: "yahoo-jp", name: "Yahoo! JAPAN", searchUrl: "https://search.yahoo.co.jp/search?p=%s", homeUrl: "https://www.yahoo.co.jp"),
]

enum FlowActionType: String, Codable, CaseIterable, Identifiable {
    case navigate, click, input, check, uncheck, select, submit
    case wait, waitForSelector, runJavaScript, fillUsername, fillPassword
    var id: String { rawValue }
    var title: String {
        switch self {
        case .navigate: return "ページ移動"
        case .click: return "クリック"
        case .input: return "テキスト入力"
        case .check: return "チェックを入れる"
        case .uncheck: return "チェックを外す"
        case .select: return "選択（プルダウン）"
        case .submit: return "フォーム送信"
        case .wait: return "待機（ミリ秒）"
        case .waitForSelector: return "要素の出現を待つ"
        case .runJavaScript: return "JavaScript実行"
        case .fillUsername: return "ユーザー名を入力"
        case .fillPassword: return "パスワードを入力"
        }
    }
    var needsSelector: Bool {
        [.click, .input, .check, .uncheck, .select, .submit, .waitForSelector, .fillUsername, .fillPassword].contains(self)
    }
    var needsValue: Bool { [.input, .select, .wait, .runJavaScript].contains(self) }
}

struct FlowStep: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var type: FlowActionType = .click
    var selector: String?
    var value: String?          // 既定値。promptAtRun時は実行フォームの初期値
    var url: String?
    var delayMs: Int = 300
    var timeoutMs: Int = 12000
    var promptAtRun = false      // 実行時に値の入力を求める
    var promptLabel: String?     // 実行フォームでの見出し（例:「出勤時刻」）
    var secureInput = false      // 実行フォームで伏せ字入力

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, type, selector, value, url, delayMs, timeoutMs, promptAtRun, promptLabel, secureInput
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try c.decodeIfPresent(FlowActionType.self, forKey: .type) ?? .click
        selector = try c.decodeIfPresent(String.self, forKey: .selector)
        value = try c.decodeIfPresent(String.self, forKey: .value)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        delayMs = try c.decodeIfPresent(Int.self, forKey: .delayMs) ?? 300
        timeoutMs = try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 12000
        promptAtRun = try c.decodeIfPresent(Bool.self, forKey: .promptAtRun) ?? false
        promptLabel = try c.decodeIfPresent(String.self, forKey: .promptLabel)
        secureInput = try c.decodeIfPresent(Bool.self, forKey: .secureInput) ?? false
    }
}

struct Flow: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = ""
    var note = ""
    var enabled = true
    var matchType: MatchType = .domain
    var matchPattern = ""
    var startUrl = ""
    var useCredentials = false
    var credentialId: String?
    var pinnedToHome = false
    var steps: [FlowStep] = []
    var createdAt = ISO8601DateFormatter().string(from: Date())
    var updatedAt = ISO8601DateFormatter().string(from: Date())

    /// 実行時に入力を求めるステップ
    var promptSteps: [FlowStep] { steps.filter { $0.promptAtRun } }

    func matches(_ url: String) -> Bool {
        var p = SiteProfile()
        p.enabled = enabled; p.matchType = matchType; p.matchPattern = matchPattern
        return p.matches(url)
    }

    init() {}

    // 旧バージョンで保存したフロー（note等が無い）も読めるよう寛容にデコード
    enum CodingKeys: String, CodingKey {
        case id, name, note, enabled, matchType, matchPattern, startUrl
        case useCredentials, credentialId, pinnedToHome, steps, createdAt, updatedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        matchType = try c.decodeIfPresent(MatchType.self, forKey: .matchType) ?? .domain
        matchPattern = try c.decodeIfPresent(String.self, forKey: .matchPattern) ?? ""
        startUrl = try c.decodeIfPresent(String.self, forKey: .startUrl) ?? ""
        useCredentials = try c.decodeIfPresent(Bool.self, forKey: .useCredentials) ?? false
        credentialId = try c.decodeIfPresent(String.self, forKey: .credentialId)
        pinnedToHome = try c.decodeIfPresent(Bool.self, forKey: .pinnedToHome) ?? false
        steps = try c.decodeIfPresent([FlowStep].self, forKey: .steps) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ISO8601DateFormatter().string(from: Date())
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ISO8601DateFormatter().string(from: Date())
    }
}

/// フローの保存（Documents/chamaeleon-flows.json）
@MainActor
final class FlowStore: ObservableObject {
    @Published var flows: [Flow] = [] { didSet { save() } }
    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chamaeleon-flows.json")
    }
    init() {
        if let d = try? Data(contentsOf: url), let v = try? JSONDecoder().decode([Flow].self, from: d) { flows = v }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(flows) { try? d.write(to: url, options: .atomic) }
    }
    func matched(for url: String) -> [Flow] { flows.filter { $0.matches(url) } }
}

// MARK: - 認証情報（Keychainで端末内保存・仕様§14）

struct Credential: Identifiable, Equatable {
    var id: String
    var domain: String
    var username: String
}

/// ユーザー名はメタ情報(UserDefaults)、パスワードはKeychainに保存。
@MainActor
final class CredentialStore: ObservableObject {
    @Published var items: [Credential] = []
    private let metaKey = "chm_cred_meta_v1"

    init() { reload() }

    private func reload() {
        let raw = UserDefaults.standard.array(forKey: metaKey) as? [[String: String]] ?? []
        items = raw.compactMap { d in
            guard let id = d["id"], let dom = d["domain"], let user = d["username"] else { return nil }
            return Credential(id: id, domain: dom, username: user)
        }
    }
    private func saveMeta() {
        let raw = items.map { ["id": $0.id, "domain": $0.domain, "username": $0.username] }
        UserDefaults.standard.set(raw, forKey: metaKey)
    }

    func save(domain: String, username: String, password: String) {
        // 既存(domain+username)は更新
        let id = items.first(where: { $0.domain == domain && $0.username == username })?.id ?? UUID().uuidString
        keychainSet(id: id, password: password)
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = Credential(id: id, domain: domain, username: username)
        } else {
            items.insert(Credential(id: id, domain: domain, username: username), at: 0)
        }
        saveMeta()
    }
    func delete(_ id: String) {
        keychainDelete(id: id)
        items.removeAll { $0.id == id }
        saveMeta()
    }
    func reveal(_ id: String) -> (username: String, password: String)? {
        guard let c = items.first(where: { $0.id == id }), let pw = keychainGet(id: id) else { return nil }
        return (c.username, pw)
    }

    // --- Keychain helpers ---
    private func keychainSet(id: String, password: String) {
        keychainDelete(id: id)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.awokela.chamaeleon.creds",
            kSecAttrAccount as String: id,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }
    private func keychainGet(id: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.awokela.chamaeleon.creds",
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func keychainDelete(id: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.awokela.chamaeleon.creds",
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

/// アプリ設定（検索エンジン＋ホーム/ヘッダーの見た目カスタマイズ）
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var engineId: String { didSet { d.set(engineId, forKey: "chm_engine") } }
    // 見た目（選択式で編集）
    @Published var accentId: String { didSet { d.set(accentId, forKey: "chm_accent") } }
    @Published var bgId: String { didSet { d.set(bgId, forKey: "chm_bg") } }
    @Published var greeting: String { didSet { d.set(greeting, forKey: "chm_greeting") } }
    // ウィジェット
    @Published var showEngineBar: Bool { didSet { d.set(showEngineBar, forKey: "chm_w_engine") } }
    @Published var showClock: Bool { didSet { d.set(showClock, forKey: "chm_w_clock") } }
    @Published var showMemo: Bool { didSet { d.set(showMemo, forKey: "chm_w_memo") } }
    @Published var memo: String { didSet { d.set(memo, forKey: "chm_memo") } }
    // ヘッダー
    @Published var showBookmarkButton: Bool { didSet { d.set(showBookmarkButton, forKey: "chm_h_bm") } }
    @Published var showChameleonBadge: Bool { didSet { d.set(showChameleonBadge, forKey: "chm_h_badge") } }

    private let d = UserDefaults.standard

    init() {
        engineId = d.string(forKey: "chm_engine") ?? "google"
        accentId = d.string(forKey: "chm_accent") ?? "green"
        bgId = d.string(forKey: "chm_bg") ?? "forest"
        greeting = d.string(forKey: "chm_greeting") ?? "🦎 Chamaeleon"
        showEngineBar = d.object(forKey: "chm_w_engine") as? Bool ?? true
        showClock = d.object(forKey: "chm_w_clock") as? Bool ?? false
        showMemo = d.object(forKey: "chm_w_memo") as? Bool ?? false
        memo = d.string(forKey: "chm_memo") ?? ""
        showBookmarkButton = d.object(forKey: "chm_h_bm") as? Bool ?? true
        showChameleonBadge = d.object(forKey: "chm_h_badge") as? Bool ?? true
    }

    var engine: SearchEngine { DEFAULT_ENGINES.first { $0.id == engineId } ?? DEFAULT_ENGINES[0] }
}

// MARK: - 見た目プリセット（選択式編集）

struct AccentOption: Identifiable { let id: String; let name: String; let hex: String }
let ACCENT_OPTIONS: [AccentOption] = [
    .init(id: "green", name: "グリーン", hex: "#22C55E"),
    .init(id: "teal", name: "ティール", hex: "#14B8A6"),
    .init(id: "blue", name: "ブルー", hex: "#3B82F6"),
    .init(id: "purple", name: "パープル", hex: "#8B5CF6"),
    .init(id: "orange", name: "オレンジ", hex: "#F97316"),
    .init(id: "pink", name: "ピンク", hex: "#EC4899"),
]

struct BgOption: Identifiable { let id: String; let name: String; let topHex: String; let bottomHex: String }
let BG_OPTIONS: [BgOption] = [
    .init(id: "forest", name: "フォレスト", topHex: "#0F1712", bottomHex: "#000000"),
    .init(id: "midnight", name: "ミッドナイト", topHex: "#0B1220", bottomHex: "#000000"),
    .init(id: "slate", name: "スレート", topHex: "#1E293B", bottomHex: "#0A0F1A"),
    .init(id: "plum", name: "プラム", topHex: "#1E1233", bottomHex: "#000000"),
]

extension AppSettingsStore {
    var accentHex: String { ACCENT_OPTIONS.first { $0.id == accentId }?.hex ?? "#22C55E" }
    var bg: BgOption { BG_OPTIONS.first { $0.id == bgId } ?? BG_OPTIONS[0] }
}
