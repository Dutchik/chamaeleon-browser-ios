import SwiftUI

/// 操作記録のセッション（ドックの開閉に関係なく記録を継続）
@MainActor
final class RecordSession: ObservableObject {
    @Published var active = false
    @Published var paused = false
    @Published var steps: [RecordedStep] = []
    private weak var model: BrowserModel?

    func start(_ m: BrowserModel) {
        model = m; steps = []; paused = false; active = true
        m.onRecorded = { [weak self] rs in
            guard let self, !self.paused else { return }
            self.steps.append(rs)
        }
        m.startRecording()
    }
    func togglePause() {
        paused.toggle()
        if paused { model?.stopRecording() } else { model?.startRecording() }
    }
    func clear() { steps = [] }
    func stop() {
        model?.stopRecording(); model?.onRecorded = nil
        active = false; steps = []
    }
    func buildFlow() -> Flow {
        let cur = model?.currentURL ?? ""
        let host = URL(string: cur)?.host ?? cur
        var f = Flow()
        f.name = host; f.matchType = .domain; f.matchPattern = host; f.startUrl = cur
        f.steps = steps.map { rs in
            var s = FlowStep(); s.type = FlowActionType(rawValue: rs.type) ?? .click
            s.selector = rs.selector; s.value = rs.value; return s
        }
        return f
    }
}

/// 右ドックをアクティブペインに追従させるホスト
struct DockHost: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var flowStore: FlowStore
    @ObservedObject var session: RecordSession
    let accent: Color
    @Binding var expanded: Bool
    @Binding var status: String?
    let onRunFlow: (Flow, BrowserModel) -> Void
    let onSaveFlow: (Flow) -> Void

    var body: some View {
        RightDock(model: tab.active, flowStore: flowStore, session: session, accent: accent,
                  expanded: $expanded, status: $status,
                  onRunFlow: { onRunFlow($0, tab.active) }, onSaveFlow: onSaveFlow)
    }
}

/// 右側のドック: 自動化の登録ログ（操作記録）・実行できるフローを右側に「閉じて」配置し、
/// 記録開始などで右端の展開タブから開く。
struct RightDock: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var flowStore: FlowStore
    @ObservedObject var session: RecordSession
    let accent: Color
    @Binding var expanded: Bool
    @Binding var status: String?
    let onRunFlow: (Flow) -> Void
    let onSaveFlow: (Flow) -> Void

    private var matched: [Flow] { model.isHome ? [] : flowStore.matched(for: model.currentURL) }
    private var hasContent: Bool { session.active || !matched.isEmpty || status != nil }

    var body: some View {
        if hasContent {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if expanded {
                    panel.frame(width: 300).transition(.move(edge: .trailing))
                } else {
                    edgeTab.transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }

    private var edgeTab: some View {
        Button { withAnimation { expanded = true } } label: {
            VStack(spacing: 6) {
                Image(systemName: session.active ? "record.circle.fill" : "bolt.horizontal.circle.fill")
                    .font(.system(size: 18))
                if session.active {
                    Text("記録").font(.system(size: 10, weight: .bold))
                } else {
                    Text("\(matched.count)").font(.system(size: 12, weight: .bold))
                }
                Image(systemName: "chevron.left").font(.system(size: 10))
            }
            .foregroundColor(session.active ? .red : accent)
            .padding(.vertical, 12).padding(.horizontal, 7)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.15), radius: 8, x: -2)
        }
        .padding(.trailing, 6).padding(.top, 8)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.active ? "操作の記録" : "自動化").font(.system(size: 14, weight: .bold))
                Spacer()
                Button { withAnimation { expanded = false } } label: {
                    Image(systemName: "chevron.right.2").font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if session.active { recordBody }
                    if let s = status {
                        Text(s).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary).padding(.horizontal, 14)
                    }
                    if !matched.isEmpty {
                        Text("このページのフロー").font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary).padding(.horizontal, 14)
                        ForEach(matched) { f in
                            Button { onRunFlow(f) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill").font(.system(size: 11))
                                    Text(f.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(accent.opacity(0.14)).foregroundColor(accent)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(Rectangle().frame(width: 1).foregroundColor(.primary.opacity(0.08)), alignment: .leading)
    }

    // 記録本体
    private var recordBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(session.paused ? Color.gray : Color.red).frame(width: 8, height: 8)
                Text(session.paused ? "一時停止中" : "記録中").font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(session.steps.count)手順").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text("ページを操作すると手順が記録されます。").font(.system(size: 11)).foregroundColor(.secondary)

            if session.steps.isEmpty {
                Text("まだ手順がありません").font(.system(size: 12)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(session.steps.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 6) {
                            Text("\(i + 1)").font(.system(size: 10, weight: .bold))
                                .frame(width: 18, height: 18).background(accent.opacity(0.15)).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(FlowActionType(rawValue: s.type)?.title ?? s.type).font(.system(size: 12, weight: .semibold))
                                Text(s.selector ?? "").font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button { session.steps.remove(at: i) } label: {
                                Image(systemName: "minus.circle").foregroundColor(.red)
                            }.buttonStyle(.borderless)
                        }
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
            }

            HStack(spacing: 8) {
                Button { session.togglePause() } label: {
                    Image(systemName: session.paused ? "play.fill" : "pause.fill")
                }.buttonStyle(.bordered)
                Button { session.clear() } label: { Image(systemName: "trash") }
                    .buttonStyle(.bordered).disabled(session.steps.isEmpty)
                Spacer()
                Button { session.stop() } label: { Text("終了").font(.system(size: 12)) }.buttonStyle(.bordered)
            }
            Button {
                let f = session.buildFlow(); session.stop(); onSaveFlow(f)
            } label: {
                Label("フローとして保存", systemImage: "square.and.arrow.down").font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(accent).disabled(session.steps.isEmpty)
        }
        .padding(.horizontal, 14)
    }
}
