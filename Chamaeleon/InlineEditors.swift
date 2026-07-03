import SwiftUI

/// 右パネルに表示する編集の種類
enum InlineEditor: Equatable { case none, style, record }

/// スタイル編集の本体（右パネルの中身）。デベロッパーモード風＋CSS不要のかんたん編集。
/// 要素選択時はパネルを右へ畳んでページ全体を見せ、選択後に再展開する。
struct StyleEditorBody: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var model: BrowserModel
    let accent: Color
    @Binding var expanded: Bool
    let onClose: () -> Void

    @State private var selector = ""
    @State private var css = ""
    @State private var styles: [String: String] = [:]
    @State private var patchName = "スタイル調整"
    @State private var picking = false
    @State private var edits: [String: String] = [:]
    @State private var textColor: Color = .primary
    @State private var bgColor: Color = .white

    private let quickProps = ["color", "background-color", "font-size", "display", "border-radius", "padding"]
    private var host: String { URL(string: model.currentURL)?.host ?? model.currentURL }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if picking {
                    Text("ページ上の要素をタップして選択してください")
                        .font(.system(size: 12)).foregroundColor(accent)
                }

                // 要素選択
                HStack {
                    TextField("CSSセレクタ", text: $selector)
                        .font(.system(size: 13, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none).autocorrectionDisabled()
                        .onChange(of: selector) { _ in rebuild() }
                    Button(action: pick) {
                        Label("選択", systemImage: "target").font(.system(size: 13, weight: .semibold))
                    }.buttonStyle(.borderedProminent).tint(accent)
                }

                if !styles.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(quickProps, id: \.self) { p in
                            if let v = styles[p] {
                                HStack {
                                    Text(p).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                    Spacer()
                                    Text(v).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(8).background(Color.secondary.opacity(0.08)).cornerRadius(8)
                }

                // かんたん編集（CSS不要）
                Text("かんたん編集（CSS不要）").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                VStack(spacing: 8) {
                    ColorPicker("文字色", selection: $textColor, supportsOpacity: false)
                        .onChange(of: textColor) { c in setEdit("color", hex(c)) }
                    ColorPicker("背景色", selection: $bgColor, supportsOpacity: false)
                        .onChange(of: bgColor) { c in setEdit("background-color", hex(c)) }
                    HStack(spacing: 8) {
                        Text("文字").font(.system(size: 13))
                        Button { bumpFont(-2) } label: { Image(systemName: "textformat.size.smaller") }.buttonStyle(.bordered)
                        Button { bumpFont(2) } label: { Image(systemName: "textformat.size.larger") }.buttonStyle(.bordered)
                        Button { toggleBold() } label: { Image(systemName: "bold") }
                            .buttonStyle(.bordered).tint(edits["font-weight"] == "bold" ? accent : nil)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        Button(role: .destructive) { setEdit("display", "none") } label: {
                            Label("隠す", systemImage: "eye.slash")
                        }.buttonStyle(.bordered)
                        Button { removeEdit("display") } label: { Label("表示", systemImage: "eye") }.buttonStyle(.bordered)
                        Button { resetEdits() } label: { Text("リセット") }.buttonStyle(.bordered)
                        Spacer()
                    }.font(.system(size: 12))
                }
                .font(.system(size: 13))
                .disabled(selector.isEmpty)
                .opacity(selector.isEmpty ? 0.4 : 1)

                // CSS（詳しい方向け）
                Text("CSS（詳しい方向け・入力で即プレビュー）").font(.system(size: 12)).foregroundColor(.secondary)
                TextEditor(text: $css)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(height: 100)
                    .padding(6)
                    .background(Color.secondary.opacity(0.08)).cornerRadius(8)
                    .onChange(of: css) { _ in model.previewCss(css) }

                HStack {
                    Button("プレビュー") { model.previewCss(css) }.font(.system(size: 13))
                    Button("解除") { model.clearPreview() }.font(.system(size: 13)).foregroundColor(.secondary)
                    Spacer()
                }

                // 保存
                TextField("パッチ名", text: $patchName).textFieldStyle(.roundedBorder)
                Button(action: save) {
                    Label("このサイトに登録", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(accent)
                .disabled(css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selector.isEmpty)
            }
            .padding(14)
        }
    }

    private func pick() {
        picking = true
        withAnimation { expanded = false }   // ページを全面表示してタップできるように右へ畳む
        model.onInspected = { info in
            selector = info.selector
            styles = info.styles
            edits = [:]
            picking = false
            withAnimation { expanded = true }
            rebuild()
        }
        model.startInspect()
    }

    private func rebuild() {
        let s = selector.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        if css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { css = "\(s) {\n  \n}" }
        else if !css.contains(s) { css = "\(s) {\n  \n}\n" + css }
        model.previewCss(css)
    }

    // MARK: - かんたん編集ヘルパ
    private func setEdit(_ k: String, _ v: String) { edits[k] = v; regen() }
    private func removeEdit(_ k: String) { edits[k] = nil; regen() }
    private func resetEdits() { edits = [:]; regen() }
    private func toggleBold() {
        if edits["font-weight"] == "bold" { removeEdit("font-weight") } else { setEdit("font-weight", "bold") }
    }
    private func bumpFont(_ d: Int) {
        let raw = (edits["font-size"] ?? styles["font-size"] ?? "16")
            .replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces)
        let cur = Int(Double(raw) ?? 16)
        setEdit("font-size", "\(max(6, cur + d))px")
    }
    private func hex(_ c: Color) -> String {
        let u = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
    private func regen() {
        let s = selector.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        let decls = edits.keys.sorted().map { k -> String in
            let imp = (k == "display" || k == "font-weight") ? " !important" : ""
            return "  \(k): \(edits[k]!)\(imp);"
        }
        css = "\(s) {\n" + decls.joined(separator: "\n") + "\n}"
        model.previewCss(css)
    }

    private func save() {
        let patch = CssPatch(name: patchName, enabled: true, code: css, runAt: .documentEnd)
        if let idx = store.profiles.firstIndex(where: { $0.matchType == .domain && $0.matchPattern == host }) {
            store.profiles[idx].cssPatches.append(patch)
            store.profiles[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        } else {
            var p = SiteProfile()
            p.name = host; p.matchType = .domain; p.matchPattern = host; p.cssPatches = [patch]
            store.profiles.insert(p, at: 0)
        }
        model.clearPreview()
        onClose()
    }
}
