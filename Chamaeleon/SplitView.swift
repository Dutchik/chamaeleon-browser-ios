import SwiftUI
import WebKit

/// 分割ビュー内の1ペイン用の軽量WebView（登録済みプロファイルのCSS/DOM/JSも適用）
struct PaneWebView: UIViewRepresentable {
    let urlString: String
    @ObservedObject var store: ProfileStore

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        load(urlString, into: wv, context: context)
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {
        if context.coordinator.loaded != urlString { load(urlString, into: wv, context: context) }
    }
    private func load(_ s: String, into wv: WKWebView, context: Context) {
        context.coordinator.loaded = s
        guard let u = URL(string: s.hasPrefix("http") ? s : "https://\(s)") else { return }
        wv.load(URLRequest(url: u))
    }
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let store: ProfileStore
        var loaded: String?
        init(store: ProfileStore) { self.store = store }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            Task { @MainActor in PatchEngine.apply(profiles: store.matched(for: url), stage: .documentStart, to: webView) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            Task { @MainActor in
                let m = store.matched(for: url)
                PatchEngine.apply(profiles: m, stage: .documentEnd, to: webView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    PatchEngine.apply(profiles: m, stage: .idle, to: webView)
                }
            }
        }
    }
}

/// 複数サイトを同時に開く分割ビュー画面
struct SplitContainerView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var splitStore: SplitStore
    @State var config: SplitConfig
    let accent: Color
    let onClose: () -> Void
    @State private var showEdit = false

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack(spacing: 10) {
                Button(action: onClose) { Image(systemName: "chevron.left") }
                Text(config.name.isEmpty ? "分割ビュー" : config.name)
                    .font(.system(size: 15, weight: .bold)).lineLimit(1)
                Spacer()
                Menu {
                    ForEach(SplitLayout.allCases) { l in
                        Button { config.layout = l; config.normalize() } label: {
                            Label(l.title, systemImage: l.systemImage)
                        }
                    }
                } label: { Image(systemName: config.layout.systemImage) }
                Button { showEdit = true } label: { Image(systemName: "slider.horizontal.3") }
                Button { save() } label: { Image(systemName: "pin.fill") }.foregroundColor(accent)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .tint(accent)
            .background(Color(uiColor: .systemBackground))
            Divider()

            panes.ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showEdit) { SplitEditView(config: $config) }
    }

    @ViewBuilder private var panes: some View {
        switch config.layout {
        case .columns2:
            HStack(spacing: 2) { pane(0); pane(1) }
        case .rows2:
            VStack(spacing: 2) { pane(0); pane(1) }
        case .triptych:
            HStack(spacing: 2) { pane(0); pane(1); pane(2) }
        case .grid4:
            VStack(spacing: 2) {
                HStack(spacing: 2) { pane(0); pane(1) }
                HStack(spacing: 2) { pane(2); pane(3) }
            }
        }
    }

    @ViewBuilder private func pane(_ i: Int) -> some View {
        let url = i < config.urls.count ? config.urls[i] : ""
        if url.trimmingCharacters(in: .whitespaces).isEmpty {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                VStack(spacing: 6) {
                    Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 22)).foregroundColor(.secondary)
                    Text("URL未設定").font(.system(size: 12)).foregroundColor(.secondary)
                    Button("編集") { showEdit = true }.font(.system(size: 12)).tint(accent)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PaneWebView(urlString: url, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    private func save() {
        var c = config; c.normalize(); c.pinnedToHome = true
        if let i = splitStore.configs.firstIndex(where: { $0.id == c.id }) { splitStore.configs[i] = c }
        else { splitStore.configs.insert(c, at: 0) }
        config = c
    }
}

/// 分割ビューのURL・レイアウト・名前を編集
struct SplitEditView: View {
    @Binding var config: SplitConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("設定") {
                    TextField("名前", text: $config.name)
                    Picker("レイアウト", selection: $config.layout) {
                        ForEach(SplitLayout.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    .onChange(of: config.layout) { _ in config.normalize() }
                }
                Section("各ペインのURL") {
                    ForEach(0..<config.layout.paneCount, id: \.self) { i in
                        TextField("ペイン\(i + 1) のURL", text: bindingFor(i))
                            .autocapitalization(.none).autocorrectionDisabled()
                            .font(.system(size: 13))
                    }
                }
                Section { Toggle("ホーム画面に表示", isOn: $config.pinnedToHome) }
            }
            .navigationTitle("分割ビューの編集").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
            .onAppear { config.normalize() }
        }
    }

    private func bindingFor(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < config.urls.count ? config.urls[i] : "" },
            set: { v in
                config.normalize()
                if i < config.urls.count { config.urls[i] = v }
            })
    }
}
