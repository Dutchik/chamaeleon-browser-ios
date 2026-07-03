import SwiftUI

struct ContentView: View {
    @StateObject private var store = ProfileStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var flowStore = FlowStore()
    @StateObject private var credStore = CredentialStore()
    @StateObject private var settings = AppSettingsStore()

    @State private var tabs: [BrowserModel] = []
    @State private var activeIndex = 0
    @State private var showPanel = false
    @State private var showLibrary = false
    @State private var showDrawer = false
    @State private var showFlows = false
    @State private var showCreds = false
    @State private var editor: InlineEditor = .none
    @State private var wizardFlow: Flow?
    @State private var flowStatus: String?
    @FocusState private var urlFocused: Bool

    private var active: BrowserModel? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex] : tabs.first
    }

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                tabBar
                navBar
                flowHeader
                Divider()
                content
            }

            // 左ハンバーガードロワー
            if showDrawer {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { withAnimation { showDrawer = false } }
                DrawerView(
                    library: library, settings: settings,
                    onFlows: { showDrawer = false; showFlows = true },
                    onCreds: { showDrawer = false; showCreds = true },
                    onStyle: { showDrawer = false; openEditor(.style) },
                    onSite: { showDrawer = false; showPanel = true },
                    onLibrary: { showDrawer = false; showLibrary = true },
                    onRecord: { showDrawer = false; openEditor(.record) },
                    onHome: { showDrawer = false; active?.goHome() },
                    isRecording: editor == .record
                )
                .frame(width: 290).frame(maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
                .transition(.move(edge: .leading))
            }

            // 画面下部の編集パネル（ページを見ながら設定）
            inlineEditorPanel
        }
        .onAppear {
            if tabs.isEmpty { tabs = [BrowserModel(home: true)] }
        }
        .sheet(isPresented: $showPanel) {
            if let m = active {
                SitePanelView(store: store, model: m, flowStore: flowStore, credStore: credStore) { flow in
                    showPanel = false
                    runFlow(flow, model: m)
                }
            }
        }
        .sheet(isPresented: $showLibrary) { if let m = active { LibraryView(library: library, model: m) } }
        .sheet(isPresented: $showFlows) { if let m = active { FlowListView(flowStore: flowStore, credStore: credStore, model: m) } }
        .sheet(isPresented: $showCreds) { CredentialsView(store: credStore) }
        .sheet(item: $wizardFlow) { f in
            if let m = active { FlowWizardView(flowStore: flowStore, credStore: credStore, model: m, editing: f) }
        }
    }

    // MARK: - インライン編集パネル

    @ViewBuilder
    private var inlineEditorPanel: some View {
        if let model = active, editor != .none {
            VStack {
                Spacer()
                switch editor {
                case .style:
                    InlineStylePanel(store: store, model: model) { editor = .none }
                case .record:
                    InlineRecordPanel(model: model, onClose: { editor = .none }) { flow in
                        editor = .none
                        wizardFlow = flow
                    }
                case .none:
                    EmptyView()
                }
            }
            .transition(.move(edge: .bottom))
        }
    }

    private func openEditor(_ e: InlineEditor) {
        // ホーム画面では編集対象のページが無いので開かない
        if active?.isHome == true { return }
        editor = e
    }

    // MARK: - コンテンツ（ホーム or WebView）

    private var content: some View {
        ZStack {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, model in
                ZStack {
                    BrowserView(model: model, store: store) { url, title in
                        library.recordVisit(url: url, title: title)
                    }
                    if model.isHome {
                        StartView(settings: settings, library: library) { target in
                            model.navigate(target)
                        }
                    }
                }
                .opacity(index == activeIndex ? 1 : 0)
                .allowsHitTesting(index == activeIndex)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - フロー実行ヘッダー（マッチしたページで表示）

    @ViewBuilder
    private var flowHeader: some View {
        if let model = active, !model.isHome {
            let matched = flowStore.matched(for: model.currentURL)
            if !matched.isEmpty || flowStatus != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let s = flowStatus {
                            Text(s).font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary).lineLimit(1)
                        }
                        ForEach(matched) { flow in
                            Button {
                                runFlow(flow, model: model)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill").font(.system(size: 10))
                                    Text(flow.name).font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .background(Color(uiColor: .secondarySystemBackground))
            }
        }
    }

    private func runFlow(_ flow: Flow, model: BrowserModel) {
        Task {
            await FlowRunner.run(flow, model: model, creds: credStore) { s in flowStatus = s }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            flowStatus = nil
        }
    }

    // MARK: - タブバー

    private var tabBar: some View {
        HStack(spacing: 6) {
            Button { withAnimation { showDrawer.toggle() } } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 16, weight: .semibold))
            }
            .padding(.leading, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, model in
                        TabChip(model: model, isActive: index == activeIndex,
                                showClose: tabs.count > 1,
                                onSelect: { activeIndex = index },
                                onClose: { closeTab(at: index) })
                    }
                    Button {
                        tabs.append(BrowserModel(home: true))
                        activeIndex = tabs.count - 1
                    } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 5)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func closeTab(at index: Int) {
        tabs.remove(at: index)
        if tabs.isEmpty {
            tabs = [BrowserModel(home: true)]
            activeIndex = 0
        } else if activeIndex >= tabs.count {
            activeIndex = tabs.count - 1
        }
    }

    // MARK: - ナビゲーションバー

    @ViewBuilder
    private var navBar: some View {
        if let model = active {
            NavBarView(model: model, library: library,
                       showPanel: $showPanel,
                       urlFocused: $urlFocused)
        }
    }
}

/// 左ドロワー（ハンバーガーメニュー）
private struct DrawerView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var settings: AppSettingsStore
    let onFlows: () -> Void
    let onCreds: () -> Void
    let onStyle: () -> Void
    let onSite: () -> Void
    let onLibrary: () -> Void
    let onRecord: () -> Void
    let onHome: () -> Void
    let isRecording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("🦎 Chamaeleon").font(.system(size: 18, weight: .heavy))
                Spacer()
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    row("house", "ホーム", onHome)
                    row("wand.and.stars", "自動化フロー", onFlows)
                    row(isRecording ? "record.circle.fill" : "record.circle",
                        isRecording ? "記録を停止" : "操作を記録", onRecord, tint: isRecording ? .red : nil)
                    row("key.fill", "認証情報（端末内）", onCreds)
                    row("paintbrush.pointed", "スタイル編集", onStyle)
                    row("slider.horizontal.3", "サイト設定", onSite)
                    row("books.vertical", "ブックマーク・履歴", onLibrary)
                    Divider().padding(.vertical, 8)
                    Text("検索エンジン").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary).padding(.horizontal, 16).padding(.top, 4)
                    ForEach(DEFAULT_ENGINES) { e in
                        Button { settings.engineId = e.id } label: {
                            HStack {
                                Image(systemName: settings.engineId == e.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(settings.engineId == e.id ? .green : .secondary)
                                Text(e.name).foregroundColor(.primary)
                                Spacer()
                            }
                            .font(.system(size: 14)).padding(.horizontal, 16).padding(.vertical, 9)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func row(_ icon: String, _ label: String, _ action: @escaping () -> Void, tint: Color? = nil) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundColor(tint ?? .accentColor)
                Text(label).foregroundColor(.primary)
                Spacer()
            }
            .font(.system(size: 15)).padding(.horizontal, 16).padding(.vertical, 11)
        }
    }
}

/// タブ1枚分のチップ（modelのtitleを購読）
private struct TabChip: View {
    @ObservedObject var model: BrowserModel
    let isActive: Bool
    let showClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(model.isHome ? "ホーム" : (model.title.isEmpty ? "New Tab" : model.title))
                .font(.system(size: 12, weight: isActive ? .bold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 120)
            if showClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isActive ? Color(uiColor: .secondarySystemBackground) : .clear)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: onSelect)
    }
}

/// ナビバー本体（activeタブのBrowserModelを購読するため分離）
private struct NavBarView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var library: LibraryStore
    @Binding var showPanel: Bool
    var urlFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Button { model.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack)
            Button { model.webView?.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward)

            TextField("URLまたは検索", text: $model.urlInput)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .focused(urlFocused)
                .onSubmit {
                    model.navigate(model.urlInput)
                    urlFocused.wrappedValue = false
                }

            if model.isLoading {
                Button { model.webView?.stopLoading(); model.isLoading = false } label: {
                    Image(systemName: "xmark")
                }
            } else {
                Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
            }

            Button {
                library.toggleBookmark(url: model.currentURL, title: model.title)
            } label: {
                Image(systemName: library.isBookmarked(model.currentURL) ? "star.fill" : "star")
                    .foregroundColor(library.isBookmarked(model.currentURL) ? .yellow : .accentColor)
            }

            // カメレオンバッジ: 適用中プロファイル数 → Site Panel
            Button { showPanel = true } label: {
                HStack(spacing: 3) {
                    Text("🦎")
                    Text("\(model.matchedCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(model.matchedCount > 0 ? .green : .secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
    }
}
