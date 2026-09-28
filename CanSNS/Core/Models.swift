import Foundation

// MARK: - ユーザー

struct UserProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// アイコン代わりの絵文字
    var emoji: String
    var createdAt: Date
    /// デモ用の「友達ボット」かどうか
    var isDemo: Bool = false
}

// MARK: - 自動販売機（＝友達グループ）

struct Membership: Codable, Hashable {
    var userID: String
    var joinedAt: Date
}

struct Machine: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// 友達を招待するためのコード（6文字）
    var inviteCode: String
    var createdAt: Date
    var members: [Membership]
    /// これまでに納品された缶の累計（自販機のレベルに使う）
    var deliveredCount: Int?

    var memberIDs: [String] { members.map(\.userID) }

    func isMember(_ userID: String) -> Bool {
        members.contains { $0.userID == userID }
    }
}

// MARK: - 缶（＝投稿）

/// 投稿者が選ぶ「今日の気分」。自販機の値段の下にある、あの色つきの帯になる。
enum Mood: String, Codable, CaseIterable, Identifiable {
    case cold
    case hot
    case fizzy

    var id: String { rawValue }

    /// 自販機の帯に書かれる文字
    var stripText: String {
        switch self {
        case .cold: "つめた〜い"
        case .hot: "あったか〜い"
        case .fizzy: "しゅわしゅわ"
        }
    }

    var meaning: String {
        switch self {
        case .cold: "おちついてる・淡々"
        case .hot: "うれしい・ほっこり"
        case .fizzy: "テンション高め・びっくり"
        }
    }
}

/// 缶の中身の種類
enum ContentKind: String, Codable, CaseIterable, Identifiable {
    case photo
    case video
    case text
    case voice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo: "写真"
        case .video: "動画"
        case .text: "ひとこと"
        case .voice: "音声"
        }
    }

    /// SF Symbols の名前
    var symbol: String {
        switch self {
        case .photo: "camera.fill"
        case .video: "video.fill"
        case .text: "text.bubble.fill"
        case .voice: "waveform"
        }
    }
}

/// 缶ラベルの柄（テンプレート）
enum LabelPattern: String, Codable, CaseIterable, Identifiable {
    case plain
    case stripe
    case dots
    case wave

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain: "無地"
        case .stripe: "ストライプ"
        case .dots: "ドット"
        case .wave: "ウェーブ"
        }
    }
}

struct CanPost: Codable, Identifiable, Hashable {
    var id: String
    var machineID: String
    var authorID: String
    /// どの営業日に納品されたか（翌朝6:00に廃棄される）
    var businessDay: BusinessDay
    var createdAt: Date
    /// タイトル ＝ 商品名
    var title: String
    var mood: Mood
    var kind: ContentKind
    /// ひとこと本文。写真・動画・音声のときは添えるコメントとして使う。
    var text: String?
    /// 端末内に保存したメディアファイル名
    var mediaFileName: String?
    /// 動画・音声の長さ（秒）
    var mediaDuration: Double?
    var pattern: LabelPattern
    /// 友達が自分の冷蔵庫に保存するのを許可するか
    var allowFridge: Bool
    /// true のとき、中身（種類・本文・メディア）をまだサーバーから受け取っていない。
    /// 開店前の友達の缶はこの状態（ラベルだけ見える）。
    var isSealed: Bool?

    var isContentHidden: Bool { isSealed == true }

    /// 中身の要約（開けたあとの「成分表示」で使う。開ける前には表示しない）
    /// 例: 「写真1枚」「動画8秒」「音声12秒」「ひとこと」
    var contentSummary: String {
        let seconds = Int((mediaDuration ?? 0).rounded())
        switch kind {
        case .photo: return "写真1枚"
        case .video: return seconds > 0 ? "動画\(seconds)秒" : "動画"
        case .voice: return seconds > 0 ? "音声\(seconds)秒" : "音声"
        case .text: return "ひとこと"
        }
    }
}

/// 納品フォームの入力内容
struct CanDraft {
    var title: String = ""
    var mood: Mood = .cold
    var kind: ContentKind = .text
    var text: String = ""
    var mediaFileName: String?
    var mediaDuration: Double?
    var pattern: LabelPattern = .plain
    var allowFridge: Bool = true

    static let titleLimit = 12
    static let textLimit = 80
    static let captionLimit = 40
}

// MARK: - 開封・リアクション

struct Opening: Codable, Identifiable, Hashable {
    var id: String
    var canID: String
    var userID: String
    var openedAt: Date
}

/// 「いいね」の代わりの、自販機らしいリアクション
enum ReactionKind: String, Codable, CaseIterable, Identifiable {
    case okawari
    case tsumetai
    case attakai
    case tansan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .okawari: "おかわり"
        case .tsumetai: "つめたいね"
        case .attakai: "あったかいね"
        case .tansan: "炭酸強め"
        }
    }

    var emoji: String {
        switch self {
        case .okawari: "🔁"
        case .tsumetai: "🧊"
        case .attakai: "☕️"
        case .tansan: "🫧"
        }
    }

    var meaning: String {
        switch self {
        case .okawari: "もう一度見たい・もっと聞きたい"
        case .tsumetai: "クール・おもしろい・淡々としてる"
        case .attakai: "共感・応援・癒やされた"
        case .tansan: "衝撃的・予想外"
        }
    }
}

struct Reaction: Codable, Identifiable, Hashable {
    var id: String
    var canID: String
    var userID: String
    var kind: ReactionKind
    var createdAt: Date
}

/// 「ストローを差す」＝投稿者と1対1でやりとりできる返信スレッド
struct StrawMessage: Codable, Identifiable, Hashable {
    var id: String
    var canID: String
    /// スレッドの相手（投稿者ではない側）のユーザーID
    var threadUserID: String
    var senderID: String
    var text: String
    var createdAt: Date

    static let textLimit = 100
}

/// 「返却口に手紙」＝投稿者だけに届く、一方通行の短いメッセージ（1缶につき1通）
struct Letter: Codable, Identifiable, Hashable {
    var id: String
    var canID: String
    var fromID: String
    var toID: String
    var text: String
    var createdAt: Date

    static let textLimit = 40
}

// MARK: - 冷蔵庫（アーカイブ）

/// 友達の缶を自分の冷蔵庫に入れた記録（自分の缶は廃棄時に自動で入る）
struct FridgeEntry: Codable, Identifiable, Hashable {
    var id: String
    var ownerID: String
    var canID: String
    var savedAt: Date
}

// MARK: - お知らせ

enum NotificationKind: String, Codable {
    case opened
    case reaction
    case straw
    case letter
    case fridge
    case memberJoined
}

struct AppNotification: Codable, Identifiable, Hashable {
    var id: String
    var recipientID: String
    var actorID: String
    var kind: NotificationKind
    var canID: String?
    var message: String
    var createdAt: Date
    var isRead: Bool = false
}
