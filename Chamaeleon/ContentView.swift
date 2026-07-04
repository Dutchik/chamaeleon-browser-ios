import SwiftUI

/// 1タブ = 複数ペイン（分割表示）。分割してもアプリ共通ヘッダーは残る。
@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var panes: [BrowserModel]
    @Published var axis: Axis = .horizontal
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
    @StateObject private var netRules = NetRuleStore()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var recordSession = RecordSession()

    @State private var tabs: [BrowserTab] = []
    @State private var activeIndex = 0
    @State private var showPanel = false
    @State private var showLibrary = false
    @State private var showDrawer = false
    @State private var showFlows = false
    @State private var showCreds = false
    @State private var showHomeSettings = false
    @State private var showBlock = false
    @State private var showDownloader = false
    @State private var videoMenuSrc: String?
    @StateObject private var screenRecorder = ScreenRecorder()
    @State private var captureToast: String?
    @State private var editor: InlineEditor = .none      // 下部スタイル編集パネル
    @State private var dockExpanded = false              // 右ドックの展開状態
    @State private var wizardFlow: Flow?
    @State private var runInputFlow: Flow?
    @State private var flowStatus: String?
    @FocusState private var urlFocused: Bool

    private var accent: Color { Color(hex: settings.accentHex) }
    private var activeTab: BrowserTab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : tabs.first }
    private var active: BrowserModel? { activeTab?.active }

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                header
                Divider()
                content
            }

            // 右パネル（操作記録の登録内容 / スタイル設定の入力エリア）
            if let tab = activeTab {
                DockHost(tab: tab, store: store, session: recordSession, accent: accent,
                         editorIsStyle: editor == .style, expanded: $dockExpanded,
                         onCloseStyle: { active?.clearPreview(); editor = .none },
                         onCloseRecord: { recordSession.stop() },
                         onSaveFlow: { flow in dockExpanded = false; wizardFlow = flow })
            }

            // 左ハンバーガードロワー
            if showDrawer {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { withAnimation { showDrawer = false } }
                DrawerView(
                    library: library, settings: settings,
                    onFlows: { showDrawer = false; showFlows = true },
                    onCreds: { showDrawer = false; showCreds = true },
                    onStyle: { showDrawer = false; openStyle() },
                    onSite: { showDrawer = false; showPanel = true },
                    onLibrary: { showDrawer = false; showLibrary = true },
                    onRecord: { showDrawer = false; toggleRecord() },
                    onSplit: { showDrawer = false; splitTab(.horizontal) },
                    onHomeSettings: { showDrawer = false; showHomeSettings = true },
                    onBlock: { showDrawer = false; showBlock = true },
                    onDownload: { showDrawer = false; showDownloader = true },
                    onHome: { showDrawer = false; active?.goHome() },
                    isRecording: recordSession.active
                )
                .frame(width: 290).frame(maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
                .transition(.move(edge: .leading))
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { v in
                            if v.translation.width < -45 { withAnimation { showDrawer = false } }
                        }
                )
            }

            // フロー実行のステータス表示（トースト）
            if let s = flowStatus {
                VStack {
                    Spacer()
                    Text(s).font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial).clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            // 取り込み中／画面録画中のフローティングバー
            VStack {
                Spacer()
                if netRules.sessionActive {
                    captureBar("取り込み中… 再生後に完了", color: .green, button: "完了") {
                        netRules.stopCaptureSession(); captureToast = "取り込みを保存しました"
                    }
                } else if screenRecorder.recording {
                    captureBar("画面録画中…", color: .red, button: "停止") { screenRecorder.stop() }
                } else if let t = captureToast {
                    Text(t).font(.system(size: 13, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial).clipShape(Capsule()).padding(.bottom, 26)
                        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { captureToast = nil } }
                }
            }.frame(maxWidth: .infinity)
        }
        .tint(accent)
        .onAppear { if tabs.isEmpty { tabs = [BrowserTab(home: true)] } }
        .confirmationDialog("動画のキャプチャ", isPresented: Binding(
            get: { videoMenuSrc != nil }, set: { if !$0 { videoMenuSrc = nil } }), titleVisibility: .visible) {
            Button("この動画を取り込み（m3u8対応）") { startVideoCapture() }
            Button("画面録画を開始") { screenRecorder.start() }
            Button("キャンセル", role: .cancel) { videoMenuSrc = nil }
        } message: {
            Text("パケット層で動画を取り込みます（HTTPSはブロック設定でMITM ON）。または画面録画します。私的利用の範囲でご利用ください。")
        }
        .sheet(isPresented: $showHomeSettings) { HomeSettingsView(settings: settings) }
        .sheet(isPresented: $showPanel) {
            if let m = active {
                SitePanelView(store: store, model: m, flowStore: flowStore, credStore: credStore) { flow in
                    showPanel = false; runFlow(flow, model: m)
                }
            }
        }
        .sheet(isPresented: $showLibrary) { if let m = active { LibraryView(library: library, model: m) } }
        .sheet(isPresented: $showFlows) { if let m = active { FlowListView(flowStore: flowStore, credStore: credStore, model: m) } }
        .sheet(isPresented: $showCreds) { CredentialsView(store: credStore) }
        .sheet(isPresented: $showBlock) { if let m = active { BlockRulesView(netRules: netRules, model: m, accent: accent) } }
        .sheet(isPresented: $showDownloader) { if let m = active { DownloaderView(manager: downloadManager, model: m, accent: accent) } }
        .sheet(item: $wizardFlow) { f in
            if let m = active { FlowWizardView(flowStore: flowStore, credStore: credStore, model: m, editing: f) }
        }
        .sheet(item: $runInputFlow) { f in
            RunInputSheet(flow: f) { inputs in if let m = active { execFlow(f, model: m, inputs: inputs) } }
        }
    }

    // MARK: - 一行ヘッダー

    @ViewBuilder
    private var header: some View {
        if let tab = activeTab {
            HeaderBar(tab: tab, settings: settings, library: library, urlFocused: $urlFocused,
                      tabCount: tabs.count, tabTitles: tabs.map { $0.active.title }, activeIndex: activeIndex,
                      onMenu: { withAnimation { showDrawer.toggle() } },
                      onBadge: { showPanel = true },
                      onNewTab: { tabs.append(BrowserTab(home: true)); activeIndex = tabs.count - 1 },
                      onSelectTab: { activeIndex = $0 },
                      onCloseTab: { closeTab(at: $0) })
        }
    }

    // MARK: - コンテンツ（タブ毎のペイン群）

    private var content: some View {
        ZStack {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                TabPanesView(tab: tab, store: store, library: library, settings: settings,
                             flowStore: flowStore, splitStore: splitStore, netRules: netRules, accent: accent,
                             onRunFlow: { flow, model in runFlow(flow, model: model) },
                             onOpenSplit: { cfg in openSplit(cfg) },
                             onNewSplit: { splitTab(.horizontal) },
                             onVideoMenu: { src in videoMenuSrc = src })
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
        tab.panes.append(BrowserModel(home: true))
        tab.activePane = tab.panes.count - 1
    }

    private func openSplit(_ cfg: SplitConfig) {
        guard let tab = activeTab else { return }
        var models: [BrowserModel] = []
        for raw in cfg.urls.prefix(4) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            models.append(t.isEmpty ? BrowserModel(home: true)
                          : BrowserModel(home: false, url: t.hasPrefix("http") ? t : "https://" + t))
        }
        if models.isEmpty { models = [BrowserModel(home: true)] }
        tab.axis = cfg.layout == .rows2 ? .vertical : .horizontal
        tab.panes = models
        tab.activePane = 0
    }

    // MARK: - フロー

    private func runFlow(_ flow: Flow, model: BrowserModel) {
        if !flow.promptSteps.isEmpty { runInputFlow = flow }
        else { execFlow(flow, model: model, inputs: [:]) }
    }

    private func execFlow(_ flow: Flow, model: BrowserModel, inputs: [String: String]) {
        model.isHome = false
        Task {
            await FlowRunner.run(flow, model: model, creds: credStore, inputs: inputs) { s in flowStatus = s }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            flowStatus = nil
        }
    }

    // MARK: - 記録 / スタイル

    private func toggleRecord() {
        if recordSession.active { recordSession.stop(); return }
        guard let m = active, !m.isHome else { return }
        editor = .none            // スタイル編集を閉じて記録に切替
        recordSession.start(m)
        dockExpanded = false      // 右側に閉じて配置（展開タブから開く）
    }

    private func openStyle() {
        if active?.isHome == true { return }
        editor = .style
        dockExpanded = true       // 右から設定パネルを出す
    }

    private func captureBar(_ text: String, color: Color, button: String, _ action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(button, action: action).buttonStyle(.borderedProminent).tint(color)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial).clipShape(Capsule())
        .padding(.horizontal, 12).padding(.bottom, 24)
    }

    private func startVideoCapture() {
        videoMenuSrc = nil
        netRules.startCaptureSession()   // プロキシ＋キャプチャ＋セッション開始
        active?.webView?.reload()        // 再生し直してセグメントをプロキシ経由に
        captureToast = "取り込み開始。動画を再生してください"
    }

    private func closeTab(at index: Int) {
        tabs.remove(at: index)
        if tabs.isEmpty { tabs = [BrowserTab(home: true)]; activeIndex = 0 }
        else if activeIndex >= tabs.count { activeIndex = tabs.count - 1 }
    }
}

// MARK: - 一行ヘッダー本体

private struct HeaderBar: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var library: LibraryStore
    var urlFocused: FocusState<Bool>.Binding
    let tabCount: Int
    let tabTitles: [String]
    let activeIndex: Int
    let onMenu: () -> Void
    let onBadge: () -> Void
    let onNewTab: () -> Void
    let onSelectTab: (Int) -> Void
    let onCloseTab: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onMenu) { Image(systemName: "line.3.horizontal").font(.system(size: 16, weight: .semibold)) }
                .padding(.leading, 4)
            NavControls(model: tab.active, settings: settings, library: library, urlFocused: urlFocused, onBadge: onBadge)
            tabsMenu
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground))
    }

    private var tabsMenu: some View {
        Menu {
            ForEach(0..<tabCount, id: \.self) { i in
                Button { onSelectTab(i) } label: {
                    Label(i < tabTitles.count && !tabTitles[i].isEmpty ? tabTitles[i] : "タブ \(i + 1)",
                          systemImage: i == activeIndex ? "checkmark" : "doc")
                }
            }
            Divider()
            if !tab.active.isHome {
                Button { tab.active.findOnPage() } label: { Label("ページ内を検索", systemImage: "magnifyingglass") }
            }
            Button { onNewTab() } label: { Label("新しいタブ", systemImage: "plus") }
            if tabCount > 1 {
                Button(role: .destructive) { onCloseTab(activeIndex) } label: { Label("このタブを閉じる", systemImage: "xmark") }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "square.on.square").font(.system(size: 14))
                Text("\(tabCount)").font(.system(size: 12, weight: .bold))
            }
        }
    }
}

/// ヘッダー内のナビ操作（アクティブペインを購読）
private struct NavControls: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var library: LibraryStore
    var urlFocused: FocusState<Bool>.Binding
    let onBadge: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { model.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack)
            Button { model.webView?.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward)

            TextField("URLまたは検索", text: $model.urlInput)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL).autocapitalization(.none).autocorrectionDisabled()
                .focused(urlFocused)
                .frame(maxWidth: .infinity)
                .onSubmit { model.navigate(model.urlInput); urlFocused.wrappedValue = false }

            if model.isLoading {
                Button { model.webView?.stopLoading(); model.isLoading = false } label: { Image(systemName: "xmark") }
            } else {
                Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
            }

            if settings.showBookmarkButton {
                Button { library.toggleBookmark(url: model.currentURL, title: model.title) } label: {
                    Image(systemName: library.isBookmarked(model.currentURL) ? "star.fill" : "star")
                        .foregroundColor(library.isBookmarked(model.currentURL) ? .yellow : .accentColor)
                }
            }
            if settings.showChameleonBadge {
                Button(action: onBadge) {
                    HStack(spacing: 2) {
                        Text("🦎")
                        Text("\(model.matchedCount)").font(.system(size: 12, weight: .bold))
                            .foregroundColor(model.matchedCount > 0 ? Color(hex: settings.accentHex) : .secondary)
                    }
                }
            }
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
    @ObservedObject var netRules: NetRuleStore
    let accent: Color
    let onRunFlow: (Flow, BrowserModel) -> Void
    let onOpenSplit: (SplitConfig) -> Void
    let onNewSplit: () -> Void
    let onVideoMenu: (String) -> Void

    var body: some View {
        Group {
            if tab.panes.count == 4 {
                VStack(spacing: 1) {
                    HStack(spacing: 1) { pane(0); pane(1) }
                    HStack(spacing: 1) { pane(2); pane(3) }
                }
            } else if tab.axis == .horizontal {
                HStack(spacing: 1) { ForEach(Array(tab.panes.enumerated()), id: \.element.id) { i, _ in pane(i) } }
            } else {
                VStack(spacing: 1) { ForEach(Array(tab.panes.enumerated()), id: \.element.id) { i, _ in pane(i) } }
            }
        }
    }

    @ViewBuilder private func pane(_ i: Int) -> some View {
        if i < tab.panes.count {
            let model = tab.panes[i]
            VStack(spacing: 0) {
                if tab.panes.count > 1 {
                    PaneStrip(model: model, isActive: i == tab.activePane, accent: accent,
                              onSelect: { tab.activePane = i }, onClose: { closePane(i) })
                }
                ZStack {
                    BrowserView(model: model, store: store, netRules: netRules) { url, title in library.recordVisit(url: url, title: title) }
                        .onAppear { model.onVideoMenu = { src in onVideoMenu(src) } }
                    if model.isHome {
                        StartView(settings: settings, library: library, flowStore: flowStore, splitStore: splitStore,
                                  onSearch: { model.navigate($0); tab.activePane = i },
                                  onRunFlow: { f in onRunFlow(f, model) },
                                  onOpenSplit: onOpenSplit, onNewSplit: onNewSplit)
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
    let onBlock: () -> Void
    let onDownload: () -> Void
    let onHome: () -> Void
    let isRecording: Bool

    @State private var expanded: Set<String> = ["ブラウズ", "自動化"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("🦎 Chamaeleon").font(.system(size: 18, weight: .heavy)); Spacer() }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    category("ブラウズ", "safari") {
                        row("house", "ホーム", onHome)
                        row("rectangle.split.2x2", "分割ビュー（複数サイト）", onSplit)
                        row("arrow.down.circle", "一括ダウンロード", onDownload)
                        row("books.vertical", "ブックマーク・履歴", onLibrary)
                    }
                    category("自動化", "wand.and.stars") {
                        row("list.bullet.rectangle", "自動化フロー", onFlows)
                        row(isRecording ? "record.circle.fill" : "record.circle",
                            isRecording ? "記録を停止" : "操作を記録", onRecord, tint: isRecording ? .red : nil)
                        row("key.fill", "認証情報（端末内）", onCreds)
                    }
                    category("カスタマイズ", "paintbrush") {
                        row("paintbrush.pointed", "スタイル編集", onStyle)
                        row("slider.horizontal.3", "サイト設定", onSite)
                        row("paintpalette", "ホーム / 見た目の編集", onHomeSettings)
                    }
                    category("保護 / ブロック", "shield.lefthalf.filled") {
                        row("shield.lefthalf.filled", "広告ブロック・リクエスト制御", onBlock)
                    }
                    category("検索エンジン", "magnifyingglass") {
                        ForEach(settings.allEngines) { e in
                            Button { settings.engineId = e.id } label: {
                                HStack {
                                    Image(systemName: settings.engineId == e.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(settings.engineId == e.id ? Color(hex: settings.accentHex) : .secondary)
                                    Text(e.name).foregroundColor(.primary)
                                    Spacer()
                                }
                                .font(.system(size: 14)).padding(.horizontal, 28).padding(.vertical, 9)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func category<C: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) -> some View {
        let isOpen = expanded.contains(title)
        Button {
            withAnimation { if isOpen { expanded.remove(title) } else { expanded.insert(title) } }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundColor(.secondary)
                Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
                Spacer()
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        if isOpen { content() }
        Divider().padding(.leading, 16).opacity(0.5)
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
