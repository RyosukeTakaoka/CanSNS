import Foundation

/// 1人でも動きを試せるように、デモ用の「友達ボット」と缶を用意する。
enum DemoSeeder {
    static let friends: [(name: String, emoji: String)] = [
        ("みさき", "🐱"),
        ("そうた", "🐶"),
        ("ゆい", "🐰"),
    ]

    static let sampleCans: [(title: String, text: String, mood: Mood, pattern: LabelPattern)] = [
        ("部活おわり", "今日の夕焼け、なんか好きだった", .hot, .wave),
        ("小テスト", "範囲まちがえてた🫠 明日から本気出す", .fizzy, .dots),
        ("帰り道", "コンビニの新作プリンうまかった", .cold, .stripe),
        ("雨", "傘わすれて全力ダッシュした", .fizzy, .plain),
        ("図書室", "静かすぎて逆に集中できなかった", .cold, .dots),
        ("ねむい", "5限の数学、記憶がない", .cold, .wave),
        ("推し", "新曲がよすぎて3回泣いた", .hot, .stripe),
        ("おなかすいた", "今日の給食カレーだった🍛", .hot, .plain),
        ("ちょっとだけ", "朝いつもより早く起きれた", .cold, .plain),
        ("びっくり", "駅で小学校の友達に会った！", .fizzy, .wave),
    ]

    static let sampleLetters = ["わかる〜", "それな", "明日話そ！", "おつかれ〜", "天才では"]

    /// デモ用の自販機を作り、自分と友達ボット3人を入れる。
    /// 過去6日分の納品と、今日の友達3人分の缶も入れておく。
    @discardableResult
    static func seed(into db: inout AppDatabase, me: String, now: Date, clock: BusinessClock) -> Machine {
        let today = clock.businessDay(for: now)
        let createdAt = clock.deliveryStart(of: clock.day(today, offsetBy: -7))
        var machine = db.createMachine(name: "放課後の自販機", ownerID: me, now: createdAt)
        let bots = friends.map { db.createUser(name: $0.name, emoji: $0.emoji, now: createdAt, isDemo: true) }
        if let index = db.machines.firstIndex(where: { $0.id == machine.id }) {
            for bot in bots {
                db.machines[index].members.append(Membership(userID: bot.id, joinedAt: createdAt))
            }
            machine = db.machines[index]
        }

        // 過去6日分：友達の缶と、自分の缶（→廃棄されて冷蔵庫に入っている）
        for offset in 1...6 {
            let day = clock.day(today, offsetBy: -offset)
            let deliveredAt = clock.date(of: day, hour: 17)
            let bot = bots[offset % bots.count]
            let friendCan = try? db.deliver(draft(index: offset), authorID: bot.id, machineID: machine.id,
                                            now: deliveredAt, clock: clock)
            if offset <= 2 {
                _ = try? db.deliver(draft(index: offset + 5), authorID: me, machineID: machine.id,
                                now: deliveredAt.addingTimeInterval(600), clock: clock)
            }
            // 昨日の友達の缶を1本、冷蔵庫に入れておく
            if offset == 1, let friendCan {
                let openedAt = clock.date(of: day, hour: 22)
                try? db.open(canID: friendCan.id, userID: me, now: openedAt, clock: clock)
                try? db.saveToFridge(canID: friendCan.id, userID: me, now: openedAt, clock: clock)
            }
        }

        // 過去の日のお知らせは消しておく（今日の分だけ残す）
        let todayStart = clock.deliveryStart(of: today)
        db.notifications.removeAll { $0.createdAt < todayStart }

        // 今日の友達の缶（開店前でもラベルは見える）
        deliverFromFriends(in: &db, machineID: machine.id, now: now, clock: clock)
        return machine
    }

    /// まだ今日納品していない友達ボットに納品してもらう
    static func deliverFromFriends(in db: inout AppDatabase, machineID: String, now: Date, clock: BusinessClock) {
        guard let machine = db.machine(machineID) else { return }
        let today = clock.businessDay(for: now)
        let bots = machine.memberIDs.compactMap { db.user($0) }.filter(\.isDemo)
        for (index, bot) in bots.enumerated() where db.cans(in: machineID, by: bot.id, on: today).isEmpty {
            let seedIndex = today.day + index * 3
            // 少しずつ時間をずらして納品したことにする（未来の時刻にはしない）
            let deliveredAt = max(clock.deliveryStart(of: today), now.addingTimeInterval(Double(-600 * (index + 1))))
            _ = try? db.deliver(draft(index: seedIndex), authorID: bot.id, machineID: machineID,
                            now: deliveredAt, clock: clock)
        }
    }

    /// 友達ボットに、自分の今日の缶を開けてリアクションしてもらう（通知のテスト用）
    static func friendsReact(to canID: String, in db: inout AppDatabase, now: Date, clock: BusinessClock) {
        guard let can = db.can(canID), let machine = db.machine(can.machineID) else { return }
        let bots = machine.memberIDs.compactMap { db.user($0) }.filter { $0.isDemo && $0.id != can.authorID }
        for (index, bot) in bots.enumerated() {
            // 開店前でも試せるように、時刻のチェックは飛ばす
            try? db.open(canID: canID, userID: bot.id, now: now, clock: clock, ignoringSchedule: true)
            let kind = ReactionKind.allCases[(index + can.title.count) % ReactionKind.allCases.count]
            if !db.hasReacted(canID: canID, userID: bot.id, kind: kind) {
                db.toggleReaction(canID: canID, userID: bot.id, kind: kind, now: now)
            }
            if index == 0 {
                try? db.sendLetter(canID: canID, fromID: bot.id,
                                   text: sampleLetters[can.title.count % sampleLetters.count], now: now)
            }
        }
    }

    private static func draft(index: Int) -> CanDraft {
        let sample = sampleCans[abs(index) % sampleCans.count]
        var draft = CanDraft()
        draft.title = sample.title
        draft.text = sample.text
        draft.mood = sample.mood
        draft.pattern = sample.pattern
        draft.kind = .text
        return draft
    }
}
