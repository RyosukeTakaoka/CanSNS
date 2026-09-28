import SwiftUI

/// 冷蔵庫（アーカイブ）
/// - じぶんの缶：翌朝6:00に自販機から廃棄された自分の投稿が、自動でここに入る
/// - もらった缶：友達の缶のうち、自分で冷蔵庫に入れたもの（自分にしか見えない）
struct FridgeView: View {
    @Environment(AppStore.self) private var store
    @State private var shelf: Shelf = .own
    @State private var selected: CanPost?

    enum Shelf: String, CaseIterable, Identifiable {
        case own = "じぶんの缶"
        case saved = "もらった缶"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            let userID = store.currentUserID ?? ""
            let contents = store.db.fridgeCans(for: userID, today: store.today)
            let cans = shelf == .own ? contents.own : contents.saved

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("棚", selection: $shelf) {
                        ForEach(Shelf.allCases) { shelf in
                            Text(shelf.rawValue).tag(shelf)
                        }
                    }
                    .pickerStyle(.segmented)

                    if cans.isEmpty {
                        emptyView
                    } else {
                        ForEach(groupByDay(cans)) { group in
                            shelfRow(day: group.day, cans: group.cans)
                        }
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(colors: [Theme.fridgeInside, Color.white], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationTitle("冷蔵庫")
            .sheet(item: $selected) { can in
                NavigationStack {
                    CanContentView(can: can)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("とじる") { selected = nil }
                            }
                            if can.authorID != userID {
                                ToolbarItem(placement: .destructiveAction) {
                                    Button("冷蔵庫から出す", role: .destructive) {
                                        store.removeFromFridge(can)
                                        selected = nil
                                    }
                                }
                            }
                        }
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "refrigerator")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(shelf == .own
                 ? "まだ空っぽです。\n自販機の缶は翌朝6:00に廃棄されると、ここに入ります。"
                 : "まだ空っぽです。\n開けた友達の缶を「冷蔵庫に入れる」と、ここに残せます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func shelfRow(day: BusinessDay, cans: [CanPost]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.shortText)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(cans) { can in
                    Button {
                        selected = can
                    } label: {
                        VStack(spacing: 4) {
                            CanView(can: can, emoji: store.user(can.authorID)?.emoji ?? "🙂", width: 52,
                                    showsKind: !can.isContentHidden)
                            Text(store.user(can.authorID)?.name ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            // 冷蔵庫の棚板
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [Color.white, Color(hex: 0xB9D3E0)], startPoint: .top, endPoint: .bottom))
                .frame(height: 8)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 2)
        }
    }

    private struct DayGroup: Identifiable {
        var day: BusinessDay
        var cans: [CanPost]
        var id: String { day.key }
    }

    private func groupByDay(_ cans: [CanPost]) -> [DayGroup] {
        let grouped = Dictionary(grouping: cans) { $0.businessDay }
        return grouped.keys.sorted(by: >).map { day in DayGroup(day: day, cans: grouped[day] ?? []) }
    }
}

/// お知らせ（開封・リアクション・ストロー・手紙・冷蔵庫・メンバー参加）
struct NotificationsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            let items = store.db.notifications(for: store.currentUserID ?? "")
            Group {
                if items.isEmpty {
                    ContentUnavailableView("お知らせはまだありません",
                                           systemImage: "bell",
                                           description: Text("友達があなたの缶を開けると、ここに届きます"))
                } else {
                    List(items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Text(store.user(item.actorID)?.emoji ?? "🙂")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.message)
                                    .font(.subheadline)
                                Text(DateText.monthDayTime(item.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !item.isRead {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("お知らせ")
            .task {
                // 1.5秒見たら既読にする
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                store.markAllRead()
            }
        }
    }
}
