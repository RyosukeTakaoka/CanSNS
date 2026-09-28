import Foundation

/// 0〜1 の RGB。SwiftUI に依存しないようにするための小さな色の型。
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// "#1B2250" のような16進数から作る
    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    func mixed(with other: RGB, amount t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }
}

/// 時刻に合わせた空の色。ホーム画面の自販機の背景に使う。
enum SkyPalette {
    struct Key {
        var hour: Double
        var top: RGB
        var bottom: RGB
    }

    static let keys: [Key] = [
        Key(hour: 0, top: RGB(hex: 0x070B1F), bottom: RGB(hex: 0x1A1F4B)),   // 深夜
        Key(hour: 4.5, top: RGB(hex: 0x10163A), bottom: RGB(hex: 0x3A3470)), // 夜明け前
        Key(hour: 5.8, top: RGB(hex: 0x3D4B8C), bottom: RGB(hex: 0xF2A07B)), // 朝焼け
        Key(hour: 7.5, top: RGB(hex: 0x5FA8E8), bottom: RGB(hex: 0xCDE9F7)), // 朝
        Key(hour: 12, top: RGB(hex: 0x3D8FE0), bottom: RGB(hex: 0xA9D8F5)),  // 昼
        Key(hour: 16, top: RGB(hex: 0x4F8BD0), bottom: RGB(hex: 0xF3D2A2)),  // 夕方前
        Key(hour: 17.8, top: RGB(hex: 0x6A4C9C), bottom: RGB(hex: 0xF08A5D)), // 夕焼け
        Key(hour: 19.2, top: RGB(hex: 0x1E2458), bottom: RGB(hex: 0x6B4A8A)), // 薄暮
        Key(hour: 21, top: RGB(hex: 0x0B1030), bottom: RGB(hex: 0x252A5E)),  // 夜
        Key(hour: 24, top: RGB(hex: 0x070B1F), bottom: RGB(hex: 0x1A1F4B)),  // 深夜（0時と同じ）
    ]

    /// hour は 0〜24 の小数（例: 21.5 = 21:30）
    static func colors(hour: Double) -> (top: RGB, bottom: RGB) {
        let h = min(max(hour, 0), 24)
        for index in 0..<(keys.count - 1) {
            let a = keys[index]
            let b = keys[index + 1]
            if h >= a.hour && h <= b.hour {
                let t = (h - a.hour) / (b.hour - a.hour)
                return (a.top.mixed(with: b.top, amount: t), a.bottom.mixed(with: b.bottom, amount: t))
            }
        }
        return (keys[0].top, keys[0].bottom)
    }

    /// 夜の暗さ（0 = 昼、1 = 真夜中）。星や窓明かりの濃さに使う。
    static func nightness(hour: Double) -> Double {
        switch hour {
        case ..<4.5: return 1
        case 4.5..<6.5: return 1 - (hour - 4.5) / 2
        case 6.5..<17.5: return 0
        case 17.5..<20: return (hour - 17.5) / 2.5
        default: return 1
        }
    }
}
