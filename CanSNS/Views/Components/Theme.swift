import SwiftUI

extension Color {
    init(rgb: RGB) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    init(hex: UInt32) {
        self.init(rgb: RGB(hex: hex))
    }
}

enum Theme {
    /// 自販機の本体色
    static let machineBody = Color(hex: 0x2F5FB3)
    static let machineBodyDark = Color(hex: 0x1D3F80)
    static let machineTrim = Color(hex: 0xE9EEF5)
    static let panel = Color(hex: 0x172646)
    static let lampOn = Color(hex: 0x57F287)
    static let lampSoldOut = Color(hex: 0xFF4D4D)
    static let lampIdle = Color(hex: 0x4A5568)
    static let digit = Color(hex: 0xFF3B30)
    static let paper = Color(hex: 0xFFFDF7)
    static let fridgeInside = Color(hex: 0xEAF6FB)
}

extension Mood {
    var color: Color {
        switch self {
        case .cold: Color(hex: 0x1E73E8)
        case .hot: Color(hex: 0xE5352B)
        case .fizzy: Color(hex: 0x17B890)
        }
    }

    var deepColor: Color {
        switch self {
        case .cold: Color(hex: 0x0B3F99)
        case .hot: Color(hex: 0x8F1410)
        case .fizzy: Color(hex: 0x0A6E57)
        }
    }
}

/// 自販機の値段の下にある「つめた〜い」「あったか〜い」の帯
struct MoodStrip: View {
    var mood: Mood
    var fontSize: CGFloat = 12

    var body: some View {
        Text(mood.stripText)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, fontSize * 0.6)
            .padding(.vertical, fontSize * 0.2)
            .background(mood.color, in: RoundedRectangle(cornerRadius: fontSize * 0.3))
    }
}

/// 画面下にふわっと出る短いメッセージ
struct ToastView: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.8), in: Capsule())
            .padding(.horizontal, 24)
    }
}

extension View {
    /// トーストを表示する（message が nil でなければ表示し、2.2秒後に消す）
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                ToastView(message: text)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: text) {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        withAnimation { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: message.wrappedValue)
    }
}

/// カード風の背景
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

enum DateText {
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func monthDayTime(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }
}
