import SwiftUI

/// 1タブ = 複数ペイン（分割表示）。分割してもアプリ共通ヘッダーは残る。
@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var panes: [BrowserModel]
    @Published var axis: Axis = .horizontal   // 2〜3分割時の並び方向
    @Published var activePane = 0
    init(home: Bool = true) { panes = [BrowserModel(home: home)] }
    var active: BrowserModel { panes[min(max(activePane, 0), panes.count - 1)] }
}

struct ContentView: View {
    @StateObject private var store = ProfileStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var flowStore = FlowStore()
    @StateObject private var credStore = CredentialStore()
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var splitStore = SplitStore()

    @State private var tabs: [BrowserTab] = []
    @State private var activeIndex = 0
    @State private var showPanel = false
    @State private var showLibrary = false
    @State private var showDrawer = false
    @State private var showFlows = false
    @State private var showCreds = false
    @State private var showHomeSettings = false
    @State private var editor: InlineEditor = .none
    @State private var wizardFlow: Flow?
    @State private var runInputFlow: Flow?
    @State private var flowStatus: String?
    @FocusState private var urlFocused: Bool

    private var accent: Color { Color(hex: settings.accentHex) }
    private var activeTab: BrowserTab? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex] : tabs.first
    }
    private var active: BrowserModel? { activeTab?.active }

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
                    onSplit: { showDrawer = false; splitTab(.horizontal) },
                    onHomeSettings: { showDrawer = false; showHomeSettings = true },
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
        .tint(accent)
        .onAppear {
            if tabs.isEmpty { tabs = [BrowserTab(home: true)] }
        }
        .sheet(isPresented: $showHomeSettings) { HomeSettingsView(settings: settings) }
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
        .sheet(item: $runInputFlow) { f in
            RunInputSheet(flow: f) { inputs in
                if let m = active { execFlow(f, model: m, inputs: inputs) }
            }
        }
    }

    // MARK: - コンテンツ（タブ毎のペイン群。分割してもヘッダーは上に残る）

    private var content: some View {
        ZStack {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                TabPanesView(tab: tab, store: store, library: library, settings: settings,
                             flowStore: flowStore, splitStore: splitStore, accent: accent,
                             onRunFlow: { flow, model in runFlow(flow, model: model) },
                             onOpenSplit: { cfg in openSplit(cfg) },
                             onNewSplit: { splitTab(.horizontal) })
                    .opacity(index == activeIndex ? 1 : 0)
                    .allowsHitTesting(index == activeIndex)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - 分割操作

    private func splitTab(_ axis: Axis) {
        guard let tab = activeTab, tab.panes.count < 4 else { return }
        tab.axis = axis
        // 新規ペインは従来通りの検索画面（ホーム）
        tab.panes.append(BrowserModel(home: true))
        tab.activePane = tab.panes.count - 1
    }

    private func saveSplitToHome() {
        guard let tab = activeTab, tab.panes.count > 1 else { return }
        var cfg = SplitConfig()
        cfg.urls = tab.panes.map { $0.isHome ? "" : $0.currentURL }
        cfg.layout = tab.panes.count >= 4 ? .grid4
            : tab.panes.count == 3 ? .triptych
            : (tab.axis == .vertical ? .rows2 : .columns2)
        cfg.name = URL(string: cfg.urls.first(where: { !$0.isEmpty }) ?? "")?.host ?? "分割ビュー"
        cfg.pinnedToHome = true
        splitStore.configs.insert(cfg, at: 0)
    }

    /// 保存済みの分割設定を現在のタブに展開（URL未指定ペインはホーム）
    private func openSplit(_ cfg: SplitConfig) {
        guard let tab = activeTab else { return }
        var models: [BrowserModel] = []
        for raw in cfg.urls.prefix(4) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                models.append(BrowserModel(home: true))
            } else {
                models.append(BrowserModel(home: false, url: t.hasPrefix("http") ? t : "https://" + t))
            }
        }
        if models.isEmpty { models = [BrowserModel(home: true)] }
        tab.axis = cfg.layout == .rows2 ? .vertical : .horizontal
        tab.panes = models
        tab.activePane = 0
    }

    // MARK: - フロー実行ヘッダー

    @ViewBuilder
    private var flowHeader: some View {
        if let tab = activeTab {
            FlowHeaderHost(tab: tab, flowStore: flowStore, status: $flowStatus) { flow, model in
                runFlow(flow, model: model)
            }
        }
    }

    private func runFlow(_ flow: Flow, model: BrowserModel) {
        if !flow.promptSteps.isEmpty {
            runInputFlow = flow
        } else {
            execFlow(flow, model: model, inputs: [:])
        }
    }

    private func execFlow(_ flow: Flow, model: BrowserModel, inputs: [String: String]) {
        model.isHome = false
        Task {
            await FlowRunner.run(flow, model: model, creds: credStore, inputs: inputs) { s in flowStatus = s }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            flowStatus = nil
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
        if active?.isHome == true { return }
        editor = e
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
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        TabChip(tab: tab, isActive: index == activeIndex,
                                showClose: tabs.count > 1,
                                onSelect: { activeIndex = index },
                                onClose: { closeTab(at: index) })
                    }
                    Button {
                        tabs.append(BrowserTab(home: true))
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
            tabs = [BrowserTab(home: true)]
            activeIndex = 0
        } else if activeIndex >= tabs.count {
            activeIndex = tabs.count - 1
        }
    }

    // MARK: - ナビゲーションバー

    @ViewBuilder
    private var navBar: some View {
        if let tab = activeTab {
            NavBarHost(tab: tab, library: library, settings: settings,
                       showPanel: $showPanel, urlFocused: $urlFocused,
                       onSplit: { axis in splitTab(axis) },
                       onSaveSplit: { saveSplitToHome() })
        }
    }
}

// MARK: - タブ内のペイン描画（分割）

private struct TabPanesView: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var store: ProfileStore
    @ObservedObject var library: LibraryStore
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var flowStore: FlowStore
    @ObservedObject var splitStore: SplitStore
    let accent: Color
    let onRunFlow: (Flow, BrowserModel) -> Void
    let onOpenSplit: (SplitConfig) -> Void
    let onNewSplit: () -> Void

    var body: some View {
        Group {
            if tab.panes.count == 4 {
                VStack(spacing: 1) {
                    HStack(spacing: 1) { pane(0); pane(1) }
                    HStack(spacing: 1) { pane(2); pane(3) }
                }
            } else if tab.axis == .horizontal {
                HStack(spacing: 1) {
                    ForEach(Array(tab.panes.enumerated()), id: \.element.id) { i, _ in pane(i) }
                }
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(tab.panes.enumerated()), id: \.element.id) { i, _ in pane(i) }
                }
            }
        }
    }

    @ViewBuilder private func pane(_ i: Int) -> some View {
        if i < tab.panes.count {
            let model = tab.panes[i]
            VStack(spacing: 0) {
                // 分割時のみ: ペインの選択・クローズ用ストリップ
                if tab.panes.count > 1 {
                    PaneStrip(model: model, isActive: i == tab.activePane, accent: accent,
                              onSelect: { tab.activePane = i },
                              onClose: { closePane(i) })
                }
                ZStack {
                    BrowserView(model: model, store: store) { url, title in
                        library.recordVisit(url: url, title: title)
                    }
                    if model.isHome {
                        // 未指定の新規分割ペインは従来通りの検索画面
                        StartView(settings: settings, library: library, flowStore: flowStore, splitStore: splitStore,
                                  onSearch: { model.navigate($0); tab.activePane = i },
                                  onRunFlow: { f in onRunFlow(f, model) },
                                  onOpenSplit: onOpenSplit,
                                  onNewSplit: onNewSplit)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .id(model.id)
        }
    }

    private func closePane(_ i: Int) {
        guard tab.panes.count > 1 else { return }
        tab.panes.remove(at: i)
        if tab.activePane >= tab.panes.count { tab.activePane = tab.panes.count - 1 }
    }
}

/// 分割ペイン上部の選択ストリップ
private struct PaneStrip: View {
    @ObservedObject var model: BrowserModel
    let isActive: Bool
    let accent: Color
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(isActive ? accent : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
            Text(model.isHome ? "ホーム" : (model.title.isEmpty ? model.currentURL : model.title))
                .font(.system(size: 11, weight: isActive ? .bold : .regular)).lineLimit(1)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
            }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isActive ? accent.opacity(0.14) : Color(uiColor: .secondarySystemBackground))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - フロー実行ヘッダー（アクティブペインに追従）

private struct FlowHeaderHost: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var flowStore: FlowStore
    @Binding var status: String?
    let onRun: (Flow, BrowserModel) -> Void
    var body: some View {
        FlowHeaderInner(model: tab.active, flowStore: flowStore, status: $status, onRun: onRun)
    }
}

private struct FlowHeaderInner: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var flowStore: FlowStore
    @Binding var status: String?
    let onRun: (Flow, BrowserModel) -> Void

    var body: some View {
        if !model.isHome {
            let matched = flowStore.matched(for: model.currentURL)
            if !matched.isEmpty || status != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let s = status {
                            Text(s).font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary).lineLimit(1)
                        }
                        ForEach(matched) { flow in
                            Button { onRun(flow, model) } label: {
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
}

// MARK: - 左ドロワー

private struct DrawerView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var settings: AppSettingsStore
    let onFlows: () -> Void
    let onCreds: () -> Void
    let onStyle: () -> Void
    let onSite: () -> Void
    let onLibrary: () -> Void
    let onRecord: () -> Void
    let onSplit: () -> Void
    let onHomeSettings: () -> Void
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
                    row("rectangle.split.2x2", "分割ビュー（複数サイト）", onSplit)
                    row("wand.and.stars", "自動化フロー", onFlows)
                    row(isRecording ? "record.circle.fill" : "record.circle",
                        isRecording ? "記録を停止" : "操作を記録", onRecord, tint: isRecording ? .red : nil)
                    row("key.fill", "認証情報（端末内）", onCreds)
                    row("paintbrush.pointed", "スタイル編集", onStyle)
                    row("slider.horizontal.3", "サイト設定", onSite)
                    row("paintpalette", "ホーム / 見た目の編集", onHomeSettings)
                    row("books.vertical", "ブックマーク・履歴", onLibrary)
                    Divider().padding(.vertical, 8)
                    Text("検索エンジン").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary).padding(.horizontal, 16).padding(.top, 4)
                    ForEach(DEFAULT_ENGINES) { e in
                        Button { settings.engineId = e.id } label: {
                            HStack {
                                Image(systemName: settings.engineId == e.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(settings.engineId == e.id ? Color(hex: settings.accentHex) : .secondary)
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

// MARK: - タブチップ

private struct TabChip: View {
    @ObservedObject var tab: BrowserTab
    let isActive: Bool
    let showClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if tab.panes.count > 1 {
                Image(systemName: "rectangle.split.2x1").font(.system(size: 10))
            }
            ChipTitle(model: tab.active, isActive: isActive)
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

private struct ChipTitle: View {
    @ObservedObject var model: BrowserModel
    let isActive: Bool
    var body: some View {
        Text(model.isHome ? "ホーム" : (model.title.isEmpty ? "New Tab" : model.title))
            .font(.system(size: 12, weight: isActive ? .bold : .regular))
            .lineLimit(1)
            .frame(maxWidth: 120)
    }
}

// MARK: - ナビバー（アクティブペインに追従）

private struct NavBarHost: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var library: LibraryStore
    @ObservedObject var settings: AppSettingsStore
    @Binding var showPanel: Bool
    var urlFocused: FocusState<Bool>.Binding
    let onSplit: (Axis) -> Void
    let onSaveSplit: () -> Void

    var body: some View {
        NavBarView(model: tab.active, library: library, settings: settings,
                   showPanel: $showPanel, urlFocused: urlFocused,
                   paneCount: tab.panes.count, onSplit: onSplit, onSaveSplit: onSaveSplit)
    }
}

private struct NavBarView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var library: LibraryStore
    @ObservedObject var settings: AppSettingsStore
    @Binding var showPanel: Bool
    var urlFocused: FocusState<Bool>.Binding
    let paneCount: Int
    let onSplit: (Axis) -> Void
    let onSaveSplit: () -> Void

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

            // 分割メニュー（検索後に押すと現在のビューを分割。新ペインは検索画面）
            Menu {
                Button { onSplit(.horizontal) } label: { Label("左右に分割", systemImage: "rectangle.split.2x1") }
                    .disabled(paneCount >= 4)
                Button { onSplit(.vertical) } label: { Label("上下に分割", systemImage: "rectangle.split.1x2") }
                    .disabled(paneCount >= 4)
                if paneCount > 1 {
                    Button { onSaveSplit() } label: { Label("この分割をホームに保存", systemImage: "pin") }
                }
            } label: {
                Image(systemName: paneCount > 1 ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
            }

            if settings.showBookmarkButton {
                Button {
                    library.toggleBookmark(url: model.currentURL, title: model.title)
                } label: {
                    Image(systemName: library.isBookmarked(model.currentURL) ? "star.fill" : "star")
                        .foregroundColor(library.isBookmarked(model.currentURL) ? .yellow : .accentColor)
                }
            }

            // カメレオンバッジ: 適用中プロファイル数 → Site Panel
            if settings.showChameleonBadge {
                Button { showPanel = true } label: {
                    HStack(spacing: 3) {
                        Text("🦎")
                        Text("\(model.matchedCount)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(model.matchedCount > 0 ? Color(hex: settings.accentHex) : .secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
    }
}
