import Foundation

/// アプリのルール上のエラー。画面にはそのまま errorDescription を表示する。
enum CanSNSError: LocalizedError, Equatable {
    case userNotFound
    case machineNotFound
    case invalidInviteCode
    case machineFull
    case alreadyMember
    case notMember
    case notOpenYet
    case disposed
    case notEnoughMembers(needed: Int)
    case cannotSaveToFridge
    case alreadyInFridge
    case emptyTitle
    case emptyContent
    case letterAlreadySent
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .userNotFound: "ユーザーが見つかりません"
        case .machineNotFound: "自販機が見つかりません"
        case .invalidInviteCode: "招待コードが正しくありません"
        case .machineFull: "この自販機は満員です（最大\(MachineRules.maxMembers)人）"
        case .alreadyMember: "すでにこの自販機のメンバーです"
        case .notMember: "この自販機のメンバーではありません"
        case .notOpenYet: "まだ開店前です。21:00になったら開けられます"
        case .disposed: "この缶はもう廃棄されました"
        case .notEnoughMembers(let needed): "あと\(needed)人集まると開店できます"
        case .cannotSaveToFridge: "この缶は冷蔵庫に入れられません"
        case .alreadyInFridge: "もう冷蔵庫に入っています"
        case .emptyTitle: "商品名（タイトル）を入れてください"
        case .emptyContent: "缶の中身を入れてください"
        case .letterAlreadySent: "この缶にはもう手紙を入れました"
        case .emptyMessage: "メッセージを入力してください"
        }
    }
}

/// 自販機のルール（数値はここで調整できる）
enum MachineRules {
    /// 開店に必要な最低人数（周りを巻き込むための仕組み）
    static let minimumMembersToOpen = 2
    /// 1台の自販機に入れる最大人数
    static let maxMembers = 8
    // 1日に納品できる缶の数に上限はない
}

/// アプリのすべてのデータと、その操作（ルール）。
/// - オフライン（デモ）モード: この構造体を丸ごと端末内に JSON で保存する
/// - Firebase モード: サーバーから受け取ったデータでこの構造体を組み立て、
///   操作した前後の差分（`changes(from:)`）をサーバーに書き込む
struct AppDatabase: Codable {
    var users: [UserProfile] = []
    var machines: [Machine] = []
    var cans: [CanPost] = []
    var openings: [Opening] = []
    var reactions: [Reaction] = []
    var straws: [StrawMessage] = []
    var letters: [Letter] = []
    var fridge: [FridgeEntry] = []
    var notifications: [AppNotification] = []

    // MARK: - 読み取り

    func user(_ id: String) -> UserProfile? {
        users.first { $0.id == id }
    }

    func name(of userID: String) -> String {
        user(userID)?.name ?? "だれか"
    }

    func machine(_ id: String) -> Machine? {
        machines.first { $0.id == id }
    }

    func can(_ id: String) -> CanPost? {
        cans.first { $0.id == id }
    }

    func machines(for userID: String) -> [Machine] {
        machines.filter { $0.isMember(userID) }
    }

    /// 今この自販機に並んでいる缶（メンバーの並び順）
    func cans(in machineID: String, on day: BusinessDay) -> [CanPost] {
        cans.filter { $0.machineID == machineID && $0.businessDay == day }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// その人がその日に納品した缶（何本でも納品できる）
    func cans(in machineID: String, by userID: String, on day: BusinessDay) -> [CanPost] {
        cans(in: machineID, on: day).filter { $0.authorID == userID }
    }

    func hasOpened(canID: String, userID: String) -> Bool {
        openings.contains { $0.canID == canID && $0.userID == userID }
    }

    func openings(of canID: String) -> [Opening] {
        openings.filter { $0.canID == canID }.sorted { $0.openedAt < $1.openedAt }
    }

    func reactions(of canID: String) -> [Reaction] {
        reactions.filter { $0.canID == canID }.sorted { $0.createdAt < $1.createdAt }
    }

    func hasReacted(canID: String, userID: String, kind: ReactionKind) -> Bool {
        reactions.contains { $0.canID == canID && $0.userID == userID && $0.kind == kind }
    }

    func strawMessages(canID: String, threadUserID: String) -> [StrawMessage] {
        straws.filter { $0.canID == canID && $0.threadUserID == threadUserID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// 投稿者から見た「ストローが差さっている相手」の一覧
    func strawThreadUsers(canID: String) -> [String] {
        var seen: [String] = []
        for message in straws.filter({ $0.canID == canID }).sorted(by: { $0.createdAt < $1.createdAt })
        where !seen.contains(message.threadUserID) {
            seen.append(message.threadUserID)
        }
        return seen
    }

    func letters(of canID: String) -> [Letter] {
        letters.filter { $0.canID == canID }.sorted { $0.createdAt < $1.createdAt }
    }

    func letter(canID: String, from userID: String) -> Letter? {
        letters.first { $0.canID == canID && $0.fromID == userID }
    }

    func notifications(for userID: String) -> [AppNotification] {
        notifications.filter { $0.recipientID == userID }.sorted { $0.createdAt > $1.createdAt }
    }

    func unreadCount(for userID: String) -> Int {
        notifications.filter { $0.recipientID == userID && !$0.isRead }.count
    }

    func isDisposed(_ can: CanPost, today: BusinessDay) -> Bool {
        can.businessDay < today
    }

    func isInFridge(canID: String, ownerID: String) -> Bool {
        fridge.contains { $0.canID == canID && $0.ownerID == ownerID }
    }

    /// 冷蔵庫に入れられるか：他人の缶で、投稿者が許可していて、開封済みで、まだ廃棄前
    func canSaveToFridge(_ can: CanPost, userID: String, today: BusinessDay) -> Bool {
        can.authorID != userID
            && can.allowFridge
            && hasOpened(canID: can.id, userID: userID)
            && !isDisposed(can, today: today)
            && !isInFridge(canID: can.id, ownerID: userID)
    }

    /// 自分の冷蔵庫の中身
    /// - じぶんの缶: 廃棄された（＝前の営業日以前の）自分の投稿
    /// - もらった缶: 自分で冷蔵庫に入れた友達の投稿
    func fridgeCans(for userID: String, today: BusinessDay) -> (own: [CanPost], saved: [CanPost]) {
        let own = cans.filter { $0.authorID == userID && $0.businessDay < today }
            .sorted { $0.createdAt > $1.createdAt }
        let savedIDs = fridge.filter { $0.ownerID == userID }
            .sorted { $0.savedAt > $1.savedAt }
            .map(\.canID)
        let saved = savedIDs.compactMap { can($0) }
        return (own, saved)
    }

    /// 開封のルールを確認する（投稿者本人はいつでも中身を見られる）
    func checkCanOpen(_ can: CanPost, userID: String, now: Date, clock: BusinessClock) throws {
        guard let machine = self.machine(can.machineID) else { throw CanSNSError.machineNotFound }
        guard machine.isMember(userID) else { throw CanSNSError.notMember }
        if can.authorID == userID { return }
        guard can.businessDay == clock.businessDay(for: now) else { throw CanSNSError.disposed }
        let shortage = MachineRules.minimumMembersToOpen - machine.members.count
        if shortage > 0 { throw CanSNSError.notEnoughMembers(needed: shortage) }
        guard clock.phase(at: now) == .open else { throw CanSNSError.notOpenYet }
    }

    // MARK: - 書き込み

    /// - Parameter id: Firebase モードではログインしたユーザーのIDを使う（省略すると自動で作る）
    mutating func createUser(id: String? = nil, name: String, emoji: String, now: Date,
                             isDemo: Bool = false) -> UserProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = UserProfile(
            id: id ?? UUID().uuidString,
            name: trimmed.isEmpty ? "ななし" : String(trimmed.prefix(10)),
            emoji: emoji,
            createdAt: now,
            isDemo: isDemo
        )
        users.append(user)
        return user
    }

    mutating func updateUser(_ userID: String, name: String, emoji: String) {
        guard let index = users.firstIndex(where: { $0.id == userID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { users[index].name = String(trimmed.prefix(10)) }
        users[index].emoji = emoji
    }

    mutating func createMachine(name: String, ownerID: String, now: Date) -> Machine {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let machine = Machine(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "みんなの自販機" : String(trimmed.prefix(14)),
            inviteCode: makeInviteCode(),
            createdAt: now,
            members: [Membership(userID: ownerID, joinedAt: now)]
        )
        machines.append(machine)
        return machine
    }

    @discardableResult
    mutating func joinMachine(inviteCode: String, userID: String, now: Date) throws -> Machine {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let index = machines.firstIndex(where: { $0.inviteCode == code }) else {
            throw CanSNSError.invalidInviteCode
        }
        guard !machines[index].isMember(userID) else { throw CanSNSError.alreadyMember }
        guard machines[index].members.count < MachineRules.maxMembers else { throw CanSNSError.machineFull }
        machines[index].members.append(Membership(userID: userID, joinedAt: now))
        for member in machines[index].memberIDs {
            notify(member, actor: userID, kind: .memberJoined, canID: nil,
                   message: "\(name(of: userID))が「\(machines[index].name)」に参加しました。新商品入荷！", now: now)
        }
        return machines[index]
    }

    @discardableResult
    mutating func deliver(_ draft: CanDraft, authorID: String, machineID: String,
                          now: Date, clock: BusinessClock) throws -> CanPost {
        guard let machine = self.machine(machineID) else { throw CanSNSError.machineNotFound }
        guard machine.isMember(authorID) else { throw CanSNSError.notMember }
        let today = clock.businessDay(for: now)

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CanSNSError.emptyTitle }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.kind {
        case .text:
            guard !text.isEmpty else { throw CanSNSError.emptyContent }
        case .photo, .video, .voice:
            guard draft.mediaFileName != nil else { throw CanSNSError.emptyContent }
        }
        let textLimit = draft.kind == .text ? CanDraft.textLimit : CanDraft.captionLimit

        let can = CanPost(
            id: UUID().uuidString,
            machineID: machineID,
            authorID: authorID,
            businessDay: today,
            createdAt: now,
            title: String(title.prefix(CanDraft.titleLimit)),
            mood: draft.mood,
            kind: draft.kind,
            text: text.isEmpty ? nil : String(text.prefix(textLimit)),
            mediaFileName: draft.kind == .text ? nil : draft.mediaFileName,
            mediaDuration: draft.mediaDuration,
            pattern: draft.pattern,
            allowFridge: draft.allowFridge
        )
        // 納品は通知しない。自販機に缶が1本増えて「NEW」が付くだけ。
        cans.append(can)
        if let index = machines.firstIndex(where: { $0.id == machineID }) {
            machines[index].deliveredCount = (machines[index].deliveredCount ?? 0) + 1
        }
        return can
    }

    /// 缶を開ける。初めて開けたときだけ投稿者に通知が届く。
    /// - Parameter ignoringSchedule: デモの友達ボット用。開店時刻のチェックを飛ばす。
    mutating func open(canID: String, userID: String, now: Date, clock: BusinessClock,
                       ignoringSchedule: Bool = false) throws {
        guard let can = self.can(canID) else { throw CanSNSError.disposed }
        if !ignoringSchedule {
            try checkCanOpen(can, userID: userID, now: now, clock: clock)
        }
        guard can.authorID != userID, !hasOpened(canID: canID, userID: userID) else { return }
        openings.append(Opening(id: UUID().uuidString, canID: canID, userID: userID, openedAt: now))
        notify(can.authorID, actor: userID, kind: .opened, canID: canID,
               message: "\(name(of: userID))が「\(can.title)」を開けました", now: now)
    }

    mutating func toggleReaction(canID: String, userID: String, kind: ReactionKind, now: Date) {
        if let index = reactions.firstIndex(where: { $0.canID == canID && $0.userID == userID && $0.kind == kind }) {
            reactions.remove(at: index)
            return
        }
        reactions.append(Reaction(id: UUID().uuidString, canID: canID, userID: userID, kind: kind, createdAt: now))
        if let can = self.can(canID) {
            notify(can.authorID, actor: userID, kind: .reaction, canID: canID,
                   message: "\(name(of: userID))から「\(can.title)」に\(kind.emoji)\(kind.label)", now: now)
        }
    }

    mutating func sendStraw(canID: String, threadUserID: String, senderID: String,
                            text: String, now: Date) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CanSNSError.emptyMessage }
        guard let can = self.can(canID) else { throw CanSNSError.disposed }
        straws.append(StrawMessage(
            id: UUID().uuidString, canID: canID, threadUserID: threadUserID, senderID: senderID,
            text: String(trimmed.prefix(StrawMessage.textLimit)), createdAt: now
        ))
        // 相手に通知（投稿者が送ったならスレッド相手へ、そうでなければ投稿者へ）
        let recipient = senderID == can.authorID ? threadUserID : can.authorID
        notify(recipient, actor: senderID, kind: .straw, canID: canID,
               message: "\(name(of: senderID))が「\(can.title)」にストローを差しました：\(trimmed.prefix(20))", now: now)
    }

    mutating func sendLetter(canID: String, fromID: String, text: String, now: Date) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CanSNSError.emptyMessage }
        guard let can = self.can(canID) else { throw CanSNSError.disposed }
        guard letter(canID: canID, from: fromID) == nil else { throw CanSNSError.letterAlreadySent }
        letters.append(Letter(
            id: UUID().uuidString, canID: canID, fromID: fromID, toID: can.authorID,
            text: String(trimmed.prefix(Letter.textLimit)), createdAt: now
        ))
        notify(can.authorID, actor: fromID, kind: .letter, canID: canID,
               message: "「\(can.title)」の返却口に\(name(of: fromID))から手紙が届きました", now: now)
    }

    mutating func saveToFridge(canID: String, userID: String, now: Date, clock: BusinessClock) throws {
        guard let can = self.can(canID) else { throw CanSNSError.disposed }
        if isInFridge(canID: canID, ownerID: userID) { throw CanSNSError.alreadyInFridge }
        guard canSaveToFridge(can, userID: userID, today: clock.businessDay(for: now)) else {
            throw CanSNSError.cannotSaveToFridge
        }
        fridge.append(FridgeEntry(id: UUID().uuidString, ownerID: userID, canID: canID, savedAt: now))
        // プライバシーのため、保存されたことは投稿者に必ず知らせる
        notify(can.authorID, actor: userID, kind: .fridge, canID: canID,
               message: "\(name(of: userID))が「\(can.title)」を冷蔵庫に入れました", now: now)
    }

    mutating func removeFromFridge(canID: String, userID: String) {
        fridge.removeAll { $0.canID == canID && $0.ownerID == userID }
    }

    mutating func markAllRead(for userID: String) {
        for index in notifications.indices where notifications[index].recipientID == userID {
            notifications[index].isRead = true
        }
    }

    // MARK: - 内部処理

    private mutating func notify(_ recipientID: String, actor actorID: String, kind: NotificationKind,
                                 canID: String?, message: String, now: Date) {
        guard recipientID != actorID else { return }
        notifications.append(AppNotification(
            id: UUID().uuidString, recipientID: recipientID, actorID: actorID,
            kind: kind, canID: canID, message: message, createdAt: now
        ))
    }

    private func makeInviteCode() -> String {
        // 見間違えやすい 0/O, 1/I/L は使わない
        let characters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        while true {
            let code = String((0..<6).map { _ in characters.randomElement()! })
            if !machines.contains(where: { $0.inviteCode == code }) { return code }
        }
    }
}
