import Foundation
import Observation

/// アプリ全体の状態を持つクラス。画面はここを見て表示を変える。
/// データは端末内（Application Support/CanSNS/db.json）に保存する。
@MainActor
@Observable
final class AppStore {
    private(set) var db: AppDatabase
    private(set) var currentUserID: String?
    private(set) var selectedMachineID: String?
    /// 開発者メニュー用：本当の時刻からのずれ（秒）
    private(set) var timeOffset: TimeInterval
    /// 今のユーザーが「もう見た」缶のID（NEW バッジを消すのに使う）
    private(set) var seenCanIDs: Set<String> = []
    var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: Keys.sound)
            SoundPlayer.shared.isEnabled = soundEnabled
        }
    }

    let clock = BusinessClock()

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let currentUser = "currentUserID"
        static let machine = "selectedMachineID"
        static let offset = "timeOffset"
        static let sound = "soundEnabled"
        static func seen(_ userID: String) -> String { "seenCans-\(userID)" }
    }

    init() {
        // 初期化の途中では self のプロパティを読めないので、ローカル変数を使う
        let defaults = UserDefaults.standard
        let url = Self.makeFileURL()
        fileURL = url
        db = Self.load(from: url)
        currentUserID = defaults.string(forKey: Keys.currentUser)
        selectedMachineID = defaults.string(forKey: Keys.machine)
        timeOffset = defaults.double(forKey: Keys.offset)
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        if let id = currentUserID, db.user(id) == nil {
            currentUserID = nil
        }
        SoundPlayer.shared.isEnabled = soundEnabled
        loadSeenCans()
    }

    // MARK: - 時刻

    /// アプリ内の「今」（開発者メニューで時刻をずらしている場合はずらした時刻）
    var now: Date { Date().addingTimeInterval(timeOffset) }

    func adjusted(_ date: Date) -> Date { date.addingTimeInterval(timeOffset) }

    var today: BusinessDay { clock.businessDay(for: now) }

    var isTimeShifted: Bool { abs(timeOffset) > 1 }

    // MARK: - 今のユーザーと自販機

    var currentUser: UserProfile? {
        currentUserID.flatMap { db.user($0) }
    }

    var myMachines: [Machine] {
        guard let userID = currentUserID else { return [] }
        return db.machines(for: userID)
    }

    var currentMachine: Machine? {
        let machines = myMachines
        if let id = selectedMachineID, let machine = machines.first(where: { $0.id == id }) {
            return machine
        }
        return machines.first
    }

    var unreadCount: Int {
        guard let userID = currentUserID else { return 0 }
        return db.unreadCount(for: userID)
    }

    func user(_ id: String) -> UserProfile? { db.user(id) }

    // MARK: - アカウント・自販機

    func createAccount(name: String, emoji: String) {
        let user = db.createUser(name: name, emoji: emoji, now: now)
        setCurrentUser(user.id)
        save()
    }

    func updateProfile(name: String, emoji: String) {
        guard let userID = currentUserID else { return }
        db.updateUser(userID, name: name, emoji: emoji)
        save()
    }

    func createMachine(name: String) {
        guard let userID = currentUserID else { return }
        let machine = db.createMachine(name: name, ownerID: userID, now: now)
        selectMachine(machine.id)
        save()
    }

    func joinMachine(inviteCode: String) throws {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        let machine = try db.joinMachine(inviteCode: inviteCode, userID: userID, now: now)
        selectMachine(machine.id)
        save()
    }

    func startDemo() {
        guard let userID = currentUserID else { return }
        let machine = DemoSeeder.seed(into: &db, me: userID, now: now, clock: clock)
        selectMachine(machine.id)
        save()
    }

    func selectMachine(_ id: String) {
        selectedMachineID = id
        defaults.set(id, forKey: Keys.machine)
    }

    // MARK: - 缶の操作

    @discardableResult
    func deliver(_ draft: CanDraft) throws -> CanPost {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        guard let machine = currentMachine else { throw CanSNSError.machineNotFound }
        let can = try db.deliver(draft, authorID: userID, machineID: machine.id, now: now, clock: clock)
        save()
        return can
    }

    /// 開けられるかどうかを確認し、ダメならその理由を返す
    func openBlockReason(for can: CanPost) -> String? {
        guard let userID = currentUserID else { return CanSNSError.userNotFound.errorDescription }
        do {
            try db.checkCanOpen(can, userID: userID, now: now, clock: clock)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func open(_ can: CanPost) throws {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        try db.open(canID: can.id, userID: userID, now: now, clock: clock)
        save()
    }

    /// まだ見ていない友達の新しい缶か
    func isNew(_ can: CanPost) -> Bool {
        can.authorID != currentUserID && !seenCanIDs.contains(can.id) && !hasOpened(can)
    }

    func markSeen(_ can: CanPost) {
        guard let userID = currentUserID, !seenCanIDs.contains(can.id) else { return }
        seenCanIDs.insert(can.id)
        defaults.set(Array(seenCanIDs), forKey: Keys.seen(userID))
    }

    func hasOpened(_ can: CanPost) -> Bool {
        guard let userID = currentUserID else { return false }
        return db.hasOpened(canID: can.id, userID: userID)
    }

    func toggleReaction(_ kind: ReactionKind, on can: CanPost) {
        guard let userID = currentUserID else { return }
        db.toggleReaction(canID: can.id, userID: userID, kind: kind, now: now)
        save()
    }

    func sendStraw(on can: CanPost, threadUserID: String, text: String) throws {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        try db.sendStraw(canID: can.id, threadUserID: threadUserID, senderID: userID, text: text, now: now)
        save()
    }

    func sendLetter(on can: CanPost, text: String) throws {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        try db.sendLetter(canID: can.id, fromID: userID, text: text, now: now)
        save()
    }

    func saveToFridge(_ can: CanPost) throws {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        try db.saveToFridge(canID: can.id, userID: userID, now: now, clock: clock)
        save()
    }

    func removeFromFridge(_ can: CanPost) {
        guard let userID = currentUserID else { return }
        db.removeFromFridge(canID: can.id, userID: userID)
        save()
    }

    func markAllRead() {
        guard let userID = currentUserID else { return }
        db.markAllRead(for: userID)
        save()
    }

    // MARK: - 開発者メニュー（テスト用）

    /// 今の営業日の中で、指定した時刻に時計を合わせる（0〜5時は「翌日の深夜」として扱う）
    func setTime(hour: Int, minute: Int) {
        let base = clock.date(of: today, hour: hour, dayOffset: hour < BusinessClock.dayStartHour ? 1 : 0)
        jump(to: base.addingTimeInterval(TimeInterval(minute * 60)))
    }

    /// 翌営業日の朝に進める（前日の缶が廃棄されるのを確かめる用）
    func skipToNextMorning() {
        jump(to: clock.disposalTime(of: today).addingTimeInterval(5 * 60))
    }

    func resetTime() {
        timeOffset = 0
        defaults.set(0.0, forKey: Keys.offset)
    }

    private func jump(to date: Date) {
        timeOffset = date.timeIntervalSince(Date())
        defaults.set(timeOffset, forKey: Keys.offset)
    }

    /// 同じ自販機のメンバーに「なりきる」（1台の端末で友達側の操作を試せる）
    func switchUser(to userID: String) {
        guard db.user(userID) != nil else { return }
        setCurrentUser(userID)
    }

    func letFriendsDeliver() {
        guard let machine = currentMachine else { return }
        DemoSeeder.deliverFromFriends(in: &db, machineID: machine.id, now: now, clock: clock)
        save()
    }

    func letFriendsReactToMyCan() -> Bool {
        guard let userID = currentUserID, let machine = currentMachine,
              let can = db.can(in: machine.id, by: userID, on: today) else { return false }
        DemoSeeder.friendsReact(to: can.id, in: &db, now: now, clock: clock)
        save()
        return true
    }

    func resetAll() {
        for user in db.users {
            defaults.removeObject(forKey: Keys.seen(user.id))
        }
        db = AppDatabase()
        currentUserID = nil
        selectedMachineID = nil
        for key in [Keys.currentUser, Keys.machine, Keys.offset] {
            defaults.removeObject(forKey: key)
        }
        seenCanIDs = []
        timeOffset = 0
        MediaStore.deleteAll()
        save()
    }

    // MARK: - 保存

    private func setCurrentUser(_ id: String) {
        currentUserID = id
        defaults.set(id, forKey: Keys.currentUser)
        loadSeenCans()
    }

    private func loadSeenCans() {
        guard let userID = currentUserID else {
            seenCanIDs = []
            return
        }
        seenCanIDs = Set(defaults.stringArray(forKey: Keys.seen(userID)) ?? [])
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(db)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("保存に失敗しました: \(error)")
        }
    }

    private static func load(from url: URL) -> AppDatabase {
        guard let data = try? Data(contentsOf: url),
              let db = try? JSONDecoder().decode(AppDatabase.self, from: data) else {
            return AppDatabase()
        }
        return db
    }

    private static func makeFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CanSNS", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("db.json")
    }
}
