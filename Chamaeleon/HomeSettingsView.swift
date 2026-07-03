import SwiftUI
import PhotosUI

/// ホーム画面・ヘッダーの見た目を「選択式」で編集する設定。
struct HomeSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var newEngineName = ""
    @State private var newEngineUrl = ""

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
                                if settings.bgId == b.id, !settings.useCustomBg {
                                    Image(systemName: "checkmark").foregroundColor(Color(hex: settings.accentHex))
                                }
                            }
                        }
                    }
                }

                Section {
                    if settings.useCustomBg {
                        HStack {
                            Image(systemName: "photo").foregroundColor(Color(hex: settings.accentHex))
                            Text("カスタム画像を使用中")
                            Spacer()
                            Button("解除", role: .destructive) { settings.clearBgImage() }
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(settings.useCustomBg ? "画像を変更" : "背景に画像を設定", systemImage: "photo.badge.plus")
                    }
                } header: { Text("背景画像") }
                footer: { Text("端末内の画像をホーム背景に設定できます。画像はこの端末内にのみ保存されます。") }

                Section("ホームの表示") {
                    TextField("あいさつ / タイトル", text: $settings.greeting)
                    Toggle("検索エンジン選択バー", isOn: $settings.showEngineBar)
                }

                Section {
                    ForEach(DEFAULT_ENGINES) { e in
                        HStack {
                            Text(e.name); Spacer()
                            Text("標準").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    ForEach(settings.customEngines) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.system(size: 14, weight: .semibold))
                            Text(e.searchUrl).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    .onDelete { idx in idx.map { settings.customEngines[$0].id }.forEach(settings.removeEngine) }

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("エンジン名（例: 楽天）", text: $newEngineName)
                        TextField("検索URL（%s が検索語に置換）", text: $newEngineUrl)
                            .font(.system(size: 12, design: .monospaced))
                            .autocapitalization(.none).autocorrectionDisabled()
                        Button {
                            let name = newEngineName.trimmingCharacters(in: .whitespaces)
                            let url = newEngineUrl.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty, url.contains("%s") else { return }
                            settings.addEngine(name: name, searchUrl: url)
                            newEngineName = ""; newEngineUrl = ""
                        } label: { Label("エンジンを追加", systemImage: "plus") }
                        .disabled(newEngineName.trimmingCharacters(in: .whitespaces).isEmpty || !newEngineUrl.contains("%s"))
                    }
                } header: { Text("検索エンジン（任意登録）") }
                footer: { Text("例: https://www.google.com/search?q=%s のように、検索語の位置を %s で指定します。") }

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
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        settings.setBgImage(data)
                    }
                }
            }
        }
    }
}
