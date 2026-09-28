import Foundation

// Firebase のライブラリが読み込めるときだけ、本物の同期処理を使う。
// （読み込めないときは下の「#else」側の空の実装になり、オフラインモードだけで動く）
#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage)
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage

enum CloudSupport {
    /// Firebase コンソールからダウンロードした GoogleService-Info.plist がアプリに入っているか
    static var isAvailable: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    static func configureIfNeeded() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }
}

// MARK: - Firestore に保存するドキュメントの形
//
// users/{uid}                                   プロフィール（machineIds に参加中の自販機）
// users/{uid}/notifications/{id}                お知らせ（本人だけ読める）
// users/{uid}/fridge/{canId}                    冷蔵庫に入れた友達の缶（本人だけ読める）
// inviteCodes/{code}                            招待コード → 自販機ID
// machines/{machineId}                          自販機
// machines/{machineId}/members/{uid}            メンバー
// machines/{machineId}/cans/{canId}             缶のラベル（メンバー全員が読める）
// machines/{machineId}/cans/{canId}/private/content  缶の中身（21:00〜翌6:00だけ読める）
// machines/{machineId}/activities/{id}          開封・リアクション
// machines/{machineId}/letters/{id}             返却口の手紙（送った人と投稿者だけ読める）
// machines/{machineId}/straws/{id}              ストロー（2人だけ読める）

private struct UserDoc: Codable {
    var id: String
    var name: String
    var emoji: String
    var createdAt: Date
    var machineIds: [String]?
}

private struct MachineDoc: Codable {
    var id: String
    var name: String
    var inviteCode: String
    var ownerId: String
    var createdAt: Date
    var deliveredCount: Int
}

private struct MemberDoc: Codable {
    var userId: String
    var joinedAt: Date
    var inviteCode: String?
}

private struct CanLabelDoc: Codable {
    var id: String
    var machineId: String
    var authorId: String
    var dayKey: String
    var day: BusinessDay
    var createdAt: Date
    var title: String
    var mood: Mood
    var pattern: LabelPattern
    var openAt: Date
    var disposeAt: Date
}

private struct CanContentDoc: Codable {
    var canId: String
    var machineId: String
    var authorId: String
    var kind: ContentKind
    var text: String?
    var mediaPath: String?
    var mediaDuration: Double?
    var allowFridge: Bool
    var openAt: Date
    var disposeAt: Date
}

private struct ActivityDoc: Codable {
    static let open = "open"
    static let reaction = "reaction"

    var id: String
    var canId: String
    var userId: String
    var type: String
    var dayKey: String
    var reaction: ReactionKind?
    var createdAt: Date
}

private struct LetterDoc: Codable {
    var id: String
    var canId: String
    var machineId: String
    var fromId: String
    var toId: String
    var text: String
    var createdAt: Date
}

private struct StrawDoc: Codable {
    var id: String
    var canId: String
    var machineId: String
    var authorId: String
    var threadUserId: String
    var senderId: String
    var participants: [String]
    var text: String
    var createdAt: Date
}

private struct FridgeDoc: Codable {
    var canId: String
    var machineId: String
    var savedAt: Date
}

private struct NotificationDoc: Codable {
    var id: String
    var recipientId: String
    var actorId: String
    var machineId: String
    var kind: NotificationKind
    var canId: String?
    var message: String
    var createdAt: Date
    var isRead: Bool
}

/// 受け取った缶の中身と、端末に保存したメディアのファイル名
private struct LoadedContent {
    var doc: CanContentDoc
    var localFileName: String?
}

// MARK: - 同期の本体

/// Firebase とアプリのデータ（AppDatabase）をつなぐクラス。
/// - 読み込み: Firestore の変更を監視し、そのたびに AppDatabase を組み立て直して `onUpdate` で渡す
/// - 書き込み: 操作の前後の差分（DatabaseChanges）を受け取り、Firestore / Storage に書き込む
@MainActor
final class CloudSync {
    enum CloudError: LocalizedError {
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "サーバーにログインできていません"
            }
        }
    }

    /// データが変わるたびに呼ばれる
    var onUpdate: ((AppDatabase) -> Void)?
    /// 書き込みに失敗したときに呼ばれる（画面にメッセージを出す用）
    var onError: ((String) -> Void)?

    private(set) var uid: String?
    /// 自分のプロフィールをサーバーに確認できたか（未登録だと分かった場合も true）
    private(set) var hasLoadedProfile = false

    private let clock: BusinessClock
    private lazy var firestore = Firestore.firestore()
    private lazy var storage = Storage.storage()

    // サーバーから受け取ったデータのキャッシュ
    private var userDocs: [String: UserDoc] = [:]
    private var machineDocs: [String: MachineDoc] = [:]
    private var memberDocs: [String: [MemberDoc]] = [:]
    private var labelDocs: [String: [String: CanLabelDoc]] = [:]
    private var contentCache: [String: LoadedContent] = [:]
    private var activityDocs: [String: [String: ActivityDoc]] = [:]
    private var letterDocs: [String: [String: LetterDoc]] = [:]
    private var strawDocs: [String: [String: StrawDoc]] = [:]
    private var fridgeDocs: [String: FridgeDoc] = [:]
    private var fridgeLabels: [String: CanLabelDoc] = [:]
    private var notificationDocs: [String: NotificationDoc] = [:]

    // 書き込み中でまだサーバーから返ってきていないもの（画面から一瞬消えないように）
    private var pendingUsers: [String: UserProfile] = [:]
    private var pendingMachines: [String: Machine] = [:]
    private var pendingCans: [String: CanPost] = [:]

    private var baseListeners: [ListenerRegistration] = []
    private var userListeners: [String: ListenerRegistration] = [:]
    private var machineListeners: [String: [ListenerRegistration]] = [:]
    /// 何日前からの缶を受け取るか（連続納品の計算に7日分必要）
    private var windowStart: BusinessDay?
    private var refreshTimer: Timer?

    init(clock: BusinessClock) {
        self.clock = clock
    }

    // MARK: ログインと監視の開始・終了

    /// 匿名ログイン（アプリを消すとアカウントも消えるので注意）
    func signIn() async throws -> String {
        if let user = Auth.auth().currentUser {
            uid = user.uid
            return user.uid
        }
        let result = try await Auth.auth().signInAnonymously()
        uid = result.user.uid
        return result.user.uid
    }

    func start() {
        guard let uid else { return }
        stop()
        windowStart = clock.day(clock.businessDay(for: Date()), offsetBy: -MachineEffect.neonStreakDays)

        baseListeners.append(userRef(uid).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated { self?.handleMyUser(snapshot) }
        })
        baseListeners.append(listen(
            userRef(uid).collection("notifications").order(by: "createdAt", descending: true).limit(to: 200)
        ) { [weak self] snapshot in
            self?.notificationDocs = Self.decodeMap(snapshot, NotificationDoc.self) { $0.id }
        })
        baseListeners.append(listen(userRef(uid).collection("fridge")) { [weak self] snapshot in
            self?.handleFridge(snapshot)
        })
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshWindowIfNeeded() }
        }
    }

    func stop() {
        baseListeners.forEach { $0.remove() }
        baseListeners = []
        userListeners.values.forEach { $0.remove() }
        userListeners = [:]
        machineListeners.values.flatMap { $0 }.forEach { $0.remove() }
        machineListeners = [:]
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: 読み込み

    private func handleMyUser(_ snapshot: DocumentSnapshot?) {
        guard let uid, let snapshot else { return }
        if snapshot.exists, let doc = try? snapshot.data(as: UserDoc.self) {
            userDocs[uid] = doc
            syncMachineListeners(Set(doc.machineIds ?? []))
            hasLoadedProfile = true
        } else if !snapshot.metadata.isFromCache {
            // サーバーに確認して、まだ登録されていないと分かった
            userDocs[uid] = nil
            syncMachineListeners([])
            hasLoadedProfile = true
        }
        rebuild()
    }

    private func handleFridge(_ snapshot: QuerySnapshot) {
        fridgeDocs = Self.decodeMap(snapshot, FridgeDoc.self) { $0.canId }
        for doc in fridgeDocs.values where fridgeLabels[doc.canId] == nil {
            Task { await self.fetchFridgeLabel(doc) }
        }
    }

    private func fetchFridgeLabel(_ doc: FridgeDoc) async {
        let ref = machineRef(doc.machineId).collection("cans").document(doc.canId)
        guard let label = try? await ref.getDocument().data(as: CanLabelDoc.self) else { return }
        fridgeLabels[doc.canId] = label
        listenToUser(label.authorId)
        rebuild()
    }

    private func syncMachineListeners(_ ids: Set<String>) {
        for (id, listeners) in machineListeners where !ids.contains(id) {
            listeners.forEach { $0.remove() }
            machineListeners[id] = nil
            clearMachineCache(id)
        }
        for id in ids where machineListeners[id] == nil {
            machineListeners[id] = makeMachineListeners(id)
        }
    }

    private func makeMachineListeners(_ machineID: String) -> [ListenerRegistration] {
        guard let uid, let windowStart else { return [] }
        let ref = machineRef(machineID)
        var listeners: [ListenerRegistration] = []

        listeners.append(ref.addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.machineDocs[machineID] = try? snapshot?.data(as: MachineDoc.self)
                self.rebuild()
            }
        })
        listeners.append(listen(ref.collection("members")) { [weak self] snapshot in
            guard let self else { return }
            let members = snapshot.documents.compactMap { try? $0.data(as: MemberDoc.self) }
            self.memberDocs[machineID] = members
            members.forEach { self.listenToUser($0.userId) }
        })
        // 最近の缶（今日の自販機と、連続納品の計算に使う）
        listeners.append(listen(
            ref.collection("cans").whereField("dayKey", isGreaterThanOrEqualTo: windowStart.key)
        ) { [weak self] snapshot in
            self?.labelDocs["\(machineID)/recent"] = Self.decodeMap(snapshot, CanLabelDoc.self) { $0.id }
        })
        // 自分の過去の缶（冷蔵庫の「じぶんの缶」）
        listeners.append(listen(ref.collection("cans").whereField("authorId", isEqualTo: uid)) { [weak self] snapshot in
            self?.labelDocs["\(machineID)/mine"] = Self.decodeMap(snapshot, CanLabelDoc.self) { $0.id }
        })
        listeners.append(listen(
            ref.collection("activities").whereField("dayKey", isGreaterThanOrEqualTo: windowStart.key)
        ) { [weak self] snapshot in
            self?.activityDocs[machineID] = Self.decodeMap(snapshot, ActivityDoc.self) { $0.id }
        })
        listeners.append(listen(ref.collection("letters").whereField("toId", isEqualTo: uid)) { [weak self] snapshot in
            self?.letterDocs["\(machineID)/to"] = Self.decodeMap(snapshot, LetterDoc.self) { $0.id }
        })
        listeners.append(listen(ref.collection("letters").whereField("fromId", isEqualTo: uid)) { [weak self] snapshot in
            self?.letterDocs["\(machineID)/from"] = Self.decodeMap(snapshot, LetterDoc.self) { $0.id }
        })
        listeners.append(listen(
            ref.collection("straws").whereField("participants", arrayContains: uid)
        ) { [weak self] snapshot in
            self?.strawDocs[machineID] = Self.decodeMap(snapshot, StrawDoc.self) { $0.id }
        })
        return listeners
    }

    private func listenToUser(_ userID: String) {
        guard userListeners[userID] == nil, userID != uid else { return }
        userListeners[userID] = userRef(userID).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.userDocs[userID] = try? snapshot?.data(as: UserDoc.self)
                self.rebuild()
            }
        }
    }

    /// 日付が変わったら、受け取る缶の範囲を更新する
    private func refreshWindowIfNeeded() {
        let start = clock.day(clock.businessDay(for: Date()), offsetBy: -MachineEffect.neonStreakDays)
        guard start != windowStart else { return }
        windowStart = start
        for id in Array(machineListeners.keys) {
            machineListeners[id]?.forEach { $0.remove() }
            machineListeners[id] = makeMachineListeners(id)
        }
    }

    private func clearMachineCache(_ machineID: String) {
        machineDocs[machineID] = nil
        memberDocs[machineID] = nil
        activityDocs[machineID] = nil
        strawDocs[machineID] = nil
        for key in Array(labelDocs.keys) where key.hasPrefix("\(machineID)/") {
            labelDocs[key] = nil
        }
        for key in Array(letterDocs.keys) where key.hasPrefix("\(machineID)/") {
            letterDocs[key] = nil
        }
    }

    /// 缶の中身を受け取る（21:00前の友達の缶は、サーバーのルールで拒否される）
    func loadContent(canID: String, machineID: String) async throws {
        guard contentCache[canID] == nil else { return }
        let ref = machineRef(machineID).collection("cans").document(canID).collection("private").document("content")
        let doc = try await ref.getDocument().data(as: CanContentDoc.self)
        var localName: String?
        if let path = doc.mediaPath {
            let ext = (path as NSString).pathExtension
            let name = "\(canID).\(ext.isEmpty ? "dat" : ext)"
            let url = MediaStore.url(for: name)
            if !FileManager.default.fileExists(atPath: url.path) {
                _ = try await storage.reference(withPath: path).writeAsync(toFile: url)
            }
            localName = name
        }
        contentCache[canID] = LoadedContent(doc: doc, localFileName: localName)
        rebuild()
    }

    // MARK: AppDatabase を組み立て直す

    private func rebuild() {
        guard let uid else { return }
        var db = AppDatabase()

        var users: [String: UserProfile] = pendingUsers
        for doc in userDocs.values {
            users[doc.id] = UserProfile(id: doc.id, name: doc.name, emoji: doc.emoji, createdAt: doc.createdAt)
            pendingUsers[doc.id] = nil
        }
        db.users = Array(users.values)

        var machines: [String: Machine] = pendingMachines
        for doc in machineDocs.values {
            let members = (memberDocs[doc.id] ?? []).sorted { $0.joinedAt < $1.joinedAt }
            machines[doc.id] = Machine(
                id: doc.id, name: doc.name, inviteCode: doc.inviteCode, createdAt: doc.createdAt,
                members: members.map { Membership(userID: $0.userId, joinedAt: $0.joinedAt) },
                deliveredCount: doc.deliveredCount
            )
            if !members.isEmpty { pendingMachines[doc.id] = nil }
        }
        db.machines = machines.values.sorted { $0.createdAt < $1.createdAt }

        var cans: [String: CanPost] = pendingCans
        for group in labelDocs.values {
            for label in group.values {
                cans[label.id] = makeCan(label)
                pendingCans[label.id] = nil
            }
        }
        for label in fridgeLabels.values where cans[label.id] == nil {
            cans[label.id] = makeCan(label)
        }
        db.cans = cans.values.sorted { $0.createdAt < $1.createdAt }

        let activities = activityDocs.values.flatMap { $0.values }
        db.openings = activities.filter { $0.type == ActivityDoc.open }.map {
            Opening(id: $0.id, canID: $0.canId, userID: $0.userId, openedAt: $0.createdAt)
        }
        db.reactions = activities.compactMap { activity in
            activity.reaction.map {
                Reaction(id: activity.id, canID: activity.canId, userID: activity.userId, kind: $0,
                         createdAt: activity.createdAt)
            }
        }

        var letters: [String: LetterDoc] = [:]
        for group in letterDocs.values {
            letters.merge(group) { first, _ in first }
        }
        db.letters = letters.values.map {
            Letter(id: $0.id, canID: $0.canId, fromID: $0.fromId, toID: $0.toId, text: $0.text, createdAt: $0.createdAt)
        }
        db.straws = strawDocs.values.flatMap { $0.values }.map {
            StrawMessage(id: $0.id, canID: $0.canId, threadUserID: $0.threadUserId, senderID: $0.senderId,
                         text: $0.text, createdAt: $0.createdAt)
        }
        db.fridge = fridgeDocs.values.map {
            FridgeEntry(id: $0.canId, ownerID: uid, canID: $0.canId, savedAt: $0.savedAt)
        }
        db.notifications = notificationDocs.values.map {
            AppNotification(id: $0.id, recipientID: uid, actorID: $0.actorId, kind: $0.kind, canID: $0.canId,
                            message: $0.message, createdAt: $0.createdAt, isRead: $0.isRead)
        }
        onUpdate?(db)
    }

    private func makeCan(_ label: CanLabelDoc) -> CanPost {
        let content = contentCache[label.id]
        return CanPost(
            id: label.id,
            machineID: label.machineId,
            authorID: label.authorId,
            businessDay: label.day,
            createdAt: label.createdAt,
            title: label.title,
            mood: label.mood,
            kind: content?.doc.kind ?? .text,
            text: content?.doc.text,
            mediaFileName: content?.localFileName,
            mediaDuration: content?.doc.mediaDuration,
            pattern: label.pattern,
            allowFridge: content?.doc.allowFridge ?? false,
            isSealed: content == nil ? true : nil
        )
    }

    // MARK: 書き込み

    /// 操作の差分をサーバーに書き込む
    func apply(_ changes: DatabaseChanges, db: AppDatabase, currentMachineID: String?) {
        guard let uid else {
            onError?(CloudError.notSignedIn.localizedDescription)
            return
        }

        for user in changes.changedUsers where user.id == uid {
            pendingUsers[uid] = user
            let data: [String: Any] = ["id": uid, "name": user.name, "emoji": user.emoji, "createdAt": user.createdAt]
            userRef(uid).setData(data, merge: true, completion: completion("プロフィールの保存"))
        }

        for machine in changes.addedMachines {
            pendingMachines[machine.id] = machine
            createMachine(machine, uid: uid)
        }

        for can in changes.addedCans {
            pendingCans[can.id] = can
            Task { await self.uploadCan(can) }
        }

        for opening in changes.addedOpenings {
            guard let can = db.can(opening.canID) else { continue }
            let doc = ActivityDoc(id: opening.id, canId: can.id, userId: opening.userID, type: ActivityDoc.open,
                                  dayKey: can.businessDay.key, reaction: nil, createdAt: opening.openedAt)
            write(doc, to: activityRef(can.machineID, opening.id), label: "開封の記録")
        }

        for reaction in changes.addedReactions {
            guard let can = db.can(reaction.canID) else { continue }
            let doc = ActivityDoc(id: reaction.id, canId: can.id, userId: reaction.userID, type: ActivityDoc.reaction,
                                  dayKey: can.businessDay.key, reaction: reaction.kind, createdAt: reaction.createdAt)
            write(doc, to: activityRef(can.machineID, reaction.id), label: "リアクション")
        }

        for reaction in changes.removedReactions {
            guard let can = db.can(reaction.canID) else { continue }
            activityRef(can.machineID, reaction.id).delete(completion: completion("リアクションの取り消し"))
        }

        for straw in changes.addedStraws {
            guard let can = db.can(straw.canID) else { continue }
            let doc = StrawDoc(id: straw.id, canId: can.id, machineId: can.machineID, authorId: can.authorID,
                               threadUserId: straw.threadUserID, senderId: straw.senderID,
                               participants: [can.authorID, straw.threadUserID], text: straw.text,
                               createdAt: straw.createdAt)
            write(doc, to: machineRef(can.machineID).collection("straws").document(straw.id), label: "ストロー")
        }

        for letter in changes.addedLetters {
            guard let can = db.can(letter.canID) else { continue }
            let doc = LetterDoc(id: letter.id, canId: can.id, machineId: can.machineID, fromId: letter.fromID,
                                toId: letter.toID, text: letter.text, createdAt: letter.createdAt)
            write(doc, to: machineRef(can.machineID).collection("letters").document(letter.id), label: "手紙")
        }

        for entry in changes.addedFridge {
            guard let can = db.can(entry.canID) else { continue }
            fridgeLabels[can.id] = labelDoc(for: can)
            let doc = FridgeDoc(canId: can.id, machineId: can.machineID, savedAt: entry.savedAt)
            write(doc, to: userRef(uid).collection("fridge").document(can.id), label: "冷蔵庫")
        }

        for entry in changes.removedFridge {
            userRef(uid).collection("fridge").document(entry.canID).delete(completion: completion("冷蔵庫から出す"))
        }

        for notification in changes.addedNotifications where notification.recipientID != uid {
            let machineID = notification.canID.flatMap { db.can($0)?.machineID } ?? currentMachineID
            guard let machineID else { continue }
            let doc = NotificationDoc(id: notification.id, recipientId: notification.recipientID,
                                      actorId: notification.actorID, machineId: machineID, kind: notification.kind,
                                      canId: notification.canID, message: notification.message,
                                      createdAt: notification.createdAt, isRead: false)
            write(doc, to: userRef(notification.recipientID).collection("notifications").document(notification.id),
                  label: "お知らせ")
        }

        for notification in changes.readNotifications where notification.recipientID == uid {
            userRef(uid).collection("notifications").document(notification.id)
                .updateData(["isRead": true], completion: completion("既読"))
        }
    }

    private func createMachine(_ machine: Machine, uid: String) {
        let ref = machineRef(machine.id)
        let doc = MachineDoc(id: machine.id, name: machine.name, inviteCode: machine.inviteCode, ownerId: uid,
                             createdAt: machine.createdAt, deliveredCount: 0)
        let batch = firestore.batch()
        do {
            try batch.setData(from: doc, forDocument: ref)
            try batch.setData(from: MemberDoc(userId: uid, joinedAt: machine.createdAt, inviteCode: nil),
                              forDocument: ref.collection("members").document(uid))
        } catch {
            onError?("自販機の作成に失敗しました")
            return
        }
        batch.setData(["machineId": machine.id], forDocument: firestore.collection("inviteCodes").document(machine.inviteCode))
        batch.setData(["machineIds": FieldValue.arrayUnion([machine.id])], forDocument: userRef(uid), merge: true)
        batch.commit(completion: completion("自販機の作成"))
    }

    /// 缶を納品する：メディアを Storage に上げてから、ラベルと中身を Firestore に書く
    private func uploadCan(_ can: CanPost) async {
        do {
            var mediaPath: String?
            if let fileName = can.mediaFileName {
                let path = "machines/\(can.machineID)/cans/\(can.id)/\(fileName)"
                _ = try await storage.reference(withPath: path).putFileAsync(from: MediaStore.url(for: fileName))
                mediaPath = path
            }
            let label = labelDoc(for: can)
            let content = CanContentDoc(
                canId: can.id, machineId: can.machineID, authorId: can.authorID, kind: can.kind, text: can.text,
                mediaPath: mediaPath, mediaDuration: can.mediaDuration, allowFridge: can.allowFridge,
                openAt: label.openAt, disposeAt: label.disposeAt
            )
            contentCache[can.id] = LoadedContent(doc: content, localFileName: can.mediaFileName)

            let canRef = machineRef(can.machineID).collection("cans").document(can.id)
            let batch = firestore.batch()
            try batch.setData(from: label, forDocument: canRef)
            try batch.setData(from: content, forDocument: canRef.collection("private").document("content"))
            batch.updateData(["deliveredCount": FieldValue.increment(Int64(1))], forDocument: machineRef(can.machineID))
            try await batch.commit()
        } catch {
            print("納品の送信に失敗:", error.localizedDescription)
            pendingCans[can.id] = nil
            contentCache[can.id] = nil
            rebuild()
            onError?("納品に失敗しました。通信環境を確認してもう一度ためしてください")
        }
    }

    /// 招待コードで自販機に参加する
    func join(inviteCode: String, userName: String) async throws -> String {
        guard let uid else { throw CloudError.notSignedIn }
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { throw CanSNSError.invalidInviteCode }
        let invite = try await firestore.collection("inviteCodes").document(code).getDocument()
        guard let machineID = invite.data()?["machineId"] as? String else { throw CanSNSError.invalidInviteCode }
        if userDocs[uid]?.machineIds?.contains(machineID) == true { throw CanSNSError.alreadyMember }

        let ref = machineRef(machineID)
        let now = Date()
        let member = try Firestore.Encoder().encode(MemberDoc(userId: uid, joinedAt: now, inviteCode: code))
        try await ref.collection("members").document(uid).setData(member)
        try await userRef(uid).setData(["machineIds": FieldValue.arrayUnion([machineID])], merge: true)

        // ほかのメンバーに「新しい仲間が来た」とお知らせ（新商品入荷）
        let machineName = (try? await ref.getDocument().data(as: MachineDoc.self))?.name ?? "自販機"
        let members = try await ref.collection("members").getDocuments()
        for document in members.documents where document.documentID != uid {
            let doc = NotificationDoc(
                id: UUID().uuidString, recipientId: document.documentID, actorId: uid, machineId: machineID,
                kind: .memberJoined, canId: nil, message: "\(userName)が「\(machineName)」に参加しました。新商品入荷！",
                createdAt: now, isRead: false
            )
            write(doc, to: userRef(document.documentID).collection("notifications").document(doc.id), label: "お知らせ")
        }
        return machineID
    }

    // MARK: 小さな道具

    private func userRef(_ id: String) -> DocumentReference {
        firestore.collection("users").document(id)
    }

    private func machineRef(_ id: String) -> DocumentReference {
        firestore.collection("machines").document(id)
    }

    private func activityRef(_ machineID: String, _ id: String) -> DocumentReference {
        machineRef(machineID).collection("activities").document(id)
    }

    private func labelDoc(for can: CanPost) -> CanLabelDoc {
        CanLabelDoc(
            id: can.id, machineId: can.machineID, authorId: can.authorID, dayKey: can.businessDay.key,
            day: can.businessDay, createdAt: can.createdAt, title: can.title, mood: can.mood, pattern: can.pattern,
            openAt: clock.openTime(of: can.businessDay), disposeAt: clock.disposalTime(of: can.businessDay)
        )
    }

    private func listen(_ query: Query, _ apply: @escaping @MainActor (QuerySnapshot) -> Void) -> ListenerRegistration {
        query.addSnapshotListener { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                if let error {
                    print("Firestore の読み込みに失敗:", error.localizedDescription)
                }
                guard let self, let snapshot else { return }
                apply(snapshot)
                self.rebuild()
            }
        }
    }

    private func write<T: Encodable>(_ value: T, to ref: DocumentReference, label: String) {
        do {
            try ref.setData(from: value, completion: completion(label))
        } catch {
            onError?("\(label)の保存に失敗しました")
        }
    }

    private func completion(_ label: String) -> (Error?) -> Void {
        { [weak self] error in
            guard let error else { return }
            print("Firestore(\(label)):", error.localizedDescription)
            MainActor.assumeIsolated {
                self?.onError?("\(label)に失敗しました")
            }
        }
    }

    private static func decodeMap<T: Decodable>(_ snapshot: QuerySnapshot, _ type: T.Type,
                                                key: (T) -> String) -> [String: T] {
        var result: [String: T] = [:]
        for document in snapshot.documents {
            if let value = try? document.data(as: T.self) {
                result[key(value)] = value
            }
        }
        return result
    }
}

#else

// Firebase のライブラリがないとき用の空の実装（オフラインモードだけで動く）
enum CloudSupport {
    static var isAvailable: Bool { false }
    static func configureIfNeeded() {}
}

@MainActor
final class CloudSync {
    var onUpdate: ((AppDatabase) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var uid: String?
    private(set) var hasLoadedProfile = false

    init(clock: BusinessClock) {}

    func signIn() async throws -> String { throw CanSNSError.userNotFound }
    func start() {}
    func stop() {}
    func loadContent(canID: String, machineID: String) async throws {}
    func apply(_ changes: DatabaseChanges, db: AppDatabase, currentMachineID: String?) {}
    func join(inviteCode: String, userName: String) async throws -> String { throw CanSNSError.invalidInviteCode }
}

#endif
