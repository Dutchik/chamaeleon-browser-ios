import SwiftUI

// MARK: - フロー実行エンジン（ページ遷移をまたいで順に実行）

@MainActor
enum FlowRunner {
    /// inputs: 実行時フォームで入力された値（stepId → 値）で該当ステップの値を上書き
    static func run(_ flow: Flow, model: BrowserModel, creds: CredentialStore,
                    inputs: [String: String] = [:],
                    status: @escaping (String) -> Void) async {
        status("▶ \(flow.name) を実行中…")
        model.flowRunning = true                          // JSダイアログを自動応答して停止を防ぐ
        defer { model.flowRunning = false }
        var cred: (username: String, password: String)?
        if flow.useCredentials, let cid = flow.credentialId { cred = creds.reveal(cid) }
        let baseDelay = UInt64(max(0, flow.stepDelayMs)) * 1_000_000

        if !flow.startUrl.isEmpty, flow.startUrl != model.currentURL {
            await model.navigateAndWait(model.normalize(flow.startUrl))
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        for step in flow.steps {
            if step.type == .navigate, let u = step.url, !u.isEmpty {
                await model.navigateAndWait(model.normalize(u))
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }
            // 遅延実行: フロー全体の待機 + そのステップ固有の待機（ポップアップ描画待ち等）
            if baseDelay > 0 { try? await Task.sleep(nanoseconds: baseDelay) }
            if step.delayMs > 0 { try? await Task.sleep(nanoseconds: UInt64(step.delayMs) * 1_000_000) }
            var type = step.type.rawValue
            var value = step.value
            if step.promptAtRun, let ov = inputs[step.id] { value = ov }   // 実行時入力で上書き
            if step.type == .fillUsername { type = "input"; value = cred?.username ?? "" }
            if step.type == .fillPassword { type = "input"; value = cred?.password ?? "" }
            let ok = await model.runStep(type: type, selector: step.selector, value: value, timeoutMs: step.timeoutMs)
            if !ok { status("⚠ 停止: 「\(step.type.title)」で失敗"); return }
        }
        status("✓ \(flow.name) が完了しました")
    }
}

// MARK: - 実行前の入力フォーム（勤怠などで実行時に値を入れて自動投入）

struct RunInputSheet: View {
    let flow: Flow
    let onRun: ([String: String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String]

    init(flow: Flow, onRun: @escaping ([String: String]) -> Void) {
        self.flow = flow; self.onRun = onRun
        var v: [String: String] = [:]
        for s in flow.steps where s.promptAtRun { v[s.id] = s.value ?? "" }
        _values = State(initialValue: v)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(flow.name).font(.system(size: 16, weight: .bold))
                    if !flow.note.isEmpty {
                        Text(flow.note).font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
                Section("入力内容") {
                    ForEach(flow.promptSteps) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label(s)).font(.system(size: 12)).foregroundColor(.secondary)
                            if s.secureInput {
                                SecureField("入力", text: binding(s.id))
                            } else {
                                TextField("入力", text: binding(s.id))
                                    .autocapitalization(.none).autocorrectionDisabled()
                            }
                        }
                    }
                }
                Section {
                    Text("「実行」を押すと、入力した内容を自動でページに反映し、送信まで実行します。")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .navigationTitle("実行前の入力").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("実行") { onRun(values); dismiss() }
                }
            }
        }
    }

    private func label(_ s: FlowStep) -> String {
        if let l = s.promptLabel, !l.isEmpty { return l }
        return s.type.title
    }
    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { values[id] ?? "" }, set: { values[id] = $0 })
    }
}

// MARK: - フロー一覧

struct FlowListView: View {
    @ObservedObject var flowStore: FlowStore
    @ObservedObject var credStore: CredentialStore
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Flow?
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showNew = true } label: { Label("フローを作成", systemImage: "plus.circle.fill") }
                }
                ForEach(flowStore.flows) { f in
                    Button { editing = f } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name.isEmpty ? "(無題)" : f.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                            Text("\(f.matchType.title): \(f.matchPattern) · \(f.steps.count)手順")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { flowStore.flows.remove(atOffsets: $0) }
            }
            .navigationTitle("自動化フロー").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
            .sheet(isPresented: $showNew) { FlowWizardView(flowStore: flowStore, credStore: credStore, model: model, editing: nil) }
            .sheet(item: $editing) { FlowWizardView(flowStore: flowStore, credStore: credStore, model: model, editing: $0) }
        }
    }
}

// MARK: - フロー作成ウィザード

struct FlowWizardView: View {
    @ObservedObject var flowStore: FlowStore
    @ObservedObject var credStore: CredentialStore
    @ObservedObject var model: BrowserModel
    var editing: Flow?
    @Environment(\.dismiss) private var dismiss

    @State private var flow: Flow
    @State private var picking = false

    init(flowStore: FlowStore, credStore: CredentialStore, model: BrowserModel, editing: Flow?) {
        self.flowStore = flowStore; self.credStore = credStore; self.model = model; self.editing = editing
        var f = editing ?? Flow()
        if editing == nil {
            f.startUrl = model.currentURL.hasPrefix("http") ? model.currentURL : ""
            if let host = URL(string: model.currentURL)?.host { f.matchPattern = host; if f.name.isEmpty { f.name = host } }
        }
        _flow = State(initialValue: f)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("対象") {
                    TextField("フロー名", text: $flow.name)
                    TextField("メモ（任意）", text: $flow.note, axis: .vertical).lineLimit(1...4)
                    TextField("開始URL", text: $flow.startUrl).autocapitalization(.none).autocorrectionDisabled()
                    Picker("マッチ方式", selection: $flow.matchType) {
                        ForEach(MatchType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("パターン（例: example.com）", text: $flow.matchPattern).autocapitalization(.none).autocorrectionDisabled()
                }

                Section("アクション（上から順に実行）") {
                    ForEach($flow.steps) { $step in
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("種類", selection: $step.type) {
                                ForEach(FlowActionType.allCases) { Text($0.title).tag($0) }
                            }
                            if step.type == .navigate {
                                TextField("移動先URL", text: Binding($step.url, "")).autocapitalization(.none).autocorrectionDisabled()
                            }
                            if step.type.needsSelector {
                                HStack {
                                    TextField("CSSセレクタ", text: Binding($step.selector, ""))
                                        .font(.system(size: 13, design: .monospaced)).autocapitalization(.none).autocorrectionDisabled()
                                    Button {
                                        picking = true
                                        model.onInspected = { info in
                                            if let i = flow.steps.firstIndex(where: { $0.id == step.id }) { flow.steps[i].selector = info.selector }
                                            picking = false; dismissKeyboard()
                                        }
                                        model.startInspect()
                                    } label: { Image(systemName: "target") }
                                    .buttonStyle(.borderless)
                                }
                            }
                            if step.type.needsValue {
                                TextField(valuePlaceholder(step), text: Binding($step.value, ""))
                                    .autocapitalization(.none).autocorrectionDisabled()
                            }
                            if step.type == .input || step.type == .select {
                                Toggle("実行時に入力を求める", isOn: $step.promptAtRun).font(.system(size: 13))
                                if step.promptAtRun {
                                    TextField("フォームの見出し（例: 出勤時刻）", text: Binding($step.promptLabel, ""))
                                        .font(.system(size: 13))
                                    Toggle("入力を伏せ字にする", isOn: $step.secureInput).font(.system(size: 13))
                                }
                            }
                        }
                    }
                    .onMove { flow.steps.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { flow.steps.remove(atOffsets: $0) }
                    Button { flow.steps.append(FlowStep()) } label: { Label("アクションを追加", systemImage: "plus") }
                }

                if flow.steps.contains(where: { $0.type == .fillUsername || $0.type == .fillPassword }) {
                    Section("認証情報") {
                        Picker("使用する認証情報", selection: Binding($flow.credentialId, "")) {
                            Text("選択してください").tag("")
                            ForEach(credStore.items) { c in Text("\(c.domain) — \(c.username)").tag(c.id) }
                        }
                        Text("⚠ 認証情報は端末内のKeychainにのみ保存され、外部送信されません。")
                            .font(.system(size: 11)).foregroundColor(.orange)
                    }
                }

                Section {
                    Stepper("各操作の前に待つ: \(flow.stepDelayMs) ms", value: $flow.stepDelayMs, in: 0...5000, step: 100)
                    Text("ポップアップや画面遷移が間に合わず失敗する場合は、待機を長くしてください（遅延実行）。")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }

                Section {
                    Toggle("有効", isOn: $flow.enabled)
                    Toggle("ホーム画面にアイコンを表示", isOn: $flow.pinnedToHome)
                    if flow.promptSteps.isEmpty {
                        Text("実行時入力なし: タップですぐ実行します。")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    } else {
                        Text("実行時入力あり: 実行前に \(flow.promptSteps.count) 項目の入力フォームを表示します。")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(editing == nil ? "フローを作成" : "フローを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(flow.name.isEmpty || flow.matchPattern.isEmpty)
                }
                ToolbarItem(placement: .principal) { if picking { Text("要素をタップ").font(.caption).foregroundColor(.blue) } }
            }
        }
    }

    private func save() {
        flow.updatedAt = ISO8601DateFormatter().string(from: Date())
        flow.useCredentials = flow.steps.contains { $0.type == .fillUsername || $0.type == .fillPassword }
        if let i = flowStore.flows.firstIndex(where: { $0.id == flow.id }) { flowStore.flows[i] = flow }
        else { flowStore.flows.append(flow) }
        dismiss()
    }
    private func valuePlaceholder(_ step: FlowStep) -> String {
        if step.type == .wait { return "待機ミリ秒" }
        return step.promptAtRun ? "既定値（実行時に編集可）" : "値"
    }
    private func dismissKeyboard() {
        #if !targetEnvironment(macCatalyst)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - 認証情報マネージャ（Keychain）

struct CredentialsView: View {
    @ObservedObject var store: CredentialStore
    @Environment(\.dismiss) private var dismiss
    @State private var domain = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("⚠ ユーザー名・パスワードは、この端末内のKeychain（暗号化）にのみ保存され、外部サーバーには一切送信されません。共有端末では保存しないでください。")
                        .font(.system(size: 12)).foregroundColor(.orange)
                }
                Section("追加") {
                    TextField("サイト（ドメイン）例: example.com", text: $domain).autocapitalization(.none).autocorrectionDisabled()
                    TextField("ユーザー名 / メール", text: $username).autocapitalization(.none).autocorrectionDisabled()
                    SecureField("パスワード", text: $password)
                    Button("保存") { store.save(domain: domain, username: username, password: password); domain = ""; username = ""; password = "" }
                        .disabled(domain.isEmpty || username.isEmpty)
                }
                Section("保存済み") {
                    ForEach(store.items) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.domain).font(.system(size: 15, weight: .semibold))
                            Text(c.username).font(.system(size: 12)).foregroundColor(.secondary)
                        }
                    }
                    .onDelete { idx in idx.map { store.items[$0].id }.forEach(store.delete) }
                    if store.items.isEmpty { Text("なし").foregroundColor(.secondary) }
                }
            }
            .navigationTitle("認証情報").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
    }
}

// Binding<String?> → Binding<String> ヘルパ
extension Binding where Value == String {
    init(_ source: Binding<String?>, _ fallback: String) {
        self.init(get: { source.wrappedValue ?? fallback },
                  set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
