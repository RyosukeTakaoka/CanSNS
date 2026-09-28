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
                    header
                    PixelTabs(options: [(Shelf.own, Shelf.own.rawValue), (Shelf.saved, Shelf.saved.rawValue)],
                              selection: $shelf)

                    if cans.isEmpty {
                        emptyView
                    } else {
                        ForEach(groupByDay(cans)) { group in
                            shelfRow(day: group.day, cans: group.cans)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            .background(FridgeInteriorView().ignoresSafeArea())
            // 上の帯は庫内と同じ明るい色で固定（ダークモードでも時計などが読めるように、文字は黒）
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: 0xEAF8FC), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("冷蔵庫")
                    .font(.pixel(28))
                    .foregroundStyle(Pixel.ink)
                Text("廃棄されたあとも、ここで冷やしておける")
                    .font(.pixel(12))
                    .foregroundStyle(Pixel.ink.opacity(0.6))
            }
            Spacer(minLength: 0)
            // 冷蔵庫の温度表示（飾り）
            Text("4℃")
                .font(.pixel(18, fixed: true))
                .accessibilityHidden(true)
                .foregroundStyle(Color(hex: 0x7CF0FF))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PixelFrame(fill: Color(hex: 0x16303A), border: Pixel.ink, borderWidth: 3, step: 3))
        }
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    EmptyCanView(width: 34, tint: Color(hex: 0x3F6B7A))
                }
            }
            Text(shelf == .own
                 ? "まだ空っぽです。\n自販機の缶は翌朝6:00に廃棄されると、ここに入ります。"
                 : "まだ空っぽです。\n開けた友達の缶を「冷蔵庫に入れる」と、ここに残せます。")
                .font(.pixel(14))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            FridgeShelf()
        }
        .pixelPaper(fill: Color.white.opacity(0.85), border: Color(hex: 0x3F6B7A))
        .padding(.top, 24)
    }

    private func shelfRow(day: BusinessDay, cans: [CanPost]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // マスキングテープ風の日付ラベル
            Text(day.shortText)
                .font(.pixel(14))
                .foregroundStyle(Pixel.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color(hex: 0xFFE9A8).opacity(0.95))
                .overlay(Rectangle().strokeBorder(Pixel.ink.opacity(0.5), lineWidth: 1.5))
                .rotationEffect(.degrees(-2))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(cans) { can in
                    Button {
                        selected = can
                    } label: {
                        VStack(spacing: 4) {
                            CanView(can: can, emoji: store.user(can.authorID)?.emoji ?? "🙂", width: 50,
                                    showsKind: !can.isContentHidden)
                            Text(store.user(can.authorID)?.name ?? "")
                                .font(.pixel(11))
                                .foregroundStyle(Pixel.ink.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            FridgeShelf()
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

/// 冷蔵庫の庫内（ドット絵）：ひんやりした水色の壁・上の庫内灯・左右のドアのふち
struct FridgeInteriorView: View {
    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let p: CGFloat = 3
            func fill(_ rect: CGRect, _ color: Color) {
                context.fill(Path(rect), with: .color(color))
            }
            // 庫内の壁（上ほど明るい、段々の色帯）
            let bands = 8
            let bandHeight = (size.height / CGFloat(bands) / p).rounded(.up) * p
            for index in 0..<bands {
                let t = Double(index) / Double(bands - 1)
                let color = Color(rgb: RGB(hex: 0xEAF8FC).mixed(with: RGB(hex: 0xC4E3EE), amount: t))
                fill(CGRect(x: 0, y: CGFloat(index) * bandHeight, width: size.width, height: bandHeight + 1), color)
            }
            // 奥の壁の縦のみぞ
            var x: CGFloat = 36
            while x < size.width - 20 {
                fill(CGRect(x: x, y: 0, width: p, height: size.height), Color(hex: 0xB3D6E3).opacity(0.6))
                x += 48
            }
            // 上の庫内灯と、その光
            let lampWidth = min(120, size.width * 0.35)
            let lampX = (size.width - lampWidth) / 2
            fill(CGRect(x: lampX - p * 6, y: 0, width: lampWidth + p * 12, height: p * 10),
                 Color(hex: 0xFFF6C8).opacity(0.35))
            fill(CGRect(x: lampX, y: 0, width: lampWidth, height: p * 4), Color(hex: 0xFFE27A))
            fill(CGRect(x: lampX, y: p * 4, width: lampWidth, height: p), Color(hex: 0xC9A640))
            // 左右のドアのふち（冷蔵庫の本体）
            let edge: CGFloat = 12
            fill(CGRect(x: 0, y: 0, width: edge, height: size.height), Color(hex: 0xF4F1E4))
            fill(CGRect(x: edge, y: 0, width: p, height: size.height), Pixel.ink)
            fill(CGRect(x: size.width - edge, y: 0, width: edge, height: size.height), Color(hex: 0xF4F1E4))
            fill(CGRect(x: size.width - edge - p, y: 0, width: p, height: size.height), Pixel.ink)
        }
        .background(Color(hex: 0xD6EEF5))
        .accessibilityHidden(true)
    }
}

/// ガラスの棚板（ドット絵）
struct FridgeShelf: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.white.frame(height: 2)
            Color(hex: 0xBFE6F2).frame(height: 5)
            Color(hex: 0x7FA9B8).frame(height: 3)
            Pixel.ink.opacity(0.7).frame(height: 2)
        }
        .padding(.horizontal, -6)
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
            // 1.5秒見たら既読にする（すぐにタブを離れたら未読のまま。見ている間に届いた分も既読にする）
            .task(id: store.unreadCount) {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                store.markAllRead()
            }
        }
    }
}
