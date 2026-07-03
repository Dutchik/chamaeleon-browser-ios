import SwiftUI

/// ホームの月表示カレンダー。履歴のある日にはドット。日をタップするとその日の履歴をポップアップ表示。
struct CalendarWidget: View {
    @ObservedObject var library: LibraryStore
    let accent: Color
    let onOpen: (String) -> Void

    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var buckets: [Date: [HistoryEntry]] = [:]
    @State private var selection: DaySelection?

    private let cal = Calendar.current
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(spacing: 8) {
            header
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { w in
                    Text(w).font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5)).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    dayCell(day)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06)).cornerRadius(14).padding(.horizontal, 16)
        .onAppear(perform: rebuild)
        .onChange(of: library.history.count) { _ in rebuild() }
        .sheet(item: $selection) { sel in
            DayHistoryView(date: sel.date, entries: entries(sel.date), accent: accent, onOpen: onOpen)
        }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
        }
        .foregroundColor(accent)
    }

    @ViewBuilder private func dayCell(_ day: Date?) -> some View {
        if let day {
            let has = buckets[cal.startOfDay(for: day)] != nil
            let isToday = cal.isDateInToday(day)
            Button { selection = DaySelection(date: day) } label: {
                VStack(spacing: 2) {
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 12, weight: isToday ? .bold : .regular))
                        .foregroundColor(isToday ? .black : .white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(isToday ? accent : Color.clear)
                        .clipShape(Circle())
                    Circle().fill(has ? accent : Color.clear).frame(width: 5, height: 5)
                }
            }
            .disabled(!has && !isToday ? false : false) // 常にタップ可（履歴無しの日も空表示）
        } else {
            Color.clear.frame(height: 33)
        }
    }

    // MARK: - データ

    private var monthTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "yyyy年 M月"
        return f.string(from: month)
    }
    private var cells: [Date?] {
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps), let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let leading = cal.component(.weekday, from: first) - 1
        var out: [Date?] = Array(repeating: nil, count: leading)
        for d in range { out.append(cal.date(byAdding: .day, value: d - 1, to: first)) }
        return out
    }
    private func shift(_ n: Int) {
        if let m = cal.date(byAdding: .month, value: n, to: month) { month = m }
    }
    private func entries(_ day: Date) -> [HistoryEntry] { buckets[cal.startOfDay(for: day)] ?? [] }
    private func rebuild() {
        let f = ISO8601DateFormatter()
        var m: [Date: [HistoryEntry]] = [:]
        for e in library.history {
            if let d = f.date(from: e.visitedAt) { m[cal.startOfDay(for: d), default: []].append(e) }
        }
        buckets = m
    }
}

struct DaySelection: Identifiable { let id = UUID(); let date: Date }

/// 選択日の履歴ポップアップ
struct DayHistoryView: View {
    let date: Date
    let entries: [HistoryEntry]
    let accent: Color
    let onOpen: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.badge.xmark").font(.system(size: 34)).foregroundColor(.secondary)
                        Text("この日の履歴はありません").foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(entries) { e in
                        Button {
                            onOpen(e.url); dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title.isEmpty ? e.url : e.title).font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(timeString(e)).font(.system(size: 11)).foregroundColor(accent)
                                    Text(e.url).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private var title: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M月d日(E)"
        return f.string(from: date)
    }
    private func timeString(_ e: HistoryEntry) -> String {
        guard let d = ISO8601DateFormatter().date(from: e.visitedAt) else { return "" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
