import SwiftUI

/// 広告ブロック・リクエスト制御・要素非表示の管理（iOS）
struct BlockRulesView: View {
    @ObservedObject var netRules: NetRuleStore
    @ObservedObject var model: BrowserModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    @State private var newPattern = ""
    @State private var newAction: NetAction = .block
    @State private var newSelector = ""
    @State private var scopeToSite = true
    @State private var picking = false
    @State private var linkTarget = ""
    @State private var linkScopeToSite = false

    private var host: String { URL(string: model.currentURL)?.host ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("ブロックを有効にする", isOn: $netRules.masterEnabled)
                    Text("広告等のリクエストを遮断（メインフレームはC判定エンジン、サブリソースはWKContentRuleList）。要素は描画前に css-display-none で非表示。変更は再読み込みで反映されます。")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }

                Section("ルールを追加") {
                    Picker("種類", selection: $newAction) {
                        ForEach(NetAction.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)

                    if newAction == .block {
                        TextField("URLに含まれる文字（例: doubleclick.net, /ads/）", text: $newPattern)
                            .font(.system(size: 13, design: .monospaced))
                            .autocapitalization(.none).autocorrectionDisabled()
                        Button("ブロックルールを追加") { netRules.addBlock(newPattern); newPattern = "" }
                            .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        HStack {
                            TextField("CSSセレクタ（例: .ad, #banner）", text: $newSelector)
                                .font(.system(size: 13, design: .monospaced))
                                .autocapitalization(.none).autocorrectionDisabled()
                            Button {
                                picking = true
                                model.onInspected = { info in newSelector = info.selector; picking = false }
                                model.startInspect()
                            } label: { Image(systemName: "target") }.buttonStyle(.borderless)
                        }
                        if picking { Text("ページ上の要素をタップ").font(.caption).foregroundColor(accent) }
                        Toggle("このサイト（\(host)）だけに適用", isOn: $scopeToSite)
                        Button("非表示ルールを追加") {
                            netRules.addHide(selector: newSelector, domain: scopeToSite ? host : nil); newSelector = ""
                        }.disabled(newSelector.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    TextField("行きたくない宛先（例: example.com、affiliate.jp/ref）", text: $linkTarget)
                        .font(.system(size: 13, design: .monospaced))
                        .autocapitalization(.none).autocorrectionDisabled()
                    Toggle("このサイト（\(host)）内のリンクだけ", isOn: $linkScopeToSite)
                    Button("この宛先へのリンクを一括で隠す＋移動をブロック") {
                        netRules.addLinkTargetBlock(linkTarget, domain: linkScopeToSite ? host : nil); linkTarget = ""
                    }.disabled(linkTarget.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: { Text("リンク先ブロック") }
                footer: { Text("入力した宛先へのリンク要素（[href*=…]）をページから一括で隠し、その宛先へのナビゲーションもブロックします。誤クリックで離脱したくないサイトに。") }

                Section("登録済みルール（\(netRules.rules.count)）") {
                    ForEach($netRules.rules) { $r in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $r.enabled).labelsHidden()
                            Image(systemName: r.action == .block ? "hand.raised.slash" : "eye.slash")
                                .foregroundColor(r.action == .block ? .red : accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.action == .block ? r.pattern : (r.selector ?? ""))
                                    .font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                Text(r.action == .block ? "ブロック"
                                     : "非表示" + (r.domain.map { " · \($0)" } ?? " · 全サイト"))
                                    .font(.system(size: 10)).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .onDelete { netRules.rules.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("広告ブロック / 保護").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
    }
}
