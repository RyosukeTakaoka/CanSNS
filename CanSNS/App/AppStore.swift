import Foundation
import Observation

/// アプリ全体の状態を持つクラス。画面はここを見て表示を変える。
///
/// 2つのモードがある:
/// - Firebase モード: GoogleService-Info.plist が入っていると自動でこちら。友達と本当にやりとりできる
/// - オフライン（デモ）モード: 端末内（Application Support/CanSNS/db.json）だけに保存する。友達ボットで試せる
///
/// どちらのモードでも、操作は `perform` を通して AppDatabase のルールで行う。
@MainActor
@Observable
final class AppStore {
    enum Mode {
        case local
        case cloud
    }

    enum CloudStatus: Equatable {
        case connecting
        case ready
        case failed(String)
    }

    private(set) var mode: Mode
    private(set) var cloudStatus: CloudStatus = .ready
    private(set) var db: AppDatabase
    private(set) var currentUserID: String?
    private(set) var selectedMachineID: String?
    /// 開発者メニュー用：本当の時刻からのずれ（秒）。Firebase モードでは常に 0
    private(set) var timeOffset: TimeInterval
    /// 今のユーザーが「もう見た」缶のID（NEW バッジを消すのに使う）
    private(set) var seenCanIDs: Set<String> = []
    /// サーバーとのやりとりで起きたエラー（画面下に表示する）
    var syncMessage: String?
    var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: Keys.sound)
            SoundPlayer.shared.isEnabled = soundEnabled
        }
    }

    let clock = BusinessClock()

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var cloud: CloudSync?

    private enum Keys {
        static let currentUser = "currentUserID"
        static let machine = "selectedMachineID"
        static let offset = "timeOffset"
        static let sound = "soundEnabled"
        static let forceLocal = "forceLocalMode"
        static func seen(_ userID: String) -> String { "seenCans-\(userID)" }
    }

    init() {
        // 初期化の途中では self のプロパティを読めないので、ローカル変数を使う
        let defaults = UserDefaults.standard
        let url = Self.makeFileURL()
        let useCloud = CloudSupport.isAvailable && !defaults.bool(forKey: Keys.forceLocal)
        fileURL = url
        mode = useCloud ? .cloud : .local
        db = useCloud ? AppDatabase() : Self.load(from: url)
        currentUserID = useCloud ? nil : defaults.string(forKey: Keys.currentUser)
        selectedMachineID = defaults.string(forKey: Keys.machine)
        timeOffset = useCloud ? 0 : defaults.double(forKey: Keys.offset)
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        if let id = currentUserID, db.user(id) == nil {
            currentUserID = nil
        }
        SoundPlayer.shared.isEnabled = soundEnabled
        loadSeenCans()
        if useCloud {
            connectCloud()
        }
    }

    // MARK: - モード

    /// Firebase の設定ファイル（GoogleService-Info.plist）が入っているか
    var isCloudAvailable: Bool { CloudSupport.isAvailable }

    /// Firebase に接続中で、まだ画面を出せない
    var isLoading: Bool { mode == .cloud && cloudStatus == .connecting }

    /// オフライン（デモ）モードと Firebase モードを切り替える
    func setLocalMode(_ useLocal: Bool) {
        defaults.set(useLocal, forKey: Keys.forceLocal)
        cloud?.stop()
        cloud = nil
        seenCanIDs = []
        if useLocal || !CloudSupport.isAvailable {
            mode = .local
            cloudStatus = .ready
            db = Self.load(from: fileURL)
            currentUserID = defaults.string(forKey: Keys.currentUser)
            if let id = currentUserID, db.user(id) == nil { currentUserID = nil }
            timeOffset = defaults.double(forKey: Keys.offset)
            loadSeenCans()
        } else {
            mode = .cloud
            db = AppDatabase()
            currentUserID = nil
            timeOffset = 0
            connectCloud()
        }
    }

    func retryConnection() {
        guard mode == .cloud else { return }
        cloud?.stop()
        connectCloud()
    }

    private func connectCloud() {
        CloudSupport.configureIfNeeded()
        let cloud = CloudSync(clock: clock)
        self.cloud = cloud
        cloudStatus = .connecting
        cloud.onUpdate = { [weak self] newDB in
            self?.applyCloud(newDB)
        }
        cloud.onError = { [weak self] message in
            self?.syncMessage = message
        }
        Task {
            do {
                _ = try await cloud.signIn()
                cloud.start()
            } catch {
                self.cloudStatus = .failed(error.localizedDescription)
            }
        }
    }

    /// サーバーから届いた最新のデータを反映する
    private func applyCloud(_ newDB: AppDatabase) {
        guard let cloud, let uid = cloud.uid else { return }
        db = newDB
        guard cloud.hasLoadedProfile else { return }
        let newUserID: String? = newDB.user(uid) != nil ? uid : nil
        if currentUserID != newUserID {
            currentUserID = newUserID
            loadSeenCans()
        }
        cloudStatus = .ready
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
        let id = mode == .cloud ? cloud?.uid : nil
        if mode == .cloud && id == nil {
            syncMessage = "サーバーに接続できていません"
            return
        }
        let user = perform { $0.createUser(id: id, name: name, emoji: emoji, now: now) }
        setCurrentUser(user.id)
    }

    func updateProfile(name: String, emoji: String) {
        guard let userID = currentUserID else { return }
        perform { $0.updateUser(userID, name: name, emoji: emoji) }
    }

    func createMachine(name: String) {
        guard let userID = currentUserID else { return }
        let machine = perform { $0.createMachine(name: name, ownerID: userID, now: now) }
        selectMachine(machine.id)
    }

    func joinMachine(inviteCode: String) async throws {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        switch mode {
        case .local:
            let machine = try perform { try $0.joinMachine(inviteCode: inviteCode, userID: userID, now: now) }
            selectMachine(machine.id)
        case .cloud:
            guard let cloud else { throw CanSNSError.machineNotFound }
            let machineID = try await cloud.join(inviteCode: inviteCode, userName: currentUser?.name ?? "だれか")
            selectMachine(machineID)
        }
    }

    /// デモの自販機（友達ボット入り）を置く。オフラインモード専用
    func startDemo() {
        guard mode == .local, let userID = currentUserID else { return }
        let machine = perform { DemoSeeder.seed(into: &$0, me: userID, now: now, clock: clock) }
        selectMachine(machine.id)
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
        return try perform {
            try $0.deliver(draft, authorID: userID, machineID: machine.id, now: now, clock: clock)
        }
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
        try perform { try $0.open(canID: can.id, userID: userID, now: now, clock: clock) }
    }

    /// Firebase モードで、まだ受け取っていない缶の中身をサーバーから受け取る。
    /// 失敗したら理由を返す（開店前の友達の缶は、サーバーのルールで断られる）
    func loadContentIfNeeded(_ can: CanPost) async -> String? {
        guard mode == .cloud, can.isContentHidden, let cloud else { return nil }
        do {
            try await cloud.loadContent(canID: can.id, machineID: can.machineID)
            return nil
        } catch {
            print("中身の受け取りに失敗:", error.localizedDescription)
            return "中身を受け取れませんでした。開店前か、通信がうまくいっていないかもしれません"
        }
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
        perform { $0.toggleReaction(canID: can.id, userID: userID, kind: kind, now: now) }
    }

    func sendStraw(on can: CanPost, threadUserID: String, text: String) throws {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        try perform {
            try $0.sendStraw(canID: can.id, threadUserID: threadUserID, senderID: userID, text: text, now: now)
        }
    }

    func sendLetter(on can: CanPost, text: String) throws {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        try perform { try $0.sendLetter(canID: can.id, fromID: userID, text: text, now: now) }
    }

    func saveToFridge(_ can: CanPost) throws {
        guard let userID = currentUserID else { throw CanSNSError.userNotFound }
        try perform { try $0.saveToFridge(canID: can.id, userID: userID, now: now, clock: clock) }
    }

    func removeFromFridge(_ can: CanPost) {
        guard let userID = currentUserID else { return }
        perform { $0.removeFromFridge(canID: can.id, userID: userID) }
    }

    func markAllRead() {
        guard let userID = currentUserID, unreadCount > 0 else { return }
        perform { $0.markAllRead(for: userID) }
    }

    // MARK: - 開発者メニュー（オフラインモードでのテスト用）

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
        // Firebase モードでは、時刻はサーバーの時計で判定されるので動かせない
        guard mode == .local else { return }
        timeOffset = date.timeIntervalSince(Date())
        defaults.set(timeOffset, forKey: Keys.offset)
    }

    /// 同じ自販機のメンバーに「なりきる」（1台の端末で友達側の操作を試せる）
    func switchUser(to userID: String) {
        guard mode == .local, db.user(userID) != nil else { return }
        setCurrentUser(userID)
    }

    func letFriendsDeliver() {
        guard mode == .local, let machine = currentMachine else { return }
        perform { DemoSeeder.deliverFromFriends(in: &$0, machineID: machine.id, now: now, clock: clock) }
    }

    func letFriendsReactToMyCan() -> Bool {
        guard mode == .local, let userID = currentUserID, let machine = currentMachine,
              let can = db.cans(in: machine.id, by: userID, on: today).last else { return false }
        perform { DemoSeeder.friendsReact(to: can.id, in: &$0, now: now, clock: clock) }
        return true
    }

    /// オフラインモードのデータをすべて消す
    func resetAll() {
        guard mode == .local else { return }
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
        saveLocal()
    }

    // MARK: - 保存

    /// データを操作して、そのあと保存（オフライン）または送信（Firebase）する
    @discardableResult
    private func perform<T>(_ body: (inout AppDatabase) throws -> T) rethrows -> T {
        let before = db
        let result = try body(&db)
        switch mode {
        case .local:
            saveLocal()
        case .cloud:
            let changes = db.changes(from: before)
            if !changes.isEmpty {
                cloud?.apply(changes, db: db, currentMachineID: currentMachine?.id)
            }
        }
        return result
    }

    private func setCurrentUser(_ id: String) {
        currentUserID = id
        if mode == .local {
            defaults.set(id, forKey: Keys.currentUser)
        }
        loadSeenCans()
    }

    private func loadSeenCans() {
        guard let userID = currentUserID else {
            seenCanIDs = []
            return
        }
        seenCanIDs = Set(defaults.stringArray(forKey: Keys.seen(userID)) ?? [])
    }

    private func saveLocal() {
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
