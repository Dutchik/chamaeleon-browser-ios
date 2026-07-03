import SwiftUI

/// Site Panel（🦎アイコン）: このページに紐付く「設定（プロファイル）」と「自動化フロー」を
/// 一覧し、適用ON/OFF・実行・編集・削除ができるハブ。
struct SitePanelView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var model: BrowserModel
    @ObservedObject var flowStore: FlowStore
    @ObservedObject var credStore: CredentialStore
    var onRunFlow: (Flow) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editingFlow: Flow?

    private var host: String { URL(string: model.currentURL)?.host ?? model.currentURL }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(model.currentURL)
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .lineLimit(2)
                } header: { Text("現在のページ") }

                // MARK: 自動化フロー
                Section {
                    ForEach($flowStore.flows) { $flow in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(flow.matches(model.currentURL) ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                            Toggle("", isOn: $flow.enabled).labelsHidden()
                            Button { editingFlow = flow } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(flow.name.isEmpty ? "(無題)" : flow.name)
                                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                                    Text("\(flow.steps.count)手順 · \(flow.matchType.title): \(flow.matchPattern)")
                                        .font(.system(size: 11)).foregroundColor(.secondary)
                                    if !flow.note.isEmpty {
                                        Text(flow.note).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                                    }
                                }
                            }.buttonStyle(.plain)
                            Spacer(minLength: 4)
                            Button { onRunFlow(flow) } label: {
                                Image(systemName: "play.circle.fill").font(.system(size: 24))
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(flow.enabled ? .green : .gray)
                            .disabled(!flow.enabled)
                        }
                    }
                    .onDelete { flowStore.flows.remove(atOffsets: $0) }

                    Button {
                        var f = Flow()
                        f.name = host; f.matchPattern = host
                        f.startUrl = model.currentURL.hasPrefix("http") ? model.currentURL : ""
                        editingFlow = f
                    } label: {
                        Label("このサイト用にフロー作成", systemImage: "plus.circle.fill")
                    }
                } header: { Text("自動化フロー") }
                footer: { Text("● は現在のページで実行できます。▶ で実行、トグルで有効/無効、行タップで手順の確認・編集・削除。") }

                // MARK: 設定（プロファイル）
                Section {
                    ForEach($store.profiles) { $profile in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(profile.matches(model.currentURL) ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                            Toggle("", isOn: $profile.enabled).labelsHidden()
                            NavigationLink {
                                ProfileDetailView(store: store, model: model, profileId: profile.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name).font(.system(size: 15, weight: .semibold))
                                    Text("CSS \(profile.cssPatches.count) · DOM \(profile.domRules.count) · JS \(profile.jsPatches.count) · \(profile.matchPattern)")
                                        .font(.system(size: 11)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { store.profiles.remove(atOffsets: $0) }

                    Button {
                        var p = SiteProfile()
                        p.name = host; p.matchPattern = host
                        store.profiles.append(p)
                    } label: {
                        Label("このサイト用にプロファイル作成", systemImage: "plus.circle.fill")
                    }
                } header: { Text("設定（CSS/DOM/JS）") }
                footer: { Text("● が現在のページに適用中。トグルで適用ON/OFF。行タップでパッチ・ルール・メモを編集。") }
            }
            .navigationTitle("🦎 このページの設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .sheet(item: $editingFlow) { f in
                FlowWizardView(flowStore: flowStore, credStore: credStore, model: model, editing: f)
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
