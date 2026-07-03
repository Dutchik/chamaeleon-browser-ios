import SwiftUI
import Photos

/// 著作権に関する警告文（ダウンロード前に必ず同意）
let CHM_DL_WARNING = """
著作権に関するコンテンツを個人の利用以外で利用することは、法令に抵触する可能性があります。
ダウンロードは私的利用の範囲にとどめ、権利者の許諾および各サイトの利用規約に従ってください。
本機能の利用によって生じた責任は利用者に帰属します。
"""

/// 指定サイト内のメディア/要素を収集してダウンロード（進捗つき）。
/// 画像・動画は写真ライブラリ、その他はファイル（Documents）に保存。
@MainActor
final class DownloadManager: ObservableObject {
    @Published var running = false
    @Published var total = 0
    @Published var done = 0
    @Published var failed = 0
    @Published var status = "待機中"
    @Published var lastFile = ""

    private var task: Task<Void, Never>?
    private let imageExt: Set<String> = ["jpg","jpeg","png","gif","webp","bmp","heic","tiff"]
    private let videoExt: Set<String> = ["mp4","mov","m4v","webm","avi","mkv"]
    private let otherExt: Set<String> = ["svg","ico","mp3","wav","m4a","ogg","flac","pdf","zip","txt","json","css","js"]
    private var mediaExt: Set<String> { imageExt.union(videoExt).union(["mp3","wav","m4a","ogg","flac","pdf"]) }

    var progress: Double { total > 0 ? Double(done + failed) / Double(total) : 0 }

    func cancel() { task?.cancel() }

    func start(pageURL: URL, seed: [String], depth: Int, mediaOnly: Bool) {
        guard !running else { return }
        task = Task { await run(pageURL: pageURL, seed: seed, depth: depth, mediaOnly: mediaOnly) }
    }

    private func run(pageURL: URL, seed: [String], depth: Int, mediaOnly: Bool) async {
        running = true; done = 0; failed = 0; total = 0; lastFile = ""; status = "解析中…"
        defer { running = false }
        _ = await requestPhotoAccess()
        let host = pageURL.host ?? ""
        var resources = Set<String>()
        for s in seed { if let u = URL(string: s, relativeTo: pageURL)?.absoluteURL { resources.insert(u.absoluteString) } }

        var visited = Set<String>([pageURL.absoluteString])
        var frontier: [(URL, Int)] = [(pageURL, 0)]
        while !frontier.isEmpty {
            if Task.isCancelled { status = "キャンセル"; return }
            let (u, d) = frontier.removeFirst()
            if d >= depth { continue }
            status = "サイト内を解析中(深さ\(d))…"
            guard let html = await fetchText(u) else { continue }
            let (res, links) = extract(html: html, base: u)
            res.forEach { resources.insert($0) }
            for l in links {
                guard let lu = URL(string: l), lu.host == host, !visited.contains(lu.absoluteString) else { continue }
                visited.insert(lu.absoluteString); frontier.append((lu, d + 1))
            }
        }

        var list = Array(resources).filter { $0.hasPrefix("http") }
        if mediaOnly { list = list.filter { mediaExt.contains((URL(string: $0)?.pathExtension ?? "").lowercased()) } }
        total = list.count
        if total == 0 { status = "対象がありませんでした"; return }
        status = "ダウンロード中 \(total) 件…"

        var idx = 0
        while idx < list.count {
            if Task.isCancelled { status = "キャンセル (\(done)件保存)"; return }
            let batch = Array(list[idx..<min(idx + 3, list.count)])
            await withTaskGroup(of: Bool.self) { group in
                for s in batch { group.addTask { await self.download(s, host: host) } }
                for await ok in group { if ok { self.done += 1 } else { self.failed += 1 } }
            }
            idx += 3
        }
        status = "完了: \(done)件保存 / \(failed)件失敗（写真＝画像・動画／ファイル＝その他）"
    }

    // MARK: - 保存

    private func download(_ urlStr: String, host: String) async -> Bool {
        guard let url = URL(string: urlStr),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
        let ext = url.pathExtension.lowercased()
        if imageExt.contains(ext) || videoExt.contains(ext) {
            return await saveToPhotos(data: data, isVideo: videoExt.contains(ext), url: url)
        } else {
            return saveToFiles(data: data, url: url, host: host)
        }
    }

    private func requestPhotoAccess() async -> Bool {
        await withCheckedContinuation { c in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in c.resume(returning: s == .authorized || s == .limited) }
        }
    }
    private func saveToPhotos(data: Data, isVideo: Bool, url: URL) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: isVideo ? .video : .photo, data: data, options: nil)
            }, completionHandler: { ok, _ in
                if ok { Task { @MainActor in self.lastFile = url.lastPathComponent } }
                c.resume(returning: ok)
            })
        }
    }
    private func saveToFiles(data: Data, url: URL, host: String) -> Bool {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChamaeleonDownloads", isDirectory: true)
            .appendingPathComponent(host.isEmpty ? "page" : host, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var name = url.lastPathComponent
        if name.isEmpty || !name.contains(".") { name = "\(abs(url.absoluteString.hashValue))" }
        var dest = dir.appendingPathComponent(name); var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)_\(i).\(url.pathExtension)"); i += 1
        }
        do { try data.write(to: dest); lastFile = dest.lastPathComponent; return true } catch { return false }
    }

    // MARK: - 収集

    private func fetchText(_ url: URL) async -> String? {
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              (http.mimeType?.contains("html") ?? true) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func extract(html: String, base: URL) -> (res: [String], links: [String]) {
        var res: [String] = [], links: [String] = []
        let re = try? NSRegularExpression(pattern: "(?:src|href|data-src)\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive])
        let ns = html as NSString
        re?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, let r = Range(m.range(at: 1), in: html) else { return }
            guard let u = URL(string: String(html[r]), relativeTo: base)?.absoluteURL else { return }
            let s = u.absoluteString; res.append(s)
            let e = u.pathExtension.lowercased()
            if e.isEmpty || ["html","htm","php","aspx"].contains(e) { links.append(s) }
        }
        return (res, links)
    }
}

/// ダウンロードUI（警告＋同意 → 階層/種別 → 進捗）
struct DownloaderView: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var model: BrowserModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chm_dl_consent") private var consented = false
    @State private var agree = false
    @State private var depth = 1
    @State private var mediaOnly = true

    private var host: String { URL(string: model.currentURL)?.host ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("著作権に関する注意", systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(CHM_DL_WARNING).font(.system(size: 12)).foregroundColor(.secondary)
                    if !consented {
                        Toggle("上記に同意します", isOn: $agree)
                        Button("同意して有効化") { consented = true }
                            .disabled(!agree)
                    }
                }
                if consented {
                    Section("対象（\(host)）") {
                        Text(model.currentURL).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
                        Stepper("サイト内クロール階層: \(depth)", value: $depth, in: 0...5)
                        Toggle("メディアのみ（画像・動画・音声・PDF）", isOn: $mediaOnly)
                        Text("画像・動画は「写真」に保存します（その他の種類はアプリ内に保存）。")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Section("進捗") {
                        ProgressView(value: manager.progress) { Text(manager.status).font(.system(size: 12)) }.tint(accent)
                        Text("保存 \(manager.done) / 失敗 \(manager.failed) / 全 \(manager.total)")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                        if !manager.lastFile.isEmpty {
                            Text(manager.lastFile).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    Section {
                        if manager.running {
                            Button("キャンセル", role: .destructive) { manager.cancel() }
                        } else {
                            Button("ダウンロード開始") { startDownload() }
                                .disabled(!model.currentURL.hasPrefix("http"))
                        }
                    }
                }
            }
            .navigationTitle("一括ダウンロード").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private func startDownload() {
        guard let url = URL(string: model.currentURL) else { return }
        Task {
            let seed = await model.collectResources()
            manager.start(pageURL: url, seed: seed, depth: depth, mediaOnly: mediaOnly)
        }
    }
}
