import SwiftUI

/// Site Panel: 現在ページのプロファイルと CSS/JS/DOMルール/メモ を編集する
struct SitePanelView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(model.currentURL)
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .lineLimit(2)
                } header: { Text("現在のURL") }

                Section {
                    ForEach(store.profiles) { profile in
                        NavigationLink {
                            ProfileDetailView(store: store, model: model, profileId: profile.id)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(profile.matches(model.currentURL) ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name).font(.system(size: 15, weight: .semibold))
                                    Text("\(profile.matchType.title): \(profile.matchPattern)")
                                        .font(.system(size: 11)).foregroundColor(.secondary)
                                }
                                Spacer()
                                if !profile.enabled {
                                    Text("無効").font(.system(size: 11)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { store.profiles.remove(atOffsets: $0) }

                    Button {
                        var p = SiteProfile()
                        if let host = URL(string: model.currentURL)?.host {
                            p.name = host
                            p.matchPattern = host
                        }
                        store.profiles.append(p)
                    } label: {
                        Label("このサイト用にプロファイル作成", systemImage: "plus.circle.fill")
                    }
                } header: { Text("Site Profiles") }
                footer: { Text("● が現在のページに適用中。CSS/JSパッチとDOMルールはページ読み込み時に自動適用されます。") }
            }
            .navigationTitle("Site Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
    }
}

/// プロファイル詳細（マッチ設定・パッチ・ルール・メモ）
struct ProfileDetailView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var model: BrowserModel
    let profileId: String

    private var index: Int? { store.profiles.firstIndex { $0.id == profileId } }

    var body: some View {
        if let i = index {
            let binding = $store.profiles[i]
            List {
                Section("設定") {
                    TextField("名前", text: binding.name)
                    Toggle("有効", isOn: binding.enabled)
                    Picker("マッチ方式", selection: binding.matchType) {
                        ForEach(MatchType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("パターン（例: example.com）", text: binding.matchPattern)
                        .autocapitalization(.none).autocorrectionDisabled()
                }

                Section("CSS Patch") {
                    ForEach(binding.cssPatches) { $patch in
                        NavigationLink($patch.wrappedValue.name) {
                            PatchEditor(name: $patch.name, code: $patch.code,
                                        enabled: $patch.enabled, language: "CSS")
                        }
                    }
                    .onDelete { store.profiles[i].cssPatches.remove(atOffsets: $0) }
                    Button { store.profiles[i].cssPatches.append(CssPatch()) } label: {
                        Label("CSS Patch を追加", systemImage: "plus")
                    }
                }

                Section("JS Patch") {
                    ForEach(binding.jsPatches) { $patch in
                        NavigationLink {
                            PatchEditor(name: $patch.name, code: $patch.code,
                                        enabled: $patch.enabled, language: "JavaScript") {
                                model.webView?.evaluateJavaScript($patch.wrappedValue.code, completionHandler: nil)
                            }
                        } label: { Text($patch.wrappedValue.name) }
                    }
                    .onDelete { store.profiles[i].jsPatches.remove(atOffsets: $0) }
                    Button { store.profiles[i].jsPatches.append(JsPatch()) } label: {
                        Label("JS Patch を追加", systemImage: "plus")
                    }
                }

                Section("DOM Rule") {
                    ForEach(binding.domRules) { $rule in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Toggle("", isOn: $rule.enabled).labelsHidden()
                                Picker("", selection: $rule.action) {
                                    ForEach(DomAction.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .labelsHidden()
                                Spacer()
                                Button {
                                    model.webView?.evaluateJavaScript(PatchEngine.js(for: $rule.wrappedValue), completionHandler: nil)
                                } label: { Image(systemName: "play.fill") }
                                .buttonStyle(.borderless)
                            }
                            TextField("CSSセレクタ", text: $rule.selector)
                                .font(.system(size: 13, design: .monospaced))
                                .autocapitalization(.none).autocorrectionDisabled()
                            if [.replaceText, .addClass, .setStyle, .move, .input].contains($rule.wrappedValue.action) {
                                TextField("値", text: Binding(
                                    get: { $rule.wrappedValue.value ?? "" },
                                    set: { store.profiles[i].domRules[
                                        store.profiles[i].domRules.firstIndex(of: $rule.wrappedValue)!].value = $0 }))
                                    .font(.system(size: 13, design: .monospaced))
                            }
                        }
                    }
                    .onDelete { store.profiles[i].domRules.remove(atOffsets: $0) }
                    Button { store.profiles[i].domRules.append(DomRule()) } label: {
                        Label("DOM Rule を追加", systemImage: "plus")
                    }
                }

                Section("メモ") {
                    ForEach(binding.notes) { $note in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("タイトル", text: $note.title).font(.system(size: 14, weight: .semibold))
                            TextField("本文", text: $note.body, axis: .vertical).lineLimit(2...6)
                                .font(.system(size: 13))
                        }
                    }
                    .onDelete { store.profiles[i].notes.remove(atOffsets: $0) }
                    Button { store.profiles[i].notes.append(SiteNote()) } label: {
                        Label("メモを追加", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(store.profiles[i].name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("プロファイルが見つかりません")
        }
    }
}

/// CSS/JS コードエディタ
struct PatchEditor: View {
    @Binding var name: String
    @Binding var code: String
    @Binding var enabled: Bool
    let language: String
    var onRun: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    TextField("パッチ名", text: $name)
                    Toggle("有効", isOn: $enabled)
                    if let onRun {
                        Button { onRun() } label: { Label("今すぐ実行", systemImage: "play.fill") }
                    }
                }
                Section("\(language) コード") {
                    TextEditor(text: $code)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 280)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
