import Foundation

// デスクトップ版（desktop/src/shared/types.ts）と同じデータモデル。
// docs/DATA_MODEL.md と同期すること。

enum MatchType: String, Codable, CaseIterable, Identifiable {
    case exact, domain, path, wildcard, regex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .exact: return "完全一致"
        case .domain: return "ドメイン"
        case .path: return "パス"
        case .wildcard: return "ワイルドカード"
        case .regex: return "正規表現"
        }
    }
}

enum RunAt: String, Codable, CaseIterable, Identifiable {
    case documentStart = "document_start"
    case documentEnd = "document_end"
    case idle
    var id: String { rawValue }
}

struct CssPatch: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "CSS Patch"
    var enabled = true
    var code = ""
    var runAt: RunAt = .documentEnd
    var priority = 0
    var createdAt = ISO8601DateFormatter().string(from: Date())
    var updatedAt = ISO8601DateFormatter().string(from: Date())
}

struct JsPatch: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "JS Patch"
    var enabled = true
    var code = ""
    var runAt: RunAt = .documentEnd
    var priority = 0
    var sandbox = true
    var allowDomAccess = true
    var createdAt = ISO8601DateFormatter().string(from: Date())
    var updatedAt = ISO8601DateFormatter().string(from: Date())
}

enum DomAction: String, Codable, CaseIterable, Identifiable {
    case hide, remove, highlight, replaceText, addClass, setStyle, move, click, input
    var id: String { rawValue }
}

struct DomRule: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "Rule"
    var enabled = true
    var selector = ""
    var action: DomAction = .hide
    var value: String?
    var runAt: RunAt = .documentEnd
    var waitForSelector = true
    var timeoutMs = 10000
}

struct SiteNote: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title = "メモ"
    var body = ""
    var tags: [String] = []
    var createdAt = ISO8601DateFormatter().string(from: Date())
    var updatedAt = ISO8601DateFormatter().string(from: Date())
}

struct SiteProfile: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "New Profile"
    var enabled = true
    var matchType: MatchType = .domain
    var matchPattern = ""
    var description: String?
    var cssPatches: [CssPatch] = []
    var jsPatches: [JsPatch] = []
    var domRules: [DomRule] = []
    var notes: [SiteNote] = []
    var createdAt = ISO8601DateFormatter().string(from: Date())
    var updatedAt = ISO8601DateFormatter().string(from: Date())

    /// URLマッチ判定（desktop/src/shared/types.ts の matchesProfile と同一仕様）
    func matches(_ urlString: String) -> Bool {
        guard enabled else { return false }
        let p = matchPattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return false }
        switch matchType {
        case .exact:
            return urlString == p
        case .domain:
            guard let host = URL(string: urlString)?.host else { return false }
            return host == p || host.hasSuffix("." + p)
        case .path, .wildcard:
            let escaped = NSRegularExpression.escapedPattern(for: p).replacingOccurrences(of: "\\*", with: ".*")
            return urlString.range(of: "^" + escaped + "$", options: .regularExpression) != nil
        case .regex:
            return urlString.range(of: p, options: .regularExpression) != nil
        }
    }
}

/// JSONファイル（Documents/chamaeleon-profiles.json）に保存するストア
@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [SiteProfile] = [] {
        didSet { save(); version &+= 1 }
    }
    /// ルール変更検知用（Agent再ビルドのトリガ）
    @Published private(set) var version = 0

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chamaeleon-profiles.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SiteProfile].self, from: data) {
            profiles = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func matched(for url: String) -> [SiteProfile] {
        profiles.filter { $0.matches(url) }
    }
}


// MARK: - ブックマーク・履歴（仕様§4.1）

struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title = ""
    var url = ""
    var createdAt = ISO8601DateFormatter().string(from: Date())
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title = ""
    var url = ""
    var visitedAt = ISO8601DateFormatter().string(from: Date())
}

/// ブックマーク・履歴・設定のストア（Documents内のJSON）
@MainActor
final class LibraryStore: ObservableObject {
    @Published var bookmarks: [Bookmark] = [] { didSet { save(bookmarks, "chamaeleon-bookmarks.json") } }
    @Published var history: [HistoryEntry] = [] { didSet { save(Array(history.prefix(5000)), "chamaeleon-history.json") } }
    @Published var homepage: String {
        didSet { UserDefaults.standard.set(homepage, forKey: "homepage") }
    }

    private func fileURL(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    init() {
        homepage = UserDefaults.standard.string(forKey: "homepage") ?? "https://duckduckgo.com"
        if let d = try? Data(contentsOf: fileURL("chamaeleon-bookmarks.json")),
           let v = try? JSONDecoder().decode([Bookmark].self, from: d) { bookmarks = v }
        if let d = try? Data(contentsOf: fileURL("chamaeleon-history.json")),
           let v = try? JSONDecoder().decode([HistoryEntry].self, from: d) { history = v }
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: fileURL(name), options: .atomic)
        }
    }

    func isBookmarked(_ url: String) -> Bool { bookmarks.contains { $0.url == url } }

    func toggleBookmark(url: String, title: String) {
        if isBookmarked(url) { bookmarks.removeAll { $0.url == url } }
        else { bookmarks.insert(Bookmark(title: title.isEmpty ? url : title, url: url), at: 0) }
    }

    func recordVisit(url: String, title: String) {
        guard url.hasPrefix("http") else { return }
        history.insert(HistoryEntry(title: title, url: url), at: 0)
    }
}
