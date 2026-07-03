import SwiftUI

/// ホーム: 検索エンジン選択＋自動化ランチャー＋分割ビュー＋ウィジェット＋ブックマーク。
/// 見た目は AppSettingsStore（選択式編集）で切替。
struct StartView: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var library: LibraryStore
    @ObservedObject var flowStore: FlowStore
    @ObservedObject var splitStore: SplitStore
    let onSearch: (String) -> Void
    let onRunFlow: (Flow) -> Void
    let onOpenSplit: (SplitConfig) -> Void
    let onNewSplit: () -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    private var pinnedFlows: [Flow] { flowStore.flows.filter { $0.pinnedToHome } }
    private var pinnedSplits: [SplitConfig] { splitStore.configs.filter { $0.pinnedToHome } }
    private var accent: Color { Color(hex: settings.accentHex) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: settings.bg.topHex), Color(hex: settings.bg.bottomHex)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer().frame(height: 28)
                Text(settings.greeting).font(.system(size: 28, weight: .heavy)).foregroundColor(.white)

                // ウィジェット
                if settings.showClock { ClockWidget(accent: accent) }
                if settings.showMemo, !settings.memo.isEmpty { MemoWidget(text: settings.memo) }

                // エンジン選択
                if settings.showEngineBar {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DEFAULT_ENGINES) { e in
                                Button { settings.engineId = e.id } label: {
                                    Text(e.name).font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .background(settings.engineId == e.id ? accent : Color(white: 0.15))
                                        .foregroundColor(settings.engineId == e.id ? .black : .white)
                                        .clipShape(Capsule())
                                }
                            }
                        }.padding(.horizontal, 16)
                    }
                }

                // 検索
                HStack {
                    TextField("\(settings.engine.name) で検索、またはURL", text: $query)
                        .textFieldStyle(.plain).padding(14)
                        .background(Color(white: 0.1)).cornerRadius(12).foregroundColor(.white)
                        .keyboardType(.webSearch).autocapitalization(.none).autocorrectionDisabled()
                        .focused($focused).onSubmit(search)
                    Button(action: search) { Text("検索").fontWeight(.bold) }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .background(accent).foregroundColor(.black).cornerRadius(12)
                }.padding(.horizontal, 16)

                ScrollView {
                    // 自動化（固定フロー）
                    if !pinnedFlows.isEmpty {
                        sectionHeader("自動化")
                        grid {
                            ForEach(pinnedFlows) { f in
                                launcher(title: f.name.isEmpty ? "フロー" : f.name,
                                         icon: f.promptSteps.isEmpty ? "bolt.fill" : "square.and.pencil",
                                         colors: [accent, accent.opacity(0.55)]) { onRunFlow(f) }
                            }
                        }
                    }

                    // 分割ビュー
                    sectionHeader("分割ビュー")
                    grid {
                        ForEach(pinnedSplits) { s in
                            launcher(title: s.name.isEmpty ? "分割" : s.name,
                                     icon: s.layout.systemImage,
                                     colors: [Color(white: 0.22), Color(white: 0.12)]) { onOpenSplit(s) }
                        }
                        launcher(title: "新規分割", icon: "plus", colors: [Color(white: 0.18), Color(white: 0.1)],
                                 dashed: true) { onNewSplit() }
                    }

                    // ブックマーク
                    if !library.bookmarks.isEmpty {
                        sectionHeader("ブックマーク")
                        grid {
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
                        }
                    }
                    Spacer().frame(height: 20)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - パーツ

    private func grid<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) { content() }
            .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private func launcher(title: String, icon: String, colors: [Color], dashed: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                        .frame(width: 46, height: 46)
                    if dashed {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .foregroundColor(.white.opacity(0.4)).frame(width: 46, height: 46)
                    }
                    Image(systemName: icon).font(.system(size: 19, weight: .bold)).foregroundColor(.white)
                }
                Text(title).font(.system(size: 11)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.6))
            Spacer()
        }.padding(.horizontal, 16).padding(.top, 8)
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

// MARK: - ウィジェット

private struct ClockWidget: View {
    let accent: Color
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            VStack(spacing: 2) {
                Text(ctx.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundColor(.white)
                Text(ctx.date, format: .dateTime.year().month().day().weekday())
                    .font(.system(size: 12)).foregroundColor(accent)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color.white.opacity(0.06)).cornerRadius(14).padding(.horizontal, 16)
        }
    }
}

private struct MemoWidget: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "note.text").foregroundColor(.yellow)
            Text(text).font(.system(size: 13)).foregroundColor(.white.opacity(0.9))
            Spacer()
        }
        .padding(12).background(Color.white.opacity(0.06)).cornerRadius(14).padding(.horizontal, 16)
    }
}
