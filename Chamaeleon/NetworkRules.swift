import SwiftUI
import WebKit
import Network

enum NetAction: String, Codable, CaseIterable, Identifiable {
    case block          // ネットワークリクエストをブロック（広告等）
    case hide           // 要素を非表示（css-display-none、描画前に適用）
    var id: String { rawValue }
    var title: String { self == .block ? "ブロック" : "要素を隠す" }
}

struct NetRule: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var enabled = true
    var pattern = ""
    var selector: String?
    var domain: String?
    var action: NetAction = .block
    var note = ""

    init() {}
    init(enabled: Bool = true, pattern: String = "", selector: String? = nil,
         domain: String? = nil, action: NetAction = .block, note: String = "") {
        self.enabled = enabled; self.pattern = pattern; self.selector = selector
        self.domain = domain; self.action = action; self.note = note
    }

    // 旧データ寛容デコード
    enum CodingKeys: String, CodingKey { case id, enabled, pattern, selector, domain, action, note }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        selector = try c.decodeIfPresent(String.self, forKey: .selector)
        domain = try c.decodeIfPresent(String.self, forKey: .domain)
        action = try c.decodeIfPresent(NetAction.self, forKey: .action) ?? .block
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// 広告ブロック等のネットワークルール。
/// block: メインフレームは C エンジン(chm_rules)、サブリソースは WKContentRuleList。
/// hide: WKContentRuleList(css-display-none) で描画前に要素を消す。
@MainActor
final class NetRuleStore: ObservableObject {
    @Published var masterEnabled: Bool { didSet { d.set(masterEnabled, forKey: "chm_block_on"); refresh() } }
    @Published var rules: [NetRule] { didSet { persist(); refresh() } }
    @Published private(set) var compiledList: WKContentRuleList?
    @Published private(set) var version = 0
    /// パケット層キャプチャ（自前Cプロキシ経由、iOS17+）。iOSはOpenSSL非搭載のため平文HTTPのみ。
    @Published var captureEnabled: Bool { didSet { d.set(captureEnabled, forKey: "chm_capture_on"); applyProxyCapture() } }
    /// 取り込みセッション（同一動画のセグメントを1ファイルに結合）
    @Published private(set) var sessionActive = false

    private let d = UserDefaults.standard
    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chamaeleon-netrules.json")
    }

    var captureDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChamaeleonDownloads/capture", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    /// 取り込みセッションの保存先（Documents/ChamaeleonDownloads/session）
    var sessionDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChamaeleonDownloads/session", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    func startCaptureSession() {
        if !captureEnabled { captureEnabled = true }
        chm_proxy_session_start(sessionDir.path)
        sessionActive = true
    }
    func stopCaptureSession() {
        chm_proxy_session_stop()
        sessionActive = false
    }

    /// 自前Cプロキシを起動し WKWebView を経由させ、メディアをキャプチャ（iOS17+）
    func applyProxyCapture() {
        if #available(iOS 17.0, *) {
            if captureEnabled {
                let port = chm_proxy_start(0)
                if port > 0, let p = NWEndpoint.Port(rawValue: UInt16(port)) {
                    chm_proxy_set_capture(captureDir.path, 1)
                    WKWebsiteDataStore.default().proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: p))]
                } else { captureEnabled = false }
            } else {
                chm_proxy_set_capture(nil, 0)
                WKWebsiteDataStore.default().proxyConfigurations = []
                chm_proxy_stop()
            }
        }
    }

    init() {
        masterEnabled = d.object(forKey: "chm_block_on") as? Bool ?? true
        captureEnabled = d.object(forKey: "chm_capture_on") as? Bool ?? false
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chamaeleon-netrules.json")
        if let data = try? Data(contentsOf: u), let v = try? JSONDecoder().decode([NetRule].self, from: data) {
            rules = v
        } else {
            rules = NetRuleStore.defaults()
        }
        refresh()
        applyProxyCapture()
    }

    static func defaults() -> [NetRule] {
        ["doubleclick.net", "googlesyndication.com", "google-analytics.com", "googletagmanager.com",
         "googletagservices.com", "adservice.google", "adnxs.com", "amazon-adsystem.com", "/pagead/", "/ads/"]
            .map { NetRule(enabled: true, pattern: $0, action: .block, note: "既定の広告ブロック") }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) { try? data.write(to: url, options: .atomic) }
    }

    func refresh() {
        chm_rules_clear()
        if masterEnabled {
            for r in rules where r.enabled && r.action == .block { chm_rules_add(r.pattern, 1) }
        }
        compile()
    }

    private func compile() {
        let json = masterEnabled ? buildJSON() : "[]"
        guard json != "[]" else { compiledList = nil; version += 1; return }
        WKContentRuleListStore.default()?.compileContentRuleList(forIdentifier: "chm-block",
                                                                 encodedContentRuleList: json) { [weak self] list, _ in
            Task { @MainActor in
                guard let self else { return }
                self.compiledList = list
                self.version += 1
            }
        }
    }

    private func buildJSON() -> String {
        var arr: [[String: Any]] = []
        for r in rules where r.enabled {
            switch r.action {
            case .block:
                let f = regexEscape(r.pattern); guard !f.isEmpty else { continue }
                arr.append(["trigger": ["url-filter": f], "action": ["type": "block"]])
            case .hide:
                guard let sel = r.selector, !sel.isEmpty else { continue }
                var trig: [String: Any] = ["url-filter": ".*"]
                if let dom = r.domain, !dom.isEmpty { trig["if-domain"] = ["*\(dom)"] }
                arr.append(["trigger": trig, "action": ["type": "css-display-none", "selector": sel]])
            }
        }
        guard !arr.isEmpty, let data = try? JSONSerialization.data(withJSONObject: arr),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private func regexEscape(_ s: String) -> String {
        let specials = CharacterSet(charactersIn: "\\^$.|?*+()[]{}")
        var out = ""
        for ch in s.unicodeScalars {
            if specials.contains(ch) { out.append("\\") }
            out.append(Character(ch))
        }
        return out
    }

    func addBlock(_ pattern: String) {
        let p = pattern.trimmingCharacters(in: .whitespaces); guard !p.isEmpty else { return }
        rules.append(NetRule(enabled: true, pattern: p, action: .block))
    }
    func addHide(selector: String, domain: String?) {
        let s = selector.trimmingCharacters(in: .whitespaces); guard !s.isEmpty else { return }
        rules.append(NetRule(enabled: true, selector: s, domain: domain, action: .hide))
    }
    /// 「移動したくない宛先」を入力 → その宛先へのリンク要素を一括で隠し、ナビゲーションもブロック
    func addLinkTargetBlock(_ raw: String, domain: String? = nil) {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: "://") { t = String(t[r.upperBound...]) }   // scheme除去
        t = t.replacingOccurrences(of: "\"", with: "")
        guard !t.isEmpty else { return }
        rules.append(contentsOf: [
            NetRule(enabled: true, selector: "[href*=\"\(t)\"]", domain: domain, action: .hide, note: "リンク先ブロック"),
            NetRule(enabled: true, pattern: t, action: .block, note: "リンク先ブロック"),
        ])
    }
}
