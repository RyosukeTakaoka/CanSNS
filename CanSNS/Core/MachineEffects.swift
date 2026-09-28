import Foundation

/// 条件を達成したときだけ出る、シェアしたくなる限定演出。
/// （運まかせのガチャではなく、みんなで達成するタイプ）
enum MachineEffect: String, CaseIterable, Identifiable {
    /// グループ全員が納品した日
    case fullStock
    /// 全員が1回ずつ（自分以外の缶を）開封した日
    case allPurchased
    /// 7日連続で納品があった日
    case limitedNeon
    /// 初めて参加したメンバーがいる日
    case newArrival

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullStock: "満タン！"
        case .allPurchased: "全員購入済み"
        case .limitedNeon: "限定ネオン点灯中"
        case .newArrival: "新商品入荷"
        }
    }

    var detail: String {
        switch self {
        case .fullStock: "今日は全員が納品しました"
        case .allPurchased: "全員が友達の缶を開けました"
        case .limitedNeon: "\(MachineEffect.neonStreakDays)日連続で納品が続いています"
        case .newArrival: "新しい仲間が加わりました"
        }
    }

    var emoji: String {
        switch self {
        case .fullStock: "🥫"
        case .allPurchased: "🎉"
        case .limitedNeon: "🌈"
        case .newArrival: "✨"
        }
    }

    static let neonStreakDays = 7
}

/// 自販機の成長（これまでの納品数でレベルが上がる）
enum MachineGrowth {
    /// レベルアップに必要な累計納品数
    static let thresholds = [0, 5, 15, 30, 60, 100, 150, 220, 300, 400]

    static func level(totalCans: Int) -> Int {
        thresholds.lastIndex { totalCans >= $0 }.map { $0 + 1 } ?? 1
    }

    /// 次のレベルまでの進み具合（0〜1）と、あと何本か
    static func progress(totalCans: Int) -> (fraction: Double, remaining: Int)? {
        let lv = level(totalCans: totalCans)
        guard lv < thresholds.count else { return nil }
        let current = thresholds[lv - 1]
        let next = thresholds[lv]
        let fraction = Double(totalCans - current) / Double(next - current)
        return (fraction, next - totalCans)
    }

    static func title(for level: Int) -> String {
        switch level {
        case 1: "路地裏の自販機"
        case 2: "通学路の自販機"
        case 3: "ちょっと人気の自販機"
        case 4: "駅前の自販機"
        case 5: "ネオン街の自販機"
        case 6...8: "伝説の自販機"
        default: "宇宙一の自販機"
        }
    }
}

extension AppDatabase {
    func totalCans(in machineID: String) -> Int {
        // サーバーから最近の缶だけ受け取っている場合もあるので、記録された累計と比べて大きいほう
        let counted = cans.filter { $0.machineID == machineID }.count
        return max(counted, machine(machineID)?.deliveredCount ?? 0)
    }

    /// `day` を含めて、さかのぼって何日連続で納品があったか
    func deliveryStreak(machineID: String, endingAt day: BusinessDay, clock: BusinessClock) -> Int {
        let deliveredDays = Set(cans.filter { $0.machineID == machineID }.map(\.businessDay))
        var streak = 0
        var cursor = day
        while deliveredDays.contains(cursor) {
            streak += 1
            cursor = clock.day(cursor, offsetBy: -1)
        }
        return streak
    }

    /// その営業日に達成している演出の一覧
    func effects(machineID: String, day: BusinessDay, clock: BusinessClock) -> [MachineEffect] {
        guard let machine = self.machine(machineID) else { return [] }
        let todays = cans(in: machineID, on: day)
        let authors = Set(todays.map(\.authorID))
        let members = machine.memberIDs
        var result: [MachineEffect] = []

        if members.count >= 2, members.allSatisfy({ authors.contains($0) }) {
            result.append(.fullStock)
        }

        let todaysIDs = Set(todays.map(\.id))
        let everyoneOpened = members.allSatisfy { member in
            openings.contains { opening in
                opening.userID == member && todaysIDs.contains(opening.canID)
            }
        }
        if members.count >= 2, authors.count >= 2, everyoneOpened {
            result.append(.allPurchased)
        }

        if deliveryStreak(machineID: machineID, endingAt: day, clock: clock) >= MachineEffect.neonStreakDays {
            result.append(.limitedNeon)
        }

        let start = clock.deliveryStart(of: day)
        let end = clock.disposalTime(of: day)
        // 自販機を作った人（先頭）は「新メンバー」に数えない
        let hasNewcomer = machine.members.dropFirst().contains { $0.joinedAt >= start && $0.joinedAt < end }
        if hasNewcomer {
            result.append(.newArrival)
        }
        return result
    }
}
