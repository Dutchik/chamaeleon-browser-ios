import SwiftUI

struct ContentView: View {
    @StateObject private var store = ProfileStore()
    @StateObject private var model = BrowserModel()
    @State private var showPanel = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ナビゲーションバー
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
                    .focused($urlFocused)
                    .onSubmit {
                        model.navigate(model.urlInput)
                        urlFocused = false
                    }

                Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }

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

            Divider()

            BrowserView(model: model, store: store)
                .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showPanel) {
            SitePanelView(store: store, model: model)
        }
    }
}
