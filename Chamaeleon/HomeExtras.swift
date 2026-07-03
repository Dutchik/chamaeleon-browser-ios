import SwiftUI

// MARK: - Hex → Color

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xff) / 255; g = Double((v >> 16) & 0xff) / 255
            b = Double((v >> 8) & 0xff) / 255;  a = Double(v & 0xff) / 255
        } else {
            r = Double((v >> 16) & 0xff) / 255; g = Double((v >> 8) & 0xff) / 255
            b = Double(v & 0xff) / 255;         a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - 分割ビュー（複数サイトを同時に開く）

enum SplitLayout: String, Codable, CaseIterable, Identifiable {
    case columns2, rows2, triptych, grid4
    var id: String { rawValue }
    var title: String {
        switch self {
        case .columns2: return "左右2分割"
        case .rows2: return "上下2分割"
        case .triptych: return "3分割"
        case .grid4: return "4分割"
        }
    }
    var paneCount: Int {
        switch self {
        case .columns2, .rows2: return 2
        case .triptych: return 3
        case .grid4: return 4
        }
    }
    var systemImage: String {
        switch self {
        case .columns2: return "rectangle.split.2x1"
        case .rows2: return "rectangle.split.1x2"
        case .triptych: return "rectangle.split.3x1"
        case .grid4: return "rectangle.split.2x2"
        }
    }
}

struct SplitConfig: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "分割ビュー"
    var layout: SplitLayout = .columns2
    var urls: [String] = ["", ""]
    var pinnedToHome = true

    init() {}

    enum CodingKeys: String, CodingKey { case id, name, layout, urls, pinnedToHome }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "分割ビュー"
        layout = try c.decodeIfPresent(SplitLayout.self, forKey: .layout) ?? .columns2
        urls = try c.decodeIfPresent([String].self, forKey: .urls) ?? ["", ""]
        pinnedToHome = try c.decodeIfPresent(Bool.self, forKey: .pinnedToHome) ?? true
    }

    /// レイアウトのペイン数に URL 配列を合わせる
    mutating func normalize() {
        let n = layout.paneCount
        if urls.count < n { urls.append(contentsOf: Array(repeating: "", count: n - urls.count)) }
        if urls.count > n { urls = Array(urls.prefix(n)) }
    }
}

@MainActor
final class SplitStore: ObservableObject {
    @Published var configs: [SplitConfig] = [] { didSet { save() } }
    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chamaeleon-splits.json")
    }
    init() {
        if let d = try? Data(contentsOf: url), let v = try? JSONDecoder().decode([SplitConfig].self, from: d) { configs = v }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(configs) { try? d.write(to: url, options: .atomic) }
    }
}
