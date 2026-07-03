import SwiftUI

/// 操作記録のセッション（右パネルの開閉に関係なく記録を継続）
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

/// 右パネルをアクティブペインに追従させるホスト
struct DockHost: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var store: ProfileStore
    @ObservedObject var session: RecordSession
    let accent: Color
    let editorIsStyle: Bool
    @Binding var expanded: Bool
    let onCloseStyle: () -> Void
    let onCloseRecord: () -> Void
    let onSaveFlow: (Flow) -> Void

    var body: some View {
        RightDock(model: tab.active, store: store, session: session, accent: accent,
                  editorIsStyle: editorIsStyle, expanded: $expanded,
                  onCloseStyle: onCloseStyle, onCloseRecord: onCloseRecord, onSaveFlow: onSaveFlow)
    }
}

/// 右側パネル: 自動化の登録内容（操作記録）や CSS/スタイル設定の入力エリア。
/// 閉じている間は右端の展開タブ、要素選択時は自動で畳んでページを見せる。
struct RightDock: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var store: ProfileStore
    @ObservedObject var session: RecordSession
    let accent: Color
    let editorIsStyle: Bool
    @Binding var expanded: Bool
    let onCloseStyle: () -> Void
    let onCloseRecord: () -> Void
    let onSaveFlow: (Flow) -> Void

    private var hasContent: Bool { session.active || editorIsStyle }
    private var title: String { editorIsStyle ? "🎨 スタイル編集" : "⏺ 操作の記録" }
    private var edgeIcon: String { editorIsStyle ? "paintbrush.pointed.fill" : "record.circle.fill" }
    private var edgeColor: Color { editorIsStyle ? accent : .red }

    var body: some View {
        if hasContent {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if expanded {
                    panel.frame(width: 320).transition(.move(edge: .trailing))
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
                Image(systemName: edgeIcon).font(.system(size: 18))
                Text(editorIsStyle ? "編集" : "記録").font(.system(size: 10, weight: .bold))
                Image(systemName: "chevron.left").font(.system(size: 10))
            }
            .foregroundColor(edgeColor)
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
                Text(title).font(.system(size: 14, weight: .bold))
                Spacer()
                Button { withAnimation { expanded = false } } label: {
                    Image(systemName: "chevron.right.2").font(.system(size: 14, weight: .semibold))
                }
                Button { editorIsStyle ? onCloseStyle() : onCloseRecord() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            if editorIsStyle {
                StyleEditorBody(store: store, model: model, accent: accent, expanded: $expanded, onClose: onCloseStyle)
            } else {
                ScrollView { recordBody.padding(.vertical, 12) }
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(Rectangle().frame(width: 1).foregroundColor(.primary.opacity(0.08)), alignment: .leading)
    }

    // 記録本体（何を登録しているか＝手順を可視化）
    private var recordBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(session.paused ? Color.gray : Color.red).frame(width: 8, height: 8)
                Text(session.paused ? "一時停止中" : "記録中").font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(session.steps.count)手順").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text("ページを操作すると、登録される手順がここに表示されます。")
                .font(.system(size: 11)).foregroundColor(.secondary)

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
                                if let v = s.value, !v.isEmpty {
                                    Text("値: \(v)").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                                }
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
