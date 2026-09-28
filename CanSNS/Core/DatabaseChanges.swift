import Foundation

/// 操作の前後で「何が増えた・消えた・変わった」かのまとめ。
/// Firebase モードでは、これをもとにサーバーへ書き込む。
/// （ルールのチェックは AppDatabase の操作で1回だけ行い、同じロジックをオフラインと共有する）
struct DatabaseChanges: Equatable {
    var changedUsers: [UserProfile] = []
    var addedMachines: [Machine] = []
    var addedCans: [CanPost] = []
    var addedOpenings: [Opening] = []
    var addedReactions: [Reaction] = []
    var removedReactions: [Reaction] = []
    var addedStraws: [StrawMessage] = []
    var addedLetters: [Letter] = []
    var addedFridge: [FridgeEntry] = []
    var removedFridge: [FridgeEntry] = []
    var addedNotifications: [AppNotification] = []
    /// 未読 → 既読になったお知らせ
    var readNotifications: [AppNotification] = []

    var isEmpty: Bool { self == DatabaseChanges() }
}

extension AppDatabase {
    func changes(from old: AppDatabase) -> DatabaseChanges {
        var result = DatabaseChanges()
        let oldUsers = Dictionary(old.users.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        result.changedUsers = users.filter { oldUsers[$0.id] != $0 }
        result.addedMachines = Self.added(machines, comparedTo: old.machines)
        result.addedCans = Self.added(cans, comparedTo: old.cans)
        result.addedOpenings = Self.added(openings, comparedTo: old.openings)
        result.addedReactions = Self.added(reactions, comparedTo: old.reactions)
        result.removedReactions = Self.added(old.reactions, comparedTo: reactions)
        result.addedStraws = Self.added(straws, comparedTo: old.straws)
        result.addedLetters = Self.added(letters, comparedTo: old.letters)
        result.addedFridge = Self.added(fridge, comparedTo: old.fridge)
        result.removedFridge = Self.added(old.fridge, comparedTo: fridge)
        result.addedNotifications = Self.added(notifications, comparedTo: old.notifications)
        let oldUnread = Set(old.notifications.filter { !$0.isRead }.map(\.id))
        result.readNotifications = notifications.filter { $0.isRead && oldUnread.contains($0.id) }
        return result
    }

    /// `items` のうち、`others` に同じ id がないもの
    private static func added<T: Identifiable>(_ items: [T], comparedTo others: [T]) -> [T] where T.ID: Hashable {
        let existing = Set(others.map(\.id))
        return items.filter { !existing.contains($0.id) }
    }
}
