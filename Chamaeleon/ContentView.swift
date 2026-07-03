import SwiftUI

struct ContentView: View {
    @StateObject private var store = ProfileStore()
    @StateObject private var library = LibraryStore()
    @State private var tabs: [BrowserModel] = []
    @State private var activeIndex = 0
    @State private var showPanel = false
    @State private var showLibrary = false
    @FocusState private var urlFocused: Bool

    private var active: BrowserModel? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex] : tabs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            navBar
            Divider()
            // 各タブのWKWebViewは生かしたまま、アクティブのみ表示
            ZStack {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, model in
                    BrowserView(model: model, store: store) { url, title in
                        library.recordVisit(url: url, title: title)
                    }
                    .opacity(index == activeIndex ? 1 : 0)
                    .allowsHitTesting(index == activeIndex)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            if tabs.isEmpty { tabs = [BrowserModel(url: library.homepage)] }
        }
        .sheet(isPresented: $showPanel) {
            if let model = active {
                SitePanelView(store: store, model: model)
            }
        }
        .sheet(isPresented: $showLibrary) {
            if let model = active {
                LibraryView(library: library, model: model)
            }
        }
    }

    // MARK: - タブバー（仕様§4.1）

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, model in
                    TabChip(model: model, isActive: index == activeIndex,
                            showClose: tabs.count > 1,
                            onSelect: { activeIndex = index },
                            onClose: { closeTab(at: index) })
                }
                Button {
                    tabs.append(BrowserModel(url: library.homepage))
                    activeIndex = tabs.count - 1
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func closeTab(at index: Int) {
        tabs.remove(at: index)
        if tabs.isEmpty {
            tabs = [BrowserModel(url: library.homepage)]
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
                       showPanel: $showPanel, showLibrary: $showLibrary,
                       urlFocused: $urlFocused)
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
            Text(model.title.isEmpty ? "New Tab" : model.title)
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
    @Binding var showLibrary: Bool
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

            // 読み込み中は停止、それ以外は更新（仕様§4.1）
            if model.isLoading {
                Button { model.webView?.stopLoading(); model.isLoading = false } label: {
                    Image(systemName: "xmark")
                }
            } else {
                Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
            }

            // ブックマーク
            Button {
                library.toggleBookmark(url: model.currentURL, title: model.title)
            } label: {
                Image(systemName: library.isBookmarked(model.currentURL) ? "star.fill" : "star")
                    .foregroundColor(library.isBookmarked(model.currentURL) ? .yellow : .accentColor)
            }

            // ライブラリ（ブックマーク・履歴・設定）
            Button { showLibrary = true } label: { Image(systemName: "books.vertical") }

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
