import XCTest
@testable import CanSNSCore

final class BusinessClockTests: XCTestCase {
    let clock = BusinessClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        clock.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testBusinessDayStartsAtSixAM() {
        XCTAssertEqual(clock.businessDay(for: date(2026, 9, 28, 6, 0)).key, "2026-09-28")
        XCTAssertEqual(clock.businessDay(for: date(2026, 9, 28, 23, 59)).key, "2026-09-28")
        // 深夜0時〜5時59分は、まだ前の日の営業時間
        XCTAssertEqual(clock.businessDay(for: date(2026, 9, 29, 5, 59)).key, "2026-09-28")
        XCTAssertEqual(clock.businessDay(for: date(2026, 9, 29, 6, 0)).key, "2026-09-29")
    }

    func testPhases() {
        XCTAssertEqual(clock.phase(at: date(2026, 9, 28, 6, 0)), .delivery)
        XCTAssertEqual(clock.phase(at: date(2026, 9, 28, 20, 59)), .delivery)
        XCTAssertEqual(clock.phase(at: date(2026, 9, 28, 21, 0)), .open)
        XCTAssertEqual(clock.phase(at: date(2026, 9, 29, 3, 0)), .open)
        XCTAssertEqual(clock.phase(at: date(2026, 9, 29, 5, 59)), .open)
    }

    func testTransitions() {
        let day = clock.businessDay(for: date(2026, 9, 28, 12))
        XCTAssertEqual(clock.openTime(of: day), date(2026, 9, 28, 21))
        XCTAssertEqual(clock.disposalTime(of: day), date(2026, 9, 29, 6))
        XCTAssertEqual(clock.nextTransition(after: date(2026, 9, 28, 12)), date(2026, 9, 28, 21))
        XCTAssertEqual(clock.nextTransition(after: date(2026, 9, 28, 22)), date(2026, 9, 29, 6))
        // 月をまたいでも正しく計算できる
        let lastDay = clock.businessDay(for: date(2026, 9, 30, 12))
        XCTAssertEqual(clock.day(lastDay, offsetBy: 1).key, "2026-10-01")
        XCTAssertEqual(clock.day(lastDay, offsetBy: -30).key, "2026-08-31")
    }

    func testCountdownText() {
        XCTAssertEqual(BusinessClock.countdownText(3 * 3600 + 5 * 60 + 9), "3:05:09")
        XCTAssertEqual(BusinessClock.countdownText(-5), "0:00:00")
    }
}

final class AppDatabaseTests: XCTestCase {
    let clock = BusinessClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    var db = AppDatabase()
    var alice: UserProfile!
    var bob: UserProfile!
    var machine: Machine!

    func date(_ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        clock.calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: min))!
    }

    override func setUp() {
        db = AppDatabase()
        alice = db.createUser(name: "ありさ", emoji: "🐱", now: date(28, 7))
        bob = db.createUser(name: "ぼぶ", emoji: "🐶", now: date(28, 7))
        machine = db.createMachine(name: "テスト自販機", ownerID: alice.id, now: date(20, 7))
        try! db.joinMachine(inviteCode: machine.inviteCode, userID: bob.id, now: date(20, 8))
    }

    func textDraft(_ title: String = "今日") -> CanDraft {
        var draft = CanDraft()
        draft.title = title
        draft.text = "たのしかった"
        return draft
    }

    func testOneCanPerDay() throws {
        try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id, now: date(28, 9), clock: clock)
        XCTAssertThrowsError(try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id,
                                            now: date(28, 22), clock: clock)) { error in
            XCTAssertEqual(error as? CanSNSError, .alreadyDelivered)
        }
        // 翌朝6時を過ぎたらまた納品できる
        XCTAssertNoThrow(try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id,
                                        now: date(29, 6, 1), clock: clock))
    }

    func testDeliveryIsSilent() throws {
        // 納品しても通知は出さない（自販機に缶が増えるだけ）
        try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id, now: date(28, 9), clock: clock)
        XCTAssertEqual(db.unreadCount(for: bob.id), 0)
        XCTAssertEqual(db.cans(in: machine.id, on: clock.businessDay(for: date(28, 9))).count, 1)
    }

    func testValidation() {
        var draft = textDraft("   ")
        XCTAssertThrowsError(try db.deliver(draft, authorID: alice.id, machineID: machine.id,
                                            now: date(28, 9), clock: clock)) { error in
            XCTAssertEqual(error as? CanSNSError, .emptyTitle)
        }
        draft = textDraft()
        draft.kind = .photo
        XCTAssertThrowsError(try db.deliver(draft, authorID: alice.id, machineID: machine.id,
                                            now: date(28, 9), clock: clock)) { error in
            XCTAssertEqual(error as? CanSNSError, .emptyContent)
        }
    }

    func testCannotOpenBeforeNinePM() throws {
        let can = try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id, now: date(28, 9), clock: clock)
        XCTAssertThrowsError(try db.open(canID: can.id, userID: bob.id, now: date(28, 20, 59), clock: clock)) { error in
            XCTAssertEqual(error as? CanSNSError, .notOpenYet)
        }
        // 投稿者本人はいつでも見られる
        XCTAssertNoThrow(try db.checkCanOpen(can, userID: alice.id, now: date(28, 10), clock: clock))
        // 21時になったら開けられて、投稿者に通知が届く
        try db.open(canID: can.id, userID: bob.id, now: date(28, 21), clock: clock)
        XCTAssertTrue(db.hasOpened(canID: can.id, userID: bob.id))
        XCTAssertEqual(db.notifications(for: alice.id).first?.kind, .opened)
        // 2回目は通知が増えない
        try db.open(canID: can.id, userID: bob.id, now: date(28, 21, 5), clock: clock)
        XCTAssertEqual(db.notifications(for: alice.id).filter { $0.kind == .opened }.count, 1)
    }

    func testDisposedAtSixAM() throws {
        let can = try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id, now: date(28, 9), clock: clock)
        XCTAssertThrowsError(try db.open(canID: can.id, userID: bob.id, now: date(29, 6), clock: clock)) { error in
            XCTAssertEqual(error as? CanSNSError, .disposed)
        }
        // 廃棄されると、投稿者の冷蔵庫に入る
        let today = clock.businessDay(for: date(29, 6))
        XCTAssertEqual(db.fridgeCans(for: alice.id, today: today).own.map(\.id), [can.id])
        XCTAssertTrue(db.cans(in: machine.id, on: today).isEmpty)
    }

    func testMinimumMembers() throws {
        // 2人そろえば開店できる
        XCTAssertEqual(MachineRules.minimumMembersToOpen, 2)
        XCTAssertEqual(db.machine(machine.id)?.members.count, 2)
        let can = try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id, now: date(28, 9), clock: clock)
        XCTAssertNoThrow(try db.checkCanOpen(can, userID: bob.id, now: date(28, 22), clock: clock))
    }

    func testFridgeRules() throws {
        var draft = textDraft()
        draft.allowFridge = false
        let privateCan = try db.deliver(draft, authorID: alice.id, machineID: machine.id, now: date(28, 9), clock: clock)
        try db.open(canID: privateCan.id, userID: bob.id, now: date(28, 22), clock: clock)
        XCTAssertThrowsError(try db.saveToFridge(canID: privateCan.id, userID: bob.id, now: date(28, 22), clock: clock))

        let publicCan = try db.deliver(textDraft(), authorID: bob.id, machineID: machine.id, now: date(28, 9), clock: clock)
        // 開ける前は冷蔵庫に入れられない
        XCTAssertThrowsError(try db.saveToFridge(canID: publicCan.id, userID: alice.id, now: date(28, 22), clock: clock))
        try db.open(canID: publicCan.id, userID: alice.id, now: date(28, 22), clock: clock)
        try db.saveToFridge(canID: publicCan.id, userID: alice.id, now: date(28, 22), clock: clock)
        // 保存されたことは投稿者に必ず通知される
        XCTAssertTrue(db.notifications(for: bob.id).contains { $0.kind == .fridge })
        // 翌日になっても、冷蔵庫から見られる
        let nextDay = clock.businessDay(for: date(29, 8))
        XCTAssertEqual(db.fridgeCans(for: alice.id, today: nextDay).saved.map(\.id), [publicCan.id])
    }

    func testLetterOnlyOncePerCan() throws {
        let can = try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id, now: date(28, 9), clock: clock)
        try db.sendLetter(canID: can.id, fromID: bob.id, text: "わかる", now: date(28, 22))
        XCTAssertThrowsError(try db.sendLetter(canID: can.id, fromID: bob.id, text: "もう1通", now: date(28, 22)))
        XCTAssertEqual(db.letters(of: can.id).first?.toID, alice.id)
    }

    func testStrawThread() throws {
        let can = try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id, now: date(28, 9), clock: clock)
        try db.sendStraw(canID: can.id, threadUserID: bob.id, senderID: bob.id, text: "それどこ？", now: date(28, 22))
        try db.sendStraw(canID: can.id, threadUserID: bob.id, senderID: alice.id, text: "駅前！", now: date(28, 22, 1))
        XCTAssertEqual(db.strawMessages(canID: can.id, threadUserID: bob.id).count, 2)
        XCTAssertEqual(db.strawThreadUsers(canID: can.id), [bob.id])
        XCTAssertTrue(db.notifications(for: bob.id).contains { $0.kind == .straw })
    }

    func testReactionToggle() throws {
        let can = try db.deliver(textDraft(), authorID: alice.id, machineID: machine.id, now: date(28, 9), clock: clock)
        db.toggleReaction(canID: can.id, userID: bob.id, kind: .attakai, now: date(28, 22))
        XCTAssertTrue(db.hasReacted(canID: can.id, userID: bob.id, kind: .attakai))
        db.toggleReaction(canID: can.id, userID: bob.id, kind: .attakai, now: date(28, 22))
        XCTAssertFalse(db.hasReacted(canID: can.id, userID: bob.id, kind: .attakai))
    }

    func testInviteCode() {
        XCTAssertThrowsError(try db.joinMachine(inviteCode: "ZZZZZZ", userID: bob.id, now: date(28, 8)))
        XCTAssertThrowsError(try db.joinMachine(inviteCode: machine.inviteCode.lowercased(), userID: bob.id,
                                                now: date(28, 8))) { error in
            XCTAssertEqual(error as? CanSNSError, .alreadyMember)
        }
    }
}

final class EffectsTests: XCTestCase {
    let clock = BusinessClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)

    func date(_ d: Int, _ h: Int) -> Date {
        clock.calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
    }

    func draft() -> CanDraft {
        var draft = CanDraft()
        draft.title = "今日"
        draft.text = "ひとこと"
        return draft
    }

    func testFullStockAndAllPurchased() throws {
        var db = AppDatabase()
        let a = db.createUser(name: "a", emoji: "🐱", now: date(1, 7))
        let b = db.createUser(name: "b", emoji: "🐶", now: date(1, 7))
        let machine = db.createMachine(name: "m", ownerID: a.id, now: date(1, 7))
        try db.joinMachine(inviteCode: machine.inviteCode, userID: b.id, now: date(1, 7))
        let day = clock.businessDay(for: date(28, 12))

        let canA = try db.deliver(draft(), authorID: a.id, machineID: machine.id, now: date(28, 9), clock: clock)
        XCTAssertFalse(db.effects(machineID: machine.id, day: day, clock: clock).contains(.fullStock))
        let canB = try db.deliver(draft(), authorID: b.id, machineID: machine.id, now: date(28, 10), clock: clock)
        XCTAssertTrue(db.effects(machineID: machine.id, day: day, clock: clock).contains(.fullStock))

        try db.open(canID: canB.id, userID: a.id, now: date(28, 21), clock: clock)
        XCTAssertFalse(db.effects(machineID: machine.id, day: day, clock: clock).contains(.allPurchased))
        try db.open(canID: canA.id, userID: b.id, now: date(28, 21), clock: clock)
        XCTAssertTrue(db.effects(machineID: machine.id, day: day, clock: clock).contains(.allPurchased))
    }

    func testNeonAfterSevenDays() throws {
        var db = AppDatabase()
        let a = db.createUser(name: "a", emoji: "🐱", now: date(1, 7))
        let machine = db.createMachine(name: "m", ownerID: a.id, now: date(1, 7))
        for d in 20...26 {
            try db.deliver(draft(), authorID: a.id, machineID: machine.id, now: date(d, 9), clock: clock)
        }
        let day26 = clock.businessDay(for: date(26, 12))
        XCTAssertEqual(db.deliveryStreak(machineID: machine.id, endingAt: day26, clock: clock), 7)
        XCTAssertTrue(db.effects(machineID: machine.id, day: day26, clock: clock).contains(.limitedNeon))
        let day25 = clock.businessDay(for: date(25, 12))
        XCTAssertFalse(db.effects(machineID: machine.id, day: day25, clock: clock).contains(.limitedNeon))
    }

    func testNewArrival() throws {
        var db = AppDatabase()
        let a = db.createUser(name: "a", emoji: "🐱", now: date(1, 7))
        let b = db.createUser(name: "b", emoji: "🐶", now: date(1, 7))
        let machine = db.createMachine(name: "m", ownerID: a.id, now: date(28, 7))
        let day = clock.businessDay(for: date(28, 12))
        // 作った人だけでは「新商品入荷」にならない
        XCTAssertFalse(db.effects(machineID: machine.id, day: day, clock: clock).contains(.newArrival))
        try db.joinMachine(inviteCode: machine.inviteCode, userID: b.id, now: date(28, 15))
        XCTAssertTrue(db.effects(machineID: machine.id, day: day, clock: clock).contains(.newArrival))
    }

    func testGrowth() {
        XCTAssertEqual(MachineGrowth.level(totalCans: 0), 1)
        XCTAssertEqual(MachineGrowth.level(totalCans: 4), 1)
        XCTAssertEqual(MachineGrowth.level(totalCans: 5), 2)
        XCTAssertEqual(MachineGrowth.level(totalCans: 400), 10)
        XCTAssertNil(MachineGrowth.progress(totalCans: 400))
        XCTAssertEqual(MachineGrowth.progress(totalCans: 10)?.remaining, 5)
    }

    func testDemoSeed() {
        var db = AppDatabase()
        let me = db.createUser(name: "me", emoji: "🙂", now: date(28, 7))
        let now = date(28, 12)
        let machine = DemoSeeder.seed(into: &db, me: me.id, now: now, clock: clock)
        let today = clock.businessDay(for: now)
        XCTAssertEqual(machine.members.count, 4)
        // 今日は友達3人が納品ずみ
        XCTAssertEqual(db.cans(in: machine.id, on: today).count, 3)
        // 自分の過去の缶と、もらった缶が冷蔵庫に入っている
        let fridge = db.fridgeCans(for: me.id, today: today)
        XCTAssertEqual(fridge.own.count, 2)
        XCTAssertEqual(fridge.saved.count, 1)
        // 自分が納品すれば満タン＆7日連続
        XCTAssertNoThrow(try db.deliver(draft(), authorID: me.id, machineID: machine.id, now: now, clock: clock))
        let effects = db.effects(machineID: machine.id, day: today, clock: clock)
        XCTAssertTrue(effects.contains(.fullStock))
        XCTAssertTrue(effects.contains(.limitedNeon))
    }
}

final class SoundAndSkyTests: XCTestCase {
    func testWavHeader() {
        for effect in SoundEffect.allCases {
            let samples = SoundSynth.samples(for: effect)
            let data = SoundSynth.wavData(samples: samples)
            XCTAssertEqual(data.count, 44 + samples.count * 2, "\(effect)")
            XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
            XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
            XCTAssertLessThanOrEqual(samples.map { abs($0) }.max() ?? 0, 1)
            XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.1)
        }
    }

    func testNoiseRange() {
        var rng = NoiseGenerator(seed: 1)
        let values = (0..<10_000).map { _ in rng.next() }
        XCTAssertGreaterThanOrEqual(values.min()!, -1)
        XCTAssertLessThanOrEqual(values.max()!, 1)
        XCTAssertLessThan(values.min()!, -0.9)
        XCTAssertGreaterThan(values.max()!, 0.9)
    }

    func testSkyPalette() {
        XCTAssertEqual(SkyPalette.colors(hour: 0).top, SkyPalette.colors(hour: 24).top)
        XCTAssertEqual(SkyPalette.nightness(hour: 12), 0)
        XCTAssertEqual(SkyPalette.nightness(hour: 23), 1)
        // 昼の空は夜の空より明るい
        let noon = SkyPalette.colors(hour: 12).top
        let night = SkyPalette.colors(hour: 22).top
        XCTAssertGreaterThan(noon.r + noon.g + noon.b, night.r + night.g + night.b)
    }
}
