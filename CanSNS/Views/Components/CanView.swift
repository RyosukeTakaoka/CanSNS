import SwiftUI

/// 缶の絵（ドット絵）。ラベルの色は「今日の気分」、柄はテンプレートで決まる。
/// 中身の種類のアイコンは、開けたあとだけ出す（showsKind）。
struct CanView: View {
    var title: String
    var mood: Mood
    var kind: ContentKind
    var pattern: LabelPattern
    var emoji: String
    var width: CGFloat
    var tabOpen: Bool = false
    /// 中身の種類のアイコンを出すか（開ける前は中身がわからないように出さない）
    var showsKind: Bool = false

    init(title: String, mood: Mood, kind: ContentKind, pattern: LabelPattern,
         emoji: String, width: CGFloat, tabOpen: Bool = false, showsKind: Bool = false) {
        self.title = title
        self.mood = mood
        self.kind = kind
        self.pattern = pattern
        self.emoji = emoji
        self.width = width
        self.tabOpen = tabOpen
        self.showsKind = showsKind
    }

    init(can: CanPost, emoji: String, width: CGFloat, tabOpen: Bool = false, showsKind: Bool = false) {
        self.init(title: can.title, mood: can.mood, kind: can.kind, pattern: can.pattern,
                  emoji: emoji, width: width, tabOpen: tabOpen, showsKind: showsKind)
    }

    private var height: CGFloat { width * 1.75 }
    /// ドット1つぶんの大きさ（缶の大きさに合わせる）
    private var dot: CGFloat { max(1, (width / 14).rounded(.down)) }

    var body: some View {
        ZStack {
            // 黒い縁取り
            PixelBox(step: dot)
                .fill(Pixel.ink)
            VStack(spacing: 0) {
                topRim
                    .frame(height: height * 0.1)
                label
                    .frame(maxHeight: .infinity)
                bottomRim
                    .frame(height: height * 0.07)
            }
            .padding(dot)
        }
        .frame(width: width, height: height)
        .accessibilityElement()
        .accessibilityLabel(showsKind ? "\(title)、\(mood.stripText)、\(kind.label)" : "\(title)、\(mood.stripText)")
    }

    // MARK: - 部品

    private var silver: Color { Color(hex: 0xD9DDE3) }
    private var silverDark: Color { Color(hex: 0x8A8F99) }

    /// 上ぶたとプルタブ
    private var topRim: some View {
        ZStack {
            silver
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                silverDark.frame(height: dot)
            }
            if tabOpen {
                // 飲み口の穴
                Pixel.ink
                    .frame(width: width * 0.26, height: dot * 1.5)
            }
            Rectangle()
                .fill(Color(hex: 0xB5BAC4))
                .overlay(Rectangle().strokeBorder(silverDark, lineWidth: max(1, dot / 2)))
                .frame(width: width * 0.32, height: dot * 1.6)
                .rotation3DEffect(.degrees(tabOpen ? 70 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom)
                .offset(y: tabOpen ? -dot : 0)
        }
    }

    private var bottomRim: some View {
        ZStack {
            silver
            VStack(spacing: 0) {
                silverDark.frame(height: dot)
                Spacer(minLength: 0)
            }
        }
    }

    private var label: some View {
        ZStack {
            mood.color
            PatternOverlay(pattern: pattern)
            // 右側の影
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                mood.deepColor.frame(width: width * 0.16)
            }
            // 左側の白いハイライト（アイコンの缶と同じ）
            HStack(spacing: 0) {
                Color.clear.frame(width: width * 0.14)
                Color.white.opacity(0.8).frame(width: dot)
                Spacer(minLength: 0)
            }
            VStack(spacing: width * 0.04) {
                if showsKind {
                    Image(systemName: kind.symbol)
                        .font(.system(size: width * 0.15, weight: .bold))
                }
                Text(title)
                    .font(.pixel(width * 0.2, fixed: true))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, width * 0.1)
                Text(emoji)
                    .font(.system(size: width * 0.17))
            }
            .foregroundStyle(.white)
            .shadow(color: Pixel.ink, radius: 0, x: max(1, dot / 2), y: max(1, dot / 2))
        }
    }
}

/// まだ納品されていない枠に置く、缶の形の点線
struct EmptyCanView: View {
    var width: CGFloat
    /// 中に出す文字（「?」や「+」）
    var glyph: String = "?"
    var tint: Color = Pixel.ink

    private var dot: CGFloat { max(1, (width / 14).rounded(.down)) }

    var body: some View {
        ZStack {
            PixelBox(step: dot)
                .fill(tint.opacity(0.08))
            PixelBox(step: dot)
                .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: max(1, dot / 2), dash: [dot * 1.5, dot]))
            Text(glyph)
                .font(.pixel(width * 0.4, fixed: true))
                .foregroundStyle(tint.opacity(0.4))
        }
        .frame(width: width, height: width * 1.75)
    }
}

/// ラベルの柄（ストライプ・ドット・ウェーブ）を、ドット単位で描く
struct PatternOverlay: View {
    var pattern: LabelPattern

    var body: some View {
        Canvas { context, size in
            guard pattern != .plain, size.width > 0, size.height > 0 else { return }
            let p = max(1, (size.width / 12).rounded(.down))
            let columns = Int(size.width / p) + 1
            let rows = Int(size.height / p) + 1
            let shading = GraphicsContext.Shading.color(.white.opacity(0.22))

            for row in 0..<rows {
                for column in 0..<columns {
                    let filled: Bool
                    switch pattern {
                    case .plain:
                        filled = false
                    case .stripe:
                        // 斜めのしま
                        filled = (column + row) % 5 == 0
                    case .dots:
                        // 互い違いの四角い水玉
                        let shift = (row / 4).isMultiple(of: 2) ? 0 : 2
                        filled = row % 4 == 1 && (column + shift) % 4 == 1
                    case .wave:
                        // 5段ごとの、ガタガタの波線
                        let offset = Int((sin(Double(column) / 1.6) * 1.2).rounded())
                        let base = row - offset
                        filled = base >= 0 && base % 5 == 2
                    }
                    if filled {
                        let rect = CGRect(x: CGFloat(column) * p, y: CGFloat(row) * p, width: p, height: p)
                        context.fill(Path(rect), with: shading)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    HStack(spacing: 16) {
        CanView(title: "部活おわり", mood: .hot, kind: .photo, pattern: .wave, emoji: "🐱", width: 80, showsKind: true)
        CanView(title: "小テスト", mood: .fizzy, kind: .text, pattern: .dots, emoji: "🐶", width: 80, tabOpen: true)
        CanView(title: "帰り道", mood: .cold, kind: .voice, pattern: .stripe, emoji: "🐰", width: 80)
        EmptyCanView(width: 80)
    }
    .padding()
    .background(Color.gray)
}
