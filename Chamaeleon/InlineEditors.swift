import SwiftUI

/// 画面下部に重ねて表示する編集パネルの種類。
/// ページを見ながら（＝WebViewを隠さず）設定できるようにする。
enum InlineEditor: Equatable { case none, style, record }

// MARK: - 共通のパネル外枠

private struct PanelChrome<Body: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var collapsed: Bool
    let onClose: () -> Void
    @ViewBuilder var content: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            // グラバー＋ヘッダー
            VStack(spacing: 6) {
                Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 38, height: 5).padding(.top, 6)
                HStack(spacing: 10) {
                    Text(title).font(.system(size: 15, weight: .bold))
                    if let s = subtitle {
                        Text(s).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { collapsed.toggle() } label: {
                        Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20)).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if !collapsed {
                Divider()
                content()
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: -2)
        .padding(.horizontal, 8)
    }
}

// MARK: - スタイル編集パネル（デベロッパーモード風・ページを見ながら）

struct InlineStylePanel: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var model: BrowserModel
    let onClose: () -> Void

    @State private var selector = ""
    @State private var css = ""
    @State private var styles: [String: String] = [:]
    @State private var patchName = "スタイル調整"
    @State private var collapsed = false
    @State private var picking = false
    // かんたん編集（CSS不要）
    @State private var edits: [String: String] = [:]
    @State private var textColor: Color = .primary
    @State private var bgColor: Color = .white

    private let quickProps = ["color", "background-color", "font-size", "display", "border-radius", "padding"]
    private var host: String { URL(string: model.currentURL)?.host ?? model.currentURL }

    var body: some View {
        PanelChrome(title: "🎨 スタイル編集",
                    subtitle: picking ? "ページ上の要素をタップ" : (selector.isEmpty ? host : selector),
                    collapsed: $collapsed, onClose: { model.clearPreview(); onClose() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 要素選択
                    HStack {
                        TextField("CSSセレクタ", text: $selector)
                            .font(.system(size: 13, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none).autocorrectionDisabled()
                            .onChange(of: selector) { _ in rebuild() }
                        Button(action: pick) {
                            Label("選択", systemImage: "target").font(.system(size: 13, weight: .semibold))
                        }.buttonStyle(.borderedProminent).tint(.green)
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

                    // かんたん編集（CSSがわからなくてもボタンで）
                    Text("かんたん編集（CSS不要）").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                    VStack(spacing: 8) {
                        HStack(spacing: 14) {
                            ColorPicker("文字色", selection: $textColor, supportsOpacity: false)
                                .onChange(of: textColor) { c in setEdit("color", hex(c)) }
                            ColorPicker("背景色", selection: $bgColor, supportsOpacity: false)
                                .onChange(of: bgColor) { c in setEdit("background-color", hex(c)) }
                        }.font(.system(size: 13))
                        HStack(spacing: 8) {
                            Text("文字").font(.system(size: 13))
                            Button { bumpFont(-2) } label: { Image(systemName: "textformat.size.smaller") }.buttonStyle(.bordered)
                            Button { bumpFont(2) } label: { Image(systemName: "textformat.size.larger") }.buttonStyle(.bordered)
                            Button { toggleBold() } label: { Image(systemName: "bold") }
                                .buttonStyle(.bordered).tint(edits["font-weight"] == "bold" ? .green : nil)
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
                    .disabled(selector.isEmpty)
                    .opacity(selector.isEmpty ? 0.4 : 1)

                    // CSS 編集（詳細・入力で即プレビュー）
                    Text("CSS（詳しい方向け・入力で即プレビュー）").font(.system(size: 12)).foregroundColor(.secondary)
                    TextEditor(text: $css)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(height: 110)
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
                        Label("このサイト（\(host)）に登録", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selector.isEmpty)
                }
                .padding(16)
            }
            .frame(maxHeight: 340)
        }
    }

    private func pick() {
        picking = true
        collapsed = true   // ページを全面表示してタップできるように
        model.onInspected = { info in
            selector = info.selector
            styles = info.styles
            edits = [:]     // 新しい要素なので簡単編集をリセット
            picking = false
            collapsed = false
            rebuild()
        }
        model.startInspect()
    }

    private func rebuild() {
        let s = selector.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        if css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            css = "\(s) {\n  \n}"
        } else if !css.contains(s) {
            css = "\(s) {\n  \n}\n" + css
        }
        model.previewCss(css)
    }

    // MARK: - かんたん編集ヘルパ（editsからCSSを生成）

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
    /// editsから selector { ... } のCSSを生成してプレビュー
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

