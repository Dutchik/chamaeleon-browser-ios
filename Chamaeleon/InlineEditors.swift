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

                    // CSS 編集（入力で即プレビュー）
                    Text("CSS（入力すると即プレビュー）").font(.system(size: 12)).foregroundColor(.secondary)
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

// MARK: - 操作記録パネル（ページを操作しながら手順を記録）

struct InlineRecordPanel: View {
    @ObservedObject var model: BrowserModel
    let onClose: () -> Void
    let onSaveFlow: (Flow) -> Void

    @State private var steps: [RecordedStep] = []
    @State private var collapsed = false
    @State private var paused = false
    private var host: String { URL(string: model.currentURL)?.host ?? model.currentURL }

    var body: some View {
        PanelChrome(title: paused ? "⏸ 記録一時停止" : "⏺ 操作を記録中",
                    subtitle: "\(steps.count) 手順",
                    collapsed: $collapsed, onClose: stopAndClose) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ページを操作すると手順が記録されます。折りたたむとページ全体を見ながら操作できます。")
                    .font(.system(size: 12)).foregroundColor(.secondary).padding(.horizontal, 16).padding(.top, 10)

                if steps.isEmpty {
                    Text("まだ手順がありません。ページ上をタップ・入力してください。")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                                HStack(spacing: 8) {
                                    Text("\(i + 1)").font(.system(size: 11, weight: .bold))
                                        .frame(width: 22, height: 22)
                                        .background(Color.green.opacity(0.15)).clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(FlowActionType(rawValue: s.type)?.title ?? s.type)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(s.selector ?? "").font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if let v = s.value, !v.isEmpty {
                                        Text(v).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1).frame(maxWidth: 90)
                                    }
                                    Button { steps.remove(at: i) } label: {
                                        Image(systemName: "minus.circle").foregroundColor(.red)
                                    }.buttonStyle(.borderless)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                Divider().padding(.leading, 16)
                            }
                        }
                    }.frame(maxHeight: 200)
                }

                HStack(spacing: 10) {
                    Button {
                        paused.toggle()
                        if paused { model.stopRecording() } else { model.startRecording() }
                    } label: {
                        Label(paused ? "再開" : "一時停止", systemImage: paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }.buttonStyle(.bordered)

                    Button { steps.removeAll() } label: {
                        Label("クリア", systemImage: "trash").font(.system(size: 13))
                    }.buttonStyle(.bordered).disabled(steps.isEmpty)

                    Spacer()

                    Button(action: saveFlow) {
                        Label("フローとして保存", systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                    }.buttonStyle(.borderedProminent).tint(.green).disabled(steps.isEmpty)
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
        .onAppear {
            model.onRecorded = { rs in if !paused { steps.append(rs) } }
            model.startRecording()
        }
        .onDisappear { model.stopRecording(); model.onRecorded = nil }
    }

    private func stopAndClose() { model.stopRecording(); onClose() }

    private func saveFlow() {
        model.stopRecording()
        var f = Flow()
        f.name = host
        f.matchType = .domain
        f.matchPattern = host
        f.startUrl = model.currentURL
        f.steps = steps.map { rs in
            var s = FlowStep()
            s.type = FlowActionType(rawValue: rs.type) ?? .click
            s.selector = rs.selector
            s.value = rs.value
            return s
        }
        onSaveFlow(f)
    }
}
