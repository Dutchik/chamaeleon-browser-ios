import SwiftUI

/// デベロッパーモード風のスタイル編集: 要素を選んでCSSを書き、ライブプレビューし、
/// 現在サイトのプロファイルに CssPatch として登録する。
struct StyleEditorView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    @State private var selector = ""
    @State private var currentStyles: [String: String] = [:]
    @State private var css = ""
    @State private var picking = false
    @State private var patchName = "スタイル調整"

    // よく使うプロパティのクイック編集
    private let quickProps = ["color", "background-color", "font-size", "display", "border-radius", "padding"]

    var body: some View {
        NavigationStack {
            Form {
                Section("対象要素") {
                    HStack {
                        TextField("CSSセレクタ（🎯で選択）", text: $selector)
                            .font(.system(size: 13, design: .monospaced))
                            .autocapitalization(.none).autocorrectionDisabled()
                            .onChange(of: selector) { _ in rebuildCss() }
                        Button {
                            picking = true
                            model.onInspected = { info in
                                selector = info.selector
                                currentStyles = info.styles
                                picking = false
                                rebuildCss()
                            }
                            model.startInspect()
                        } label: { Image(systemName: "target").font(.system(size: 18)) }
                        .buttonStyle(.borderless)
                    }
                    if picking {
                        Text("ページ上の要素をタップして選択してください")
                            .font(.system(size: 12)).foregroundColor(.blue)
                    }
                }

                if !currentStyles.isEmpty {
                    Section("現在のスタイル") {
                        ForEach(quickProps, id: \.self) { p in
                            if let v = currentStyles[p] {
                                HStack {
                                    Text(p).font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                                    Spacer()
                                    Text(v).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                }
                            }
                        }
                    }
                }

                Section("CSS（このセレクタに適用）") {
                    TextEditor(text: $css)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 140)
                        .onChange(of: css) { _ in model.previewCss(css) }
                    HStack {
                        Button("プレビュー") { model.previewCss(css) }
                        Spacer()
                        Button("プレビュー解除") { model.clearPreview() }.foregroundColor(.secondary)
                    }.font(.system(size: 13))
                }

                Section("保存") {
                    TextField("パッチ名", text: $patchName)
                    Text("保存先: \(currentHost) のプロファイル")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Button {
                        savePatch()
                    } label: { Label("このサイトに登録", systemImage: "square.and.arrow.down") }
                        .disabled(css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selector.isEmpty)
                }
            }
            .navigationTitle("スタイル編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { model.clearPreview(); dismiss() }
                }
            }
        }
    }

    private var currentHost: String { URL(string: model.currentURL)?.host ?? model.currentURL }

    /// セレクタ変更時、CSSテンプレートの骨組みを作る
    private func rebuildCss() {
        let s = selector.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        if css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            css = "\(s) {\n  \n}"
        } else if !css.contains(s) {
            css = "\(s) {\n  \n}\n" + css
        }
        model.previewCss(css)
    }

    private func savePatch() {
        let host = currentHost
        let patch = CssPatch(name: patchName, enabled: true, code: css, runAt: .documentEnd)
        // 既存の同ドメインプロファイルに追記、無ければ新規
        if let idx = store.profiles.firstIndex(where: { $0.matchType == .domain && $0.matchPattern == host }) {
            store.profiles[idx].cssPatches.append(patch)
            store.profiles[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        } else {
            var p = SiteProfile()
            p.name = host
            p.matchType = .domain
            p.matchPattern = host
            p.cssPatches = [patch]
            store.profiles.insert(p, at: 0)
        }
        model.clearPreview()
        dismiss()
    }
}
