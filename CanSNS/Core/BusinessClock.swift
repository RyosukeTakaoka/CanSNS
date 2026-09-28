import Foundation

/// 「営業日」を表す日付。朝6:00から翌朝5:59までを1日として数える。
/// 例: 9/29 の 3:00 は、まだ 9/28 の営業日。
struct BusinessDay: Codable, Hashable, Comparable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    /// 並べ替えや保存に使う "2026-09-28" 形式の文字列
    var key: String { "\(year)-\(Self.pad(month))-\(Self.pad(day))" }
    var description: String { key }
    /// 画面表示用 "9/28"
    var shortText: String { "\(month)/\(day)" }

    static func < (lhs: BusinessDay, rhs: BusinessDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// 自販機の営業フェーズ
enum BusinessPhase: String, Codable {
    /// 6:00〜20:59 納品中（缶のラベルは見えるが、開けられない）
    case delivery
    /// 21:00〜翌5:59 営業中（缶を開けられる。納品もできる）
    case open

    var title: String {
        switch self {
        case .delivery: "納品中"
        case .open: "営業中"
        }
    }
}

/// 時刻から「営業日」「フェーズ」「廃棄時刻」などを計算する時計。
struct BusinessClock {
    /// 納品開始（＝前日の缶の廃棄）時刻
    static let dayStartHour = 6
    /// 開店時刻
    static let openHour = 21

    let calendar: Calendar

    init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// その時刻が属する営業日
    func businessDay(for date: Date) -> BusinessDay {
        let hour = calendar.component(.hour, from: date)
        var base = date
        if hour < Self.dayStartHour {
            // 0:00〜5:59 は「前の日」の営業時間中
            base = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        let c = calendar.dateComponents([.year, .month, .day], from: base)
        return BusinessDay(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    func phase(at date: Date) -> BusinessPhase {
        let hour = calendar.component(.hour, from: date)
        return (hour >= Self.dayStartHour && hour < Self.openHour) ? .delivery : .open
    }

    /// 営業日 `day` の `hour` 時ちょうど（dayOffset 日ずらせる）
    func date(of day: BusinessDay, hour: Int, dayOffset: Int = 0) -> Date {
        var c = DateComponents()
        c.year = day.year
        c.month = day.month
        c.day = day.day
        c.hour = hour
        c.minute = 0
        c.second = 0
        let base = calendar.date(from: c) ?? Date()
        if dayOffset == 0 { return base }
        return calendar.date(byAdding: .day, value: dayOffset, to: base) ?? base
    }

    func deliveryStart(of day: BusinessDay) -> Date { date(of: day, hour: Self.dayStartHour) }
    func openTime(of day: BusinessDay) -> Date { date(of: day, hour: Self.openHour) }
    /// 翌朝6:00。この時刻に自販機の缶は廃棄され、投稿者の冷蔵庫へ移る。
    func disposalTime(of day: BusinessDay) -> Date { date(of: day, hour: Self.dayStartHour, dayOffset: 1) }

    /// 次にフェーズが切り替わる時刻（納品中なら開店時刻、営業中なら廃棄時刻）
    func nextTransition(after now: Date) -> Date {
        let day = businessDay(for: now)
        switch phase(at: now) {
        case .delivery: return openTime(of: day)
        case .open: return disposalTime(of: day)
        }
    }

    /// 営業日を n 日ずらす（マイナスで過去）
    func day(_ day: BusinessDay, offsetBy n: Int) -> BusinessDay {
        businessDay(for: date(of: day, hour: 12, dayOffset: n))
    }

    /// 残り時間を "3:05:09" の形にする
    static func countdownText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let mm = m < 10 ? "0\(m)" : "\(m)"
        let ss = s < 10 ? "0\(s)" : "\(s)"
        return "\(h):\(mm):\(ss)"
    }
}
