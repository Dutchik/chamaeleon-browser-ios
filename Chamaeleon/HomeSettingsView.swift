import SwiftUI

/// ホーム画面・ヘッダーの見た目を「選択式」で編集する設定。
struct HomeSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("アクセントカラー") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ACCENT_OPTIONS) { a in
                                Button { settings.accentId = a.id } label: {
                                    VStack(spacing: 4) {
                                        Circle().fill(Color(hex: a.hex)).frame(width: 34, height: 34)
                                            .overlay(Circle().stroke(Color.primary,
                                                lineWidth: settings.accentId == a.id ? 3 : 0))
                                        Text(a.name).font(.system(size: 10)).foregroundColor(.secondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }.padding(.vertical, 4)
                    }
                }

                Section("ホーム背景") {
                    ForEach(BG_OPTIONS) { b in
                        Button { settings.bgId = b.id } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(LinearGradient(colors: [Color(hex: b.topHex), Color(hex: b.bottomHex)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .frame(width: 40, height: 28)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                                Text(b.name).foregroundColor(.primary)
                                Spacer()
                                if settings.bgId == b.id {
                                    Image(systemName: "checkmark").foregroundColor(Color(hex: settings.accentHex))
                                }
                            }
                        }
                    }
                }

                Section("ホームの表示") {
                    TextField("あいさつ / タイトル", text: $settings.greeting)
                    Toggle("検索エンジン選択バー", isOn: $settings.showEngineBar)
                }

                Section("ウィジェット") {
                    Toggle("時計・日付", isOn: $settings.showClock)
                    Toggle("メモ", isOn: $settings.showMemo)
                    if settings.showMemo {
                        TextField("メモの内容", text: $settings.memo, axis: .vertical).lineLimit(2...5)
                    }
                }

                Section("ヘッダー（ツールバー）") {
                    Toggle("ブックマークボタン", isOn: $settings.showBookmarkButton)
                    Toggle("🦎 適用バッジ", isOn: $settings.showChameleonBadge)
                    Text("ヘッダーのボタン色は上のアクセントカラーが反映されます。")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .navigationTitle("ホーム / 見た目の編集").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
    }
}
