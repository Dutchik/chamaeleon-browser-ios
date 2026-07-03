import SwiftUI

/// ライブラリ: ブックマーク・履歴・設定（仕様§4.1）
struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case bookmarks = "ブックマーク"
        case history = "履歴"
        case settings = "設定"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .bookmarks
    @State private var search = ""
    @State private var homepageInput = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14).padding(.vertical, 8)

                switch tab {
                case .bookmarks: bookmarkList
                case .history: historyList
                case .settings: settingsList
                }
            }
            .navigationTitle("ライブラリ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .onAppear { homepageInput = library.homepage }
        }
    }

    private var bookmarkList: some View {
        List {
            ForEach(library.bookmarks) { b in
                Button {
                    model.navigate(b.url)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(b.url).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .foregroundColor(.primary)
            }
            .onDelete { library.bookmarks.remove(atOffsets: $0) }
            if library.bookmarks.isEmpty {
                Text("ブックマークはまだありません。ナビバーの ☆ で追加できます。")
                    .font(.system(size: 13)).foregroundColor(.secondary)
            }
        }
        .listStyle(.plain)
    }

    private var historyList: some View {
        List {
            Section {
                ForEach(filteredHistory.prefix(200)) { h in
                    Button {
                        model.navigate(h.url)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.title.isEmpty ? h.url : h.title)
                                .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(h.url).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    .foregroundColor(.primary)
                }
            } header: {
                if !library.history.isEmpty {
                    Button("履歴を全消去", role: .destructive) { library.history = [] }
                        .font(.system(size: 12))
                }
            }
            if library.history.isEmpty {
                Text("履歴はありません。").font(.system(size: 13)).foregroundColor(.secondary)
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "タイトル・URLで検索")
    }

    private var filteredHistory: [HistoryEntry] {
        guard !search.isEmpty else { return library.history }
        return library.history.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.url.contains(search) }
    }

    private var settingsList: some View {
        List {
            Section {
                TextField("https://duckduckgo.com", text: $homepageInput)
                    .keyboardType(.URL).autocapitalization(.none).autocorrectionDisabled()
                Button("保存") { library.homepage = homepageInput }
            } header: {
                Text("ホームページ（新しいタブで開くURL）")
            }
        }
        .listStyle(.insetGrouped)
    }
}
