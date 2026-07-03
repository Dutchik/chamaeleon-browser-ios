import SwiftUI

/// ホーム: 検索エンジン選択からスタート。
struct StartView: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var library: LibraryStore
    let onSearch: (String) -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.08), .black],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer().frame(height: 40)
                Text("🦎 Chamaeleon").font(.system(size: 30, weight: .heavy)).foregroundColor(.white)

                // エンジン選択
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DEFAULT_ENGINES) { e in
                            Button { settings.engineId = e.id } label: {
                                Text(e.name).font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(settings.engineId == e.id ? Color.green : Color(white: 0.15))
                                    .foregroundColor(settings.engineId == e.id ? .black : .white)
                                    .clipShape(Capsule())
                            }
                        }
                    }.padding(.horizontal, 16)
                }

                // 検索ボックス
                HStack {
                    TextField("\(settings.engine.name) で検索、またはURL", text: $query)
                        .textFieldStyle(.plain).padding(14)
                        .background(Color(white: 0.1)).cornerRadius(12).foregroundColor(.white)
                        .keyboardType(.webSearch).autocapitalization(.none).autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit(search)
                    Button(action: search) { Text("検索").fontWeight(.bold) }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .background(Color.green).foregroundColor(.black).cornerRadius(12)
                }.padding(.horizontal, 16)

                // ブックマーク
                if !library.bookmarks.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                            ForEach(library.bookmarks.prefix(12)) { b in
                                Button { onSearch(b.url) } label: {
                                    VStack(spacing: 6) {
                                        Text(String(b.title.prefix(1)).uppercased())
                                            .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                                            .frame(width: 46, height: 46).background(Color(white: 0.15)).cornerRadius(12)
                                        Text(b.title).font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
                                    }
                                }
                            }
                        }.padding(16)
                    }
                }
                Spacer()
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if q.hasPrefix("http") || (q.contains(".") && !q.contains(" ")) {
            onSearch(q.hasPrefix("http") ? q : "https://" + q)
        } else {
            onSearch(settings.engine.searchUrl.replacingOccurrences(of: "%s",
                     with: q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q))
        }
        query = ""; focused = false
    }
}
